import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'adb_key.dart';

/// One message on the adb wire.
///
/// Twenty-four bytes of header and then the payload. The "checksum" is a
/// plain sum of the payload bytes, not a CRC despite what the field is
/// called in every description of the protocol; and the magic is the command
/// with every bit flipped, which is how a reader resynchronises.
@visibleForTesting
class AdbMessage {
  AdbMessage(this.command, this.arg0, this.arg1, this.payload);

  final int command;
  final int arg0;
  final int arg1;
  final Uint8List payload;

  static const connect = 0x4e584e43; // CNXN
  static const auth = 0x48545541; // AUTH
  static const open = 0x4e45504f; // OPEN
  static const okay = 0x59414b4f; // OKAY
  static const close = 0x45534c43; // CLSE
  static const write = 0x45545257; // WRTE

  static const authToken = 1;
  static const authSignature = 2;
  static const authPublicKey = 3;

  Uint8List encode() {
    final out = BytesBuilder();
    final header = ByteData(24);
    header.setUint32(0, command, Endian.little);
    header.setUint32(4, arg0, Endian.little);
    header.setUint32(8, arg1, Endian.little);
    header.setUint32(12, payload.length, Endian.little);
    header.setUint32(16, checksumOf(payload), Endian.little);
    header.setUint32(20, (command ^ 0xffffffff) & 0xffffffff, Endian.little);
    out.add(header.buffer.asUint8List());
    out.add(payload);
    return out.toBytes();
  }

  static int checksumOf(Uint8List payload) {
    var sum = 0;
    for (final byte in payload) {
      sum = (sum + byte) & 0xffffffff;
    }
    return sum;
  }

  /// True when a header's magic agrees with its command. A header that fails
  /// this is not a message; it is the middle of one.
  static bool headerIsSane(Uint8List header) {
    if (header.length < 24) return false;
    final view = ByteData.sublistView(header);
    final command = view.getUint32(0, Endian.little);
    final magic = view.getUint32(20, Endian.little);
    return magic == ((command ^ 0xffffffff) & 0xffffffff);
  }

  String get text => utf8.decode(payload, allowMalformed: true);

  @override
  String toString() =>
      '${String.fromCharCodes(_commandBytes)}(${arg0.toRadixString(16)}, '
      '${arg1.toRadixString(16)}, ${payload.length}B)';

  List<int> get _commandBytes => [
        command & 0xff,
        (command >> 8) & 0xff,
        (command >> 16) & 0xff,
        (command >> 24) & 0xff,
      ];
}

/// How an attempt to reach a device ended.
enum AdbStatus {
  /// Connected and authenticated.
  connected,

  /// The device is showing its "Allow debugging?" dialog, or has already
  /// been shown our key and refused. Either way the answer is on the other
  /// screen, not here.
  awaitingApproval,

  /// Nothing answered on that address and port.
  unreachable,

  /// Something answered but did not speak adb.
  refused,
}

class AdbResult {
  const AdbResult(this.status, [this.detail = '']);

  final AdbStatus status;
  final String detail;

  bool get ok => status == AdbStatus.connected;
}

/// Talks adb to a device over TCP, with no adb binary anywhere.
///
/// This is what makes an Android television controllable from a phone. The
/// desktop app could shell out to `adb`; a phone has no adb to shell out to,
/// and the honest answer is not "use the desktop app" but to speak the
/// protocol, which is small: a handshake, a challenge signed with an RSA
/// key, and then streams identified by a pair of integers.
///
/// It speaks to anything running adbd on a TCP port — an Android TV with
/// network debugging on, a phone with wireless debugging on, an emulator.
/// For a computer, which runs an adb *server* rather than a device daemon
/// and speaks an entirely different protocol on 5037, see [AdbHost].
class AdbClient {
  AdbClient._(this._socket, this._key, this.address, this.port);

  final Socket _socket;
  final AdbKey _key;
  final String address;
  final int port;

  /// Read side of the socket, turned into messages.
  final _incoming = StreamController<AdbMessage>.broadcast();
  final BytesBuilder _buffer = BytesBuilder();
  StreamSubscription<Uint8List>? _reads;

  /// What adbd said about itself once it let us in — model, product and the
  /// features it supports.
  String banner = '';

  var _nextStream = 1;
  var _closed = false;

  bool get isOpen => !_closed;

  /// How long to wait for a device to answer. Generous: a television that
  /// has just been woken can take a moment, and the alternative to waiting
  /// is telling the user it is unreachable when it is not.
  static const _timeout = Duration(seconds: 10);

