import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/brokers/broker_service.dart';
import '../core/crypto/crypto_service.dart';
import '../core/notifications/notification_service.dart';
import '../revamp/chat_service.dart';

/// Where a call is in its life.
enum CallState { idle, dialling, ringing, connecting, active, ended }

/// How a finished call is remembered, for the Calls tab.
class CallRecord {
  CallRecord({
    required this.peerFingerprint,
    required this.peerName,
    required this.outgoing,
    required this.answered,
    required this.startedAt,
    this.seconds = 0,
  });

  final String peerFingerprint;
  final String peerName;
  final bool outgoing;
  final bool answered;
  final int startedAt;
  final int seconds;

  bool get missed => !outgoing && !answered;

  Map<String, dynamic> toJson() => {
        'fp': peerFingerprint,
        'name': peerName,
        'out': outgoing,
        'ans': answered,
        'ts': startedAt,
        'secs': seconds,
      };

  static CallRecord fromJson(Map<String, dynamic> json) => CallRecord(
        peerFingerprint: json['fp'] as String? ?? '',
        peerName: json['name'] as String? ?? '',
        outgoing: json['out'] as bool? ?? false,
        answered: json['ans'] as bool? ?? false,
        startedAt: (json['ts'] as num?)?.toInt() ?? 0,
        seconds: (json['secs'] as num?)?.toInt() ?? 0,
      );

  String get durationLabel {
    if (missed) return 'Missed';
    if (!answered) return 'No answer';
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return minutes > 0 ? '${minutes}m ${rest}s' : '${rest}s';
  }
}

/// Voice calls between two ChatNyto users.
///
/// Signalling (ring, answer, decline, hang up, and the WebRTC offer/answer
/// and ICE candidates) travels inside the pair's existing end-to-end
/// encrypted DM channel — there is no call server and no account anywhere.
/// The audio itself is a direct peer-to-peer WebRTC stream, which is what
/// makes calls work on a local network with no internet at all: on the same
/// WiFi or the LoRa box's access point the two devices reach each other
/// directly, so no STUN or TURN server is involved.
///
/// A call needs far more bandwidth than a text message, so it is only
/// offered when the two devices share an IP network. Over a LoRa link, which
/// carries a few kilobits per second, voice is not possible; messages still
/// are.
class CallService extends ChangeNotifier {
  CallService._();

  static final CallService instance = CallService._();

  static const _historyKey = 'calls.history.v1';
  static const _maxHistory = 100;
  static const _ringTimeout = Duration(seconds: 45);

  final List<CallRecord> _history = [];
  bool _loaded = false;

  CallState _state = CallState.idle;
  ChatEntry? _chat;
  String _peerName = '';
  String _peerFingerprint = '';
  bool _outgoing = false;
  bool _muted = false;
  bool _speaker = true;
  DateTime? _connectedAt;
  Timer? _ringTimer;
  Timer? _tick;

  RTCPeerConnection? _peer;
  MediaStream? _localStream;
  String _iceState = '';

  /// Where the media path has got to, for the call screen's status line.
  String get iceState => _iceState;
  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _remoteDescriptionSet = false;

  CallState get state => _state;
  String get peerName => _peerName;
  bool get muted => _muted;
  bool get speakerOn => _speaker;
  bool get inCall => _state != CallState.idle && _state != CallState.ended;
  List<CallRecord> get history => List.unmodifiable(_history.reversed);

  /// Seconds since the call connected, for the in-call timer.
  int get elapsed => _connectedAt == null
      ? 0
      : DateTime.now().difference(_connectedAt!).inSeconds;

  String get elapsedLabel {
    final total = elapsed;
    final minutes = (total ~/ 60).toString().padLeft(2, '0');
    final seconds = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    _history.addAll((prefs.getStringList(_historyKey) ?? []).map(
        (s) => CallRecord.fromJson(jsonDecode(s) as Map<String, dynamic>)));
    ChatService.instance.onCallSignal = _onSignal;
    // Answering from the ringing notification, without opening the app.
    NotificationService.instance.onCallAction =
        (answered) => answered ? answer() : decline();
    notifyListeners();
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final tail = _history.length > _maxHistory
        ? _history.sublist(_history.length - _maxHistory)
        : _history;
    await prefs.setStringList(
        _historyKey, tail.map((r) => jsonEncode(r.toJson())).toList());
  }

  Future<void> clearHistory() async {
    _history.clear();
    await _saveHistory();
    notifyListeners();
  }

  // ------------------------------------------------------------- outgoing

