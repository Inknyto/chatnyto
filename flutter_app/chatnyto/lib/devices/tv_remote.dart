import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'adb/adb_client.dart';
import 'device.dart';

/// What happened when a key was sent.
class RemoteResult {
  const RemoteResult.ok()
      : failed = false,
        message = '';
  const RemoteResult.failed(this.message) : failed = true;

  final bool failed;
  final String message;
}

/// Speaks each television's own remote-control protocol over the local
/// network.
///
/// None of these are MQTT and none of them go through a broker: a television
/// bought before any of this existed is not going to learn a new protocol,
/// so the app learns theirs. All four are on the LAN, which is the point —
/// the remote keeps working with the internet unplugged.
///
///  * **Roku** publishes ECP: an unauthenticated HTTP API on port 8060.
///    Nothing to pair, nothing to store.
///  * **Samsung** (Tizen) takes keys over a WebSocket on 8002. The first
///    connection makes the television ask its owner to allow this phone; the
///    reply carries a token, and that token is what saves them being asked
///    again.
///  * **LG** (webOS) is a WebSocket on 3000 with a registration handshake of
///    its own, and the same one-time prompt on the television.
///  * **Android TV** here means adb over the network, which is the honest
///    description: it needs debugging turned on, and it is the only one of
///    the four that is not a remote-control protocol at all.
///
/// Every method answers with a [RemoteResult] rather than throwing. A
/// television that is off, asleep or on another network is the normal case,
/// not an exception, and the screen has to be able to say which.
class TvRemote {
  TvRemote._();

  static final TvRemote instance = TvRemote._();

  static const _timeout = Duration(seconds: 5);

  /// Open WebSocket sessions, one per television, so a burst of presses does
  /// not re-pair each time. Dropped when the television goes away.
  final Map<String, WebSocket> _sockets = {};

  /// Sends [key] to [device]. Returns the device again when the exchange
  /// produced a token worth storing.
  Future<(RemoteResult, Device?)> press(Device device, RemoteKey key) async {
    try {
      switch (device.kind) {
        case DeviceKind.roku:
          return (await _roku(device, key), null);
        case DeviceKind.samsungTv:
          return await _samsung(device, key);
        case DeviceKind.lgTv:
          return await _lg(device, key);
        case DeviceKind.androidTv:
          return (await _androidTv(device, key), null);
        case DeviceKind.mqtt:
          return (
            const RemoteResult.failed('This device has no remote.'),
            null
          );
      }
    } on TimeoutException {
      return (
        RemoteResult.failed('${device.name} did not answer. Is it on?'),
        null
      );
    } catch (error) {
      return (RemoteResult.failed('Could not reach ${device.name}: $error'), null);
    }
  }

  /// Frees whatever is held open for [device].
  Future<void> release(Device device) async {
    await _sockets.remove(device.id)?.close();
    await _pointers.remove(device.id)?.close();
  }

  Future<void> releaseAll() async {
    for (final socket in [..._sockets.values, ..._pointers.values]) {
      await socket.close();
    }
    _sockets.clear();
    _pointers.clear();
  }

  // ------------------------------------------------------------------ Roku

  static const _rokuKeys = {
    RemoteKey.power: 'Power',
    RemoteKey.home: 'Home',
    RemoteKey.back: 'Back',
    RemoteKey.up: 'Up',
    RemoteKey.down: 'Down',
    RemoteKey.left: 'Left',
    RemoteKey.right: 'Right',
    RemoteKey.ok: 'Select',
    RemoteKey.volumeUp: 'VolumeUp',
    RemoteKey.volumeDown: 'VolumeDown',
    RemoteKey.mute: 'VolumeMute',
    RemoteKey.channelUp: 'ChannelUp',
    RemoteKey.channelDown: 'ChannelDown',
    RemoteKey.playPause: 'Play',
    RemoteKey.rewind: 'Rev',
    RemoteKey.forward: 'Fwd',
    RemoteKey.info: 'Info',
    RemoteKey.exit: 'Home',
  };

  Future<RemoteResult> _roku(Device device, RemoteKey key) async {
    final name = _rokuKeys[key];
    if (name == null) return const RemoteResult.failed('No such key.');
    final port = device.port == 0 ? 8060 : device.port;
    final response = await http
        .post(Uri.parse('http://${device.address}:$port/keypress/$name'))
        .timeout(_timeout);
    // Roku answers 200 with an empty body; anything else is a refusal.
    return response.statusCode == 200
        ? const RemoteResult.ok()
        : RemoteResult.failed('The television said ${response.statusCode}.');
  }