  /// Connects and authenticates.
  ///
  /// Returns [AdbStatus.awaitingApproval] rather than an error when the
  /// device is asking its owner — that is not a failure, it is the protocol
  /// working, and the caller should say "look at the television" rather than
  /// "could not connect".
  static Future<(AdbResult, AdbClient?)> connect(String address,
      {int port = 5555}) async {
    final key = await AdbKey.load();
    Socket socket;
    try {
      socket = await Socket.connect(address, port, timeout: _timeout);
    } on SocketException catch (error) {
      return (AdbResult(AdbStatus.unreachable, error.message), null);
    } on TimeoutException {
      return (const AdbResult(AdbStatus.unreachable, 'No answer.'), null);
    }
    socket.setOption(SocketOption.tcpNoDelay, true);
    final client = AdbClient._(socket, key, address, port);
    client._listen();
    final result = await client._handshake();
    if (!result.ok) {
      await client.close();
      return (result, null);
    }
    return (result, client);
  }

  void _listen() {
    _reads = _socket.listen(
      _onBytes,
      onError: (Object _) => _fail(),
      onDone: _fail,
      cancelOnError: true,
    );
  }

  void _fail() {
    if (_closed) return;
    _closed = true;
    if (!_incoming.isClosed) _incoming.close();
  }

  /// Reassembles messages from the stream.
  ///
  /// TCP gives no message boundaries, and adbd is free to put a header and
  /// its payload in separate segments, or several messages in one. Anything
  /// that reads a fixed number of bytes and hopes works on a desk and fails
  /// on a wireless television.
  void _onBytes(Uint8List chunk) {
    _buffer.add(chunk);
    while (true) {
      final bytes = _buffer.toBytes();
      if (bytes.length < 24) return;
      if (!AdbMessage.headerIsSane(bytes)) {
        // Not a header. There is no way to recover a stream that has lost
        // its place, so say so rather than pretending.
        debugPrint('[adb] out of step with the stream; dropping the link');
        _fail();
        return;
      }
      final view = ByteData.sublistView(bytes);
      final length = view.getUint32(12, Endian.little);
      if (bytes.length < 24 + length) return;
      final message = AdbMessage(
        view.getUint32(0, Endian.little),
        view.getUint32(4, Endian.little),
        view.getUint32(8, Endian.little),
        Uint8List.sublistView(bytes, 24, 24 + length),
      );
      _buffer
        ..clear()
        ..add(Uint8List.sublistView(bytes, 24 + length));
      if (!_incoming.isClosed) _incoming.add(message);
    }
  }

  void _send(AdbMessage message) {
    if (_closed) return;
    _socket.add(message.encode());
  }

  Future<AdbResult> _handshake() async {
    final done = Completer<AdbResult>();
    var signaturesTried = 0;

    // Listening is set up before a byte goes out. [_incoming] is a broadcast
    // stream, and a broadcast stream throws away anything that arrives while
    // nobody is listening — so sending first and subscribing afterwards is a
    // race that loses the challenge on a fast local network and wins on a
    // slow one, which is the worst way for a bug to behave.
    final subscription = _incoming.stream.listen((message) {
      if (done.isCompleted) return;
      switch (message.command) {
        case AdbMessage.connect:
          banner = message.text.replaceAll('\x00', '');
          done.complete(const AdbResult(AdbStatus.connected));
        case AdbMessage.auth:
          if (message.arg0 != AdbMessage.authToken) return;
          if (signaturesTried == 0) {
            // First ask: sign it. If the device already knows this key —
            // "always allow" was ticked once — this is the whole exchange.
            signaturesTried++;
            _send(AdbMessage(AdbMessage.auth, AdbMessage.authSignature, 0,
                _key.sign(message.payload)));
          } else {
            // The signature was not recognised, so this key is new to the
            // device. Offer the public key; adbd then puts the question to
            // whoever is sitting in front of it.
            _send(AdbMessage(
              AdbMessage.auth,
              AdbMessage.authPublicKey,
              0,
              Uint8List.fromList(utf8.encode('${_key.androidPublicKey}\x00')),
            ));
            done.complete(const AdbResult(
              AdbStatus.awaitingApproval,
              'The device is asking whether to allow this. Say yes on its '
              'screen — tick "always allow" and it will not ask again.',
            ));
          }
        default:
          // Anything else at this point is not a device we can talk to.
          done.complete(AdbResult(AdbStatus.refused, 'Unexpected $message.'));
      }
    }, onDone: () {
      if (!done.isCompleted) {
        done.complete(const AdbResult(AdbStatus.unreachable,
            'The device stopped answering during the handshake.'));
      }
    });

    // Version 0x01000001 and 256 kB is what every adbd since 2017 offers.
    // The banner names us; it is not checked, but it is what the device
    // shows in its dialog.
    _send(AdbMessage(AdbMessage.connect, 0x01000001, 256 * 1024,
        Uint8List.fromList(utf8.encode('host::chatnyto\x00'))));

    try {
      return await done.future.timeout(
        _timeout,
        onTimeout: () => const AdbResult(
            AdbStatus.unreachable, 'The device did not answer in time.'),
      );
    } finally {
      await subscription.cancel();
    }
  }