  /// Rings [chat]'s peer. Only direct chats can be called.
  Future<String?> call(ChatEntry chat) async {
    if (!chat.isDm) return 'Only one-to-one chats can be called.';
    if (inCall) return 'A call is already in progress.';
    final peer = chat.peerIdentity;
    if (peer == null) return 'This contact has no verified key yet.';
    // Ringing goes through the broker, so without one there is nothing to
    // ring — better to say so than to sit on "Calling…" until it times out.
    if (!BrokerService.instance.anyConnected) {
      return 'Not connected to a network, so nobody can be rung.';
    }

    _chat = chat;
    _peerName = chat.title;
    _peerFingerprint = peer.fingerprint;
    _outgoing = true;
    _setState(CallState.dialling);

    try {
      await _startMedia();
      final offer = await _peer!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      await _peer!.setLocalDescription(offer);
      await _send({'call': 'offer', 'sdp': offer.sdp});
    } catch (error) {
      await _finish(answered: false, reason: 'Could not start the call: $error');
      return 'Could not start the call: $error';
    }

    _ringTimer = Timer(_ringTimeout, () {
      if (_state == CallState.dialling) {
        hangUp(reason: 'No answer');
      }
    });
    return null;
  }

  // ------------------------------------------------------------- incoming

  Future<void> answer() async {
    await NotificationService.instance.cancelIncomingCall();
    if (_state != CallState.ringing || _peer == null) return;
    _ringTimer?.cancel();
    _setState(CallState.connecting);
    try {
      final answer = await _peer!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      await _peer!.setLocalDescription(answer);
      await _send({'call': 'answer', 'sdp': answer.sdp});
    } catch (error) {
      await _finish(answered: false, reason: 'Could not answer: $error');
    }
  }

  Future<void> decline() async {
    if (!inCall) return;
    await _send({'call': 'decline'});
    await _finish(answered: false, reason: 'Declined');
  }

  Future<void> hangUp({String reason = 'Call ended'}) async {
    if (!inCall) return;
    await _send({'call': 'end'});
    await _finish(answered: _connectedAt != null, reason: reason);
  }

  // -------------------------------------------------------------- in call

  Future<void> toggleMute() async {
    _muted = !_muted;
    for (final track in _localStream?.getAudioTracks() ?? []) {
      track.enabled = !_muted;
    }
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    _speaker = !_speaker;
    try {
      for (final track in _localStream?.getAudioTracks() ?? []) {
        await track.enableSpeakerphone(_speaker);
      }
    } catch (error) {
      debugPrint('Could not switch the speaker: $error');
    }
    notifyListeners();
  }

  // ----------------------------------------------------------- signalling

  /// Handles a signalling message that arrived inside the encrypted DM.
  Future<void> _onSignal(ChatEntry chat, Map<String, dynamic> data) async {
    final kind = data['call'] as String?;
    debugPrint('[call] signal in: $kind from ${chat.title}');
    if (kind == null) return;

    switch (kind) {
      case 'offer':
        if (inCall) {
          // Already busy: tell the caller rather than leaving them ringing.
          await _sendTo(chat, {'call': 'decline'});
          return;
        }
        _chat = chat;
        _peerName = chat.title;
        _peerFingerprint = chat.peerIdentity?.fingerprint ?? '';
        _outgoing = false;
        try {
          await _startMedia();
          await _peer!.setRemoteDescription(
              RTCSessionDescription(data['sdp'] as String?, 'offer'));
          _remoteDescriptionSet = true;
          await _drainCandidates();
        } catch (error) {
          await _finish(answered: false, reason: 'Could not ring: $error');
          return;
        }
        _setState(CallState.ringing);
        // The screen alone is not enough: the app may be in the background,
        // or the phone locked in a pocket.
        await NotificationService.instance.showIncomingCall(_peerName);
        _ringTimer = Timer(_ringTimeout, () {
          if (_state == CallState.ringing) {
            _finish(answered: false, reason: 'Missed');
          }
        });

      case 'answer':
        if (_peer == null) return;
        await _peer!.setRemoteDescription(
            RTCSessionDescription(data['sdp'] as String?, 'answer'));
        _remoteDescriptionSet = true;
        await _drainCandidates();
        _ringTimer?.cancel();
        _setState(CallState.connecting);

      case 'ice':
        final candidate = RTCIceCandidate(
          data['candidate'] as String?,
          data['sdpMid'] as String?,
          (data['sdpMLineIndex'] as num?)?.toInt(),
        );
        if (_peer == null) return;
        if (_remoteDescriptionSet) {
          await _peer!.addCandidate(candidate);
        } else {
          // Candidates can arrive before the description they belong to.
          _pendingCandidates.add(candidate);
        }

      case 'decline':
        await _finish(answered: false, reason: 'Declined');

      case 'end':
        await _finish(answered: _connectedAt != null, reason: 'Call ended');
    }
  }