  /// The name a Roku gives itself, which is also the cheapest way to tell
  /// that an address really is one.
  Future<String?> rokuName(String address, {int port = 8060}) async {
    try {
      final response = await http
          .get(Uri.parse('http://$address:$port/query/device-info'))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode != 200) return null;
      final match = RegExp(r'<friendly-device-name>([^<]*)<')
          .firstMatch(response.body);
      return match?.group(1) ?? 'Roku';
    } catch (_) {
      return null;
    }
  }

  // --------------------------------------------------------------- Samsung

  static const _samsungKeys = {
    RemoteKey.power: 'KEY_POWER',
    RemoteKey.home: 'KEY_HOME',
    RemoteKey.back: 'KEY_RETURN',
    RemoteKey.up: 'KEY_UP',
    RemoteKey.down: 'KEY_DOWN',
    RemoteKey.left: 'KEY_LEFT',
    RemoteKey.right: 'KEY_RIGHT',
    RemoteKey.ok: 'KEY_ENTER',
    RemoteKey.volumeUp: 'KEY_VOLUP',
    RemoteKey.volumeDown: 'KEY_VOLDOWN',
    RemoteKey.mute: 'KEY_MUTE',
    RemoteKey.channelUp: 'KEY_CHUP',
    RemoteKey.channelDown: 'KEY_CHDOWN',
    RemoteKey.playPause: 'KEY_PLAY',
    RemoteKey.rewind: 'KEY_REWIND',
    RemoteKey.forward: 'KEY_FF',
    RemoteKey.info: 'KEY_INFO',
    RemoteKey.exit: 'KEY_EXIT',
  };

  Future<(RemoteResult, Device?)> _samsung(Device device, RemoteKey key) async {
    final name = _samsungKeys[key];
    if (name == null) return (const RemoteResult.failed('No such key.'), null);

    var socket = _sockets[device.id];
    Device? updated;
    if (socket == null) {
      // The name the television shows in its "allow this device?" prompt.
      final label = base64Encode(utf8.encode('ChatNyto'));
      final port = device.port == 0 ? 8002 : device.port;
      final token = device.token.isEmpty ? '' : '&token=${device.token}';
      final url = 'wss://${device.address}:$port/api/v2/channels/samsung.remote'
          '.control?name=$label$token';
      // Televisions ship a self-signed certificate for their own IP, which
      // no chain will ever validate. The link is on the local network and
      // the alternative is not connecting at all.
      final client = HttpClient()
        ..badCertificateCallback = (_, __, ___) => true;
      socket = await WebSocket.connect(url, customClient: client)
          .timeout(_timeout);
      _sockets[device.id] = socket;
      socket.done.then((_) => _sockets.remove(device.id));

      // The first frame says whether the owner allowed us, and carries the
      // token that saves them being asked again.
      final first = await socket.first.timeout(const Duration(seconds: 30));
      final greeting = jsonDecode(first as String) as Map<String, dynamic>;
      if (greeting['event'] != 'ms.channel.connect') {
        await socket.close();
        _sockets.remove(device.id);
        return (
          RemoteResult.failed(
              'The television refused: ${greeting['event'] ?? 'unknown'}'),
          null
        );
      }
      final fresh = (greeting['data'] as Map?)?['token']?.toString() ?? '';
      if (fresh.isNotEmpty && fresh != device.token) {
        updated = device.copyWith(token: fresh);
      }
      // Reconnecting listens again; without a listener the socket's frames
      // pile up unread.
      socket.listen((_) {}, onError: (_) {}, cancelOnError: false);
    }

    socket.add(jsonEncode({
      'method': 'ms.remote.control',
      'params': {
        'Cmd': 'Click',
        'DataOfCmd': name,
        'Option': 'false',
        'TypeOfRemote': 'SendRemoteKey',
      },
    }));
    return (const RemoteResult.ok(), updated);
  }

  // -------------------------------------------------------------------- LG

  static const _lgKeys = {
    RemoteKey.home: 'HOME',
    RemoteKey.back: 'BACK',
    RemoteKey.up: 'UP',
    RemoteKey.down: 'DOWN',
    RemoteKey.left: 'LEFT',
    RemoteKey.right: 'RIGHT',
    RemoteKey.ok: 'ENTER',
    RemoteKey.info: 'INFO',
    RemoteKey.exit: 'EXIT',
    RemoteKey.channelUp: 'CHANNELUP',
    RemoteKey.channelDown: 'CHANNELDOWN',
  };

  /// The webOS calls that are not button presses but named requests.
  static const _lgUris = {
    RemoteKey.power: 'ssap://system/turnOff',
    RemoteKey.volumeUp: 'ssap://audio/volumeUp',
    RemoteKey.volumeDown: 'ssap://audio/volumeDown',
    RemoteKey.mute: 'ssap://audio/setMute',
    RemoteKey.playPause: 'ssap://media.controls/play',
    RemoteKey.rewind: 'ssap://media.controls/rewind',
    RemoteKey.forward: 'ssap://media.controls/fastForward',
  };

  Future<(RemoteResult, Device?)> _lg(Device device, RemoteKey key) async {
    final port = device.port == 0 ? 3000 : device.port;
    var socket = _sockets[device.id];
    Device? updated;
    if (socket == null) {
      socket = await WebSocket.connect('ws://${device.address}:$port')
          .timeout(_timeout);
      _sockets[device.id] = socket;
      socket.done.then((_) => _sockets.remove(device.id));

      final replies = socket.asBroadcastStream();
      socket.add(jsonEncode({
        'type': 'register',
        'id': 'register_0',
        'payload': {
          'forcePairing': false,
          'pairingType': 'PROMPT',
          if (device.token.isNotEmpty) 'client-key': device.token,
          'manifest': _lgManifest,
        },
      }));
      // A television that has never seen this phone shows a prompt and waits
      // for its owner to pick up the real remote, so the patience here is
      // human-sized rather than network-sized.
      final registered = await replies
          .firstWhere((frame) =>
              (jsonDecode(frame as String) as Map)['type'] == 'registered')
          .timeout(const Duration(seconds: 60));
      final payload = (jsonDecode(registered as String)
          as Map<String, dynamic>)['payload'] as Map?;
      final clientKey = payload?['client-key']?.toString() ?? '';
      if (clientKey.isNotEmpty && clientKey != device.token) {
        updated = device.copyWith(token: clientKey);
      }
      replies.listen((_) {}, onError: (_) {}, cancelOnError: false);
    }

    final uri = _lgUris[key];
    if (uri != null) {
      socket.add(jsonEncode({
        'type': 'request',
        'id': 'req_${DateTime.now().millisecondsSinceEpoch}',
        'uri': uri,
        if (key == RemoteKey.mute) 'payload': {'mute': true},
      }));
      return (const RemoteResult.ok(), updated);
    }

    final button = _lgKeys[key];
    if (button == null) {
      return (const RemoteResult.failed('No such key.'), updated);
    }
    // Direction keys are not requests. webOS carries them on a second
    // socket, whose address the television only gives out when asked — and
    // it speaks a small line protocol rather than JSON.
    final pointer = await _lgPointer(device, socket);
    if (pointer == null) {
      return (
        const RemoteResult.failed('The television would not open its input '
            'channel.'),
        updated
      );
    }
    pointer.add('type:button\nname:$button\n\n');
    return (const RemoteResult.ok(), updated);
  }

  /// The button socket for [device], opened once and kept.
  final Map<String, WebSocket> _pointers = {};

  Future<WebSocket?> _lgPointer(Device device, WebSocket control) async {
    final existing = _pointers[device.id];
    if (existing != null) return existing;
    try {
      final replies = control.asBroadcastStream();
      control.add(jsonEncode({
        'type': 'request',
        'id': 'pointer_${DateTime.now().millisecondsSinceEpoch}',
        'uri': 'ssap://com.webos.service.networkinput/getPointerInputSocket',
      }));
      final reply = await replies
          .firstWhere((frame) =>
              ((jsonDecode(frame as String) as Map)['payload']
                  as Map?)?['socketPath'] !=
              null)
          .timeout(_timeout);
      final path = ((jsonDecode(reply as String) as Map)['payload']
          as Map)['socketPath'] as String;
      final pointer = await WebSocket.connect(path).timeout(_timeout);
      _pointers[device.id] = pointer;
      pointer.done.then((_) => _pointers.remove(device.id));
      pointer.listen((_) {}, onError: (_) {}, cancelOnError: false);
      return pointer;
    } catch (error) {
      debugPrint('[devices] no LG pointer socket: $error');
      return null;
    }
  }

  static const _lgManifest = {
    'manifestVersion': 1,
    'appVersion': '1.1',
    'signed': {
      'created': '20140509',
      'appId': 'com.lge.test',
      'vendorId': 'com.lge',
      'localizedAppNames': {'': 'ChatNyto Remote'},
      'localizedVendorNames': {'': 'ChatNyto'},
      'permissions': ['TEST_SECURE', 'CONTROL_INPUT_TEXT'],
      'serial': '2f930e2d2cfe083771f68e4fe7bb07',
    },
    'permissions': [
      'CONTROL_AUDIO',
      'CONTROL_INPUT_MEDIA_PLAYBACK',
      'CONTROL_POWER',
      'CONTROL_INPUT_TV',
      'READ_TV_CURRENT_CHANNEL',
    ],
  };

  // ----------------------------------------------------------- Android TV

  static const _androidKeys = {
    RemoteKey.power: 26,
    RemoteKey.home: 3,
    RemoteKey.back: 4,
    RemoteKey.up: 19,
    RemoteKey.down: 20,
    RemoteKey.left: 21,
    RemoteKey.right: 22,
    RemoteKey.ok: 23,
    RemoteKey.volumeUp: 24,
    RemoteKey.volumeDown: 25,
    RemoteKey.mute: 164,
    RemoteKey.channelUp: 166,
    RemoteKey.channelDown: 167,
    RemoteKey.playPause: 85,
    RemoteKey.rewind: 89,
    RemoteKey.forward: 90,
    RemoteKey.info: 165,
    RemoteKey.exit: 4,
  };

  /// Live adb connections, one per television, kept between key presses.
  ///
  /// The handshake costs an RSA signature and a round trip; doing it for
  /// every press would make the remote feel broken. A connection that has
  /// died is dropped and rebuilt on the next press.
  final Map<String, AdbClient> _adb = {};

  /// Android TV over adb.
  ///
  /// It used to shell out to the `adb` binary, which meant it worked from
  /// the desktop app and told phone users to go and find a computer — for a
  /// remote control, which is the one thing nobody wants to need a computer
  /// for. The protocol is spoken directly now (see [AdbClient]), so a phone
  /// can drive a television with nothing installed on either.
  ///
  /// It still needs network debugging turned on in the television's
  /// developer options, and the first connection puts a dialog on the
  /// television asking whether to allow it. Both of those are the
  /// television's own decisions and there is no way round them — so the
  /// message says exactly that rather than timing out silently.
  Future<RemoteResult> _androidTv(Device device, RemoteKey key) async {
    final code = _androidKeys[key];
    if (code == null) return const RemoteResult.failed('No such key.');
    final port = device.port == 0 ? 5555 : device.port;
    final id = '${device.address}:$port';

    var client = _adb[id];
    if (client != null && !client.isOpen) {
      _adb.remove(id);
      client = null;
    }
    if (client == null) {
      final (result, fresh) = await AdbClient.connect(device.address, port: port);
      switch (result.status) {
        case AdbStatus.connected:
          _adb[id] = client = fresh!;
        case AdbStatus.awaitingApproval:
          return RemoteResult.failed(result.detail);
        case AdbStatus.unreachable:
          return const RemoteResult.failed(
              'The television did not answer. Network debugging has to be on '
              'in its developer options.');
        case AdbStatus.refused:
          return const RemoteResult.failed(
              'Something is on that address, but it is not an Android TV.');
      }
    }

    try {
      final output = await client.keyEvent(code);
      // adbd reports a rejected command by printing to the same stream, so
      // the only sign of trouble is what came back.
      if (output.contains('not found') || output.contains('Error')) {
        return RemoteResult.failed(output.trim());
      }
      return const RemoteResult.ok();
    } catch (error) {
      await client.close();
      _adb.remove(id);
      return RemoteResult.failed('The television stopped answering: $error');
    }
  }

  /// Looks for televisions on the phone's own subnet.
  ///
  /// Only Roku is worth probing: it answers an unauthenticated HTTP request
  /// with its name. Samsung and LG would each need a pairing prompt on the
  /// television before they said anything, and provoking one on every set in
  /// the building is not a search, it is a nuisance.
  Future<List<({String address, String name})>> findRokus(
      String subnetPrefix) async {
    final found = <({String address, String name})>[];
    final probes = <Future<void>>[];
    for (var host = 1; host < 255; host++) {
      final address = '$subnetPrefix.$host';
      probes.add(() async {
        final name = await rokuName(address);
        if (name != null) found.add((address: address, name: name));
      }());
    }
    await Future.wait(probes);
    debugPrint('[devices] found ${found.length} Roku devices');
    return found;
  }
}