  /// Runs a shell command and returns everything it printed.
  ///
  /// One stream per command, which is what `adb shell <cmd>` does too: adbd
  /// runs it, writes the output, and closes. Nothing is kept open between
  /// calls, so a television that goes to sleep costs one failed command
  /// rather than a wedged connection.
  Future<String> shell(String command) =>
      _stream('shell:$command').timeout(_timeout, onTimeout: () => '');

  /// Presses a key, by Android keycode.
  Future<String> keyEvent(int code) => shell('input keyevent $code');

  Future<String> _stream(String service) async {
    if (_closed) return '';
    final local = _nextStream++;
    final output = StringBuffer();
    final done = Completer<String>();
    var remote = 0;

    final subscription = _incoming.stream.listen((message) {
      // Every message in a stream carries our own id in arg1, so this is
      // the whole of the routing: anything else belongs to another stream.
      if (message.arg1 != local) return;
      switch (message.command) {
        case AdbMessage.okay:
          remote = message.arg0;
        case AdbMessage.write:
          output.write(message.text);
          // Every WRTE has to be acknowledged or adbd stops sending after
          // one window's worth, and the command appears to hang half-read.
          _send(AdbMessage(AdbMessage.okay, local, message.arg0,
              Uint8List(0)));
        case AdbMessage.close:
          _send(AdbMessage(AdbMessage.close, local, remote, Uint8List(0)));
          if (!done.isCompleted) done.complete(output.toString());
      }
    }, onDone: () {
      if (!done.isCompleted) done.complete(output.toString());
    });

    _send(AdbMessage(AdbMessage.open, local, 0,
        Uint8List.fromList(utf8.encode('$service\x00'))));
    try {
      return await done.future;
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> close() async {
    _closed = true;
    await _reads?.cancel();
    if (!_incoming.isClosed) await _incoming.close();
    try {
      await _socket.close();
    } catch (_) {
      // Already gone.
    }
    _socket.destroy();
  }
}

/// Talks to an adb *server* — the thing `adb` starts on a computer and keeps
/// running on port 5037.
///
/// A completely different protocol from [AdbClient], which is the part that
/// surprises people: the server speaks a text protocol where every request
/// is its own length in four hexadecimal digits followed by the request, and
/// the reply begins OKAY or FAIL. There is no authentication at all, which
/// is why adb binds it to localhost — reaching it from a phone means the
/// computer was told to listen wider (`adb -a nodaemon server`) or the port
/// was forwarded over ssh. Both are deliberate acts by whoever owns the
/// computer, which is the right place for that decision.
///
/// What it buys: every device that computer can see, from the phone. One
/// connection, any number of devices behind it — phones on its USB ports,
/// televisions it has paired with, emulators.
class AdbHost {
  AdbHost(this.address, {this.port = 5037});

  final String address;
  final int port;

  static const _timeout = Duration(seconds: 8);

  /// The devices that computer is attached to.
  Future<List<AdbDevice>> devices() async {
    final reply = await _ask('host:devices-l');
    return reply
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map(AdbDevice.parse)
        .whereType<AdbDevice>()
        .toList();
  }

  /// Runs a shell command on one of them.
  Future<String> shell(String serial, String command) async {
    final socket = await _open();
    try {
      if (!await _request(socket, 'host:transport:$serial')) {
        return 'No such device: $serial';
      }
      if (!await _request(socket, 'shell:$command')) {
        return 'The computer refused to run that.';
      }
      // Past the second OKAY the socket is the command's own output, until
      // it closes.
      final out = StringBuffer();
      await for (final chunk in socket.timeout(_timeout)) {
        out.write(utf8.decode(chunk, allowMalformed: true));
      }
      return out.toString();
    } on TimeoutException {
      return '';
    } finally {
      socket.destroy();
    }
  }

  /// Asks the computer to attach a device over the network — the same thing
  /// as typing `adb connect`.
  Future<String> connectDevice(String target) => _ask('host:connect:$target');

  Future<String> disconnectDevice(String target) =>
      _ask('host:disconnect:$target');

  Future<Socket> _open() async {
    final socket = await Socket.connect(address, port, timeout: _timeout);
    socket.setOption(SocketOption.tcpNoDelay, true);
    return socket;
  }

  /// A request whose answer is one length-prefixed string.
  Future<String> _ask(String service) async {
    Socket socket;
    try {
      socket = await _open();
    } on SocketException catch (error) {
      return 'Could not reach the adb server: ${error.message}';
    } on TimeoutException {
      return 'The adb server did not answer.';
    }
    final reader = _Reader(socket);
    try {
      socket.add(_frame(service));
      final status = await reader.take(4);
      if (status != 'OKAY') {
        final length = int.tryParse(await reader.take(4), radix: 16) ?? 0;
        return length == 0 ? 'Refused.' : await reader.take(length);
      }
      final length = int.tryParse(await reader.take(4), radix: 16) ?? 0;
      return length == 0 ? '' : await reader.take(length);
    } on TimeoutException {
      return 'The adb server stopped answering.';
    } finally {
      socket.destroy();
    }
  }

  /// A request on a socket that stays open afterwards.
  Future<bool> _request(Socket socket, String service) async {
    socket.add(_frame(service));
    final reader = _Reader(socket);
    final status = await reader.take(4);
    if (status != 'OKAY') return false;
    // Whatever the reader buffered past the status belongs to the next
    // stage, so hand it back rather than dropping it.
    _leftovers = reader.rest;
    return true;
  }

  String _leftovers = '';

  /// Anything read past a request's reply, for the caller that follows.
  String get leftovers => _leftovers;

  static Uint8List _frame(String service) => Uint8List.fromList(
      utf8.encode('${service.length.toRadixString(16).padLeft(4, '0')}'
          '$service'));
}

/// Reads a socket a fixed number of characters at a time, keeping whatever
/// arrived early.
class _Reader {
  _Reader(Stream<Uint8List> socket) {
    _subscription = socket.listen((chunk) {
      _buffer.write(utf8.decode(chunk, allowMalformed: true));
      _pump();
    }, onDone: () {
      _done = true;
      _pump();
    }, onError: (Object _) {
      _done = true;
      _pump();
    });
  }

  late final StreamSubscription<Uint8List> _subscription;
  final StringBuffer _buffer = StringBuffer();
  Completer<String>? _waiting;
  int _wanted = 0;
  bool _done = false;

  String get rest => _buffer.toString();

  Future<String> take(int count) {
    _wanted = count;
    _waiting = Completer<String>();
    _pump();
    return _waiting!.future.timeout(const Duration(seconds: 8), onTimeout: () {
      _subscription.cancel();
      return '';
    });
  }

  void _pump() {
    final waiting = _waiting;
    if (waiting == null || waiting.isCompleted) return;
    final held = _buffer.toString();
    if (held.length < _wanted && !_done) return;
    final taken = held.length < _wanted ? held : held.substring(0, _wanted);
    _buffer
      ..clear()
      ..write(held.substring(taken.length));
    _waiting = null;
    waiting.complete(taken);
  }
}

/// One device an adb server can see.
class AdbDevice {
  const AdbDevice({
    required this.serial,
    required this.state,
    this.model = '',
    this.product = '',
  });

  final String serial;

  /// 'device', 'unauthorized', 'offline'. Worth showing verbatim: each one
  /// means something different about what to do next.
  final String state;
  final String model;
  final String product;

  bool get usable => state == 'device';

  String get label => model.isNotEmpty ? model.replaceAll('_', ' ') : serial;

  /// Parses one line of `adb devices -l`.
  static AdbDevice? parse(String line) {
    if (line.startsWith('List of devices')) return null;
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 2) return null;
    String field(String name) => parts
        .firstWhere((p) => p.startsWith('$name:'), orElse: () => '')
        .replaceFirst('$name:', '');
    return AdbDevice(
      serial: parts[0],
      state: parts[1],
      model: field('model'),
      product: field('product'),
    );
  }
}