  Future<void> _drainCandidates() async {
    for (final candidate in _pendingCandidates) {
      await _peer?.addCandidate(candidate);
    }
    _pendingCandidates.clear();
  }

  Future<void> _send(Map<String, dynamic> data) async {
    final chat = _chat;
    if (chat == null) return;
    await _sendTo(chat, data);
  }

  Future<void> _sendTo(ChatEntry chat, Map<String, dynamic> data) {
    debugPrint('[call] signal out: ${data['call']} on ${chat.topic}');
    return ChatService.instance.sendCallSignal(chat, data);
  }

  // ------------------------------------------------------------ webrtc

  Future<void> _startMedia() async {
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
    // No STUN or TURN: on a shared network the two devices find each other
    // directly, which is the case this app is built for (same WiFi, or the
    // LoRa box's access point). Adding a public STUN server here would also
    // be the app's only unsolicited internet connection.
    _peer = await createPeerConnection({
      'iceServers': <Map<String, dynamic>>[],
      'sdpSemantics': 'unified-plan',
    });

    for (final track in _localStream!.getTracks()) {
      await _peer!.addTrack(track, _localStream!);
    }

    // Surfaced on the call screen and in the logs: when a call fails it is
    // almost always the network path, and "Connecting…" forever tells the
    // user nothing.
    _peer!.onIceConnectionState = (state) {
      debugPrint('[call] ice $state');
      _iceState = state.name.replaceFirst('RTCIceConnectionState', '');
      notifyListeners();
    };

    _peer!.onIceCandidate = (candidate) {
      // Loopback addresses can never reach the other device, but ICE still
      // pairs and times out on them, which measurably delays the moment the
      // call goes live. Don't send what cannot work.
      final line = candidate.candidate ?? '';
      if (line.contains(' 127.0.0.1 ') || line.contains(' ::1 ')) return;
      debugPrint('[call] local candidate $line');
      _send({
        'call': 'ice',
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    _peer!.onConnectionState = (state) {
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          if (_connectedAt == null) {
            _connectedAt = DateTime.now();
            _tick?.cancel();
            _tick = Timer.periodic(
                const Duration(seconds: 1), (_) => notifyListeners());
            _setState(CallState.active);
          }
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          if (inCall) {
            _finish(
              answered: _connectedAt != null,
              reason: _connectedAt == null
                  ? 'Could not reach the other device'
                  : 'Call ended',
            );
          }
        default:
          break;
      }
    };
  }

  Future<void> _finish({required bool answered, String? reason}) async {
    await NotificationService.instance.cancelIncomingCall();
    _ringTimer?.cancel();
    _tick?.cancel();
    _ringTimer = null;
    _tick = null;

    if (_peerFingerprint.isNotEmpty || _peerName.isNotEmpty) {
      _history.add(CallRecord(
        peerFingerprint: _peerFingerprint,
        peerName: _peerName,
        outgoing: _outgoing,
        answered: answered,
        startedAt: DateTime.now().millisecondsSinceEpoch,
        seconds: elapsed,
      ));
      await _saveHistory();
    }

    for (final track in _localStream?.getTracks() ?? []) {
      await track.stop();
    }
    await _localStream?.dispose();
    await _peer?.close();
    _localStream = null;
    _peer = null;
    _pendingCandidates.clear();
    _remoteDescriptionSet = false;
    _connectedAt = null;
    _chat = null;
    _muted = false;
    endedReason = reason;
    _setState(CallState.ended);

    // Let the UI show why it ended, then go quiet.
    Timer(const Duration(seconds: 2), () {
      if (_state == CallState.ended) {
        _peerName = '';
        _peerFingerprint = '';
        _setState(CallState.idle);
      }
    });
  }

  /// Why the last call ended, shown briefly on the call screen.
  String? endedReason;

  void _setState(CallState state) {
    _state = state;
    notifyListeners();
  }

  /// Name to show for a fingerprint in the history, preferring the current
  /// display name of a peer we can still see.
  String nameFor(String fingerprint, String fallback) {
    if (!IdentityService.instance.isUnlocked) return fallback;
    return fallback;
  }
}
