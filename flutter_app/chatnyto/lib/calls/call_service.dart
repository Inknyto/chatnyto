import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/brokers/broker_service.dart';
import '../core/crypto/crypto_service.dart';
import '../core/notifications/notification_service.dart';
import '../revamp/chat_service.dart';
import 'ice_directory.dart';
import 'voice_relay.dart';

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
///
/// The audio takes the best road it can find, in this order:
///
///  1. **Direct.** On one network — the same WiFi, the LoRa box's access
///     point — the two devices reach each other and the stream goes
///     straight across, with no server involved at all.
///  2. **Through the network's own call servers.** Away from that, a phone
///     behind mobile data has no address the other side could dial. A STUN
///     server tells it how it looks from outside; a TURN server forwards
///     the audio when even that is not enough. Both come from what the
///     network published about itself, so nothing is built into the app.
///  3. **Over the broker.** When there is still no route, the audio is
///     encrypted and published on the same topic as the messages. It is
///     narrower — 8 kHz, four bits a sample — but it goes wherever a
///     message goes, which is the whole point.
///
/// The fallback is not a guess: it happens when the direct path has had
/// [_directTimeout] and not connected. Before this existed, that case just
/// said "Connecting…" until the caller gave up.
class CallService extends ChangeNotifier {
  CallService._();

  static final CallService instance = CallService._();

  /// History belongs to whoever made the calls, so it follows the account.
  String get _historyKey => 'calls.history.v1${IdentityService.instance.scope}';
  static const _maxHistory = 100;
  static const _ringTimeout = Duration(seconds: 45);

  /// How long a direct connection gets before the audio is relayed through
  /// the broker instead.
  ///
  /// This is a backstop, not the usual way the fallback happens: ICE
  /// reporting `failed` switches over at once, and ICE reporting `connected`
  /// cancels it. It only runs out when neither answer ever comes — a
  /// platform channel that went quiet, or a negotiation that never settled.
  ///
  /// Eight seconds was too tight. Gathering reflexive candidates from a STUN
  /// server adds a round trip that a purely local call never paid, so a
  /// deadline that was comfortable on one WiFi started expiring on exactly
  /// the networks the STUN servers had been added to serve — and expiring
  /// meant tearing down a connection that was still coming up.
  static const _directTimeout = Duration(seconds: 15);

  final List<CallRecord> _history = [];
  bool _loaded = false;

  CallState _state = CallState.idle;
  ChatEntry? _chat;
  String _peerName = '';
  String _peerFingerprint = '';
  String _peerAvatar = '';
  bool _outgoing = false;
  bool _muted = false;
  bool _speaker = true;
  DateTime? _connectedAt;
  Timer? _ringTimer;
  Timer? _tick;

  RTCPeerConnection? _peer;
  MediaStream? _localStream;
  String _iceState = '';
  Timer? _directTimer;
  bool _relaying = false;

  /// The camera's own track, held apart from [_localStream] because it is
  /// started and stopped independently of the call: an audio call can grow a
  /// camera and lose it again without the call itself being renegotiated.
  MediaStreamTrack? _cameraTrack;
  RTCRtpSender? _videoSender;
  bool _cameraOn = false;
  bool _peerCameraOn = false;
  bool _frontCamera = true;

  /// Renderers for the two pictures. Created with the call and disposed with
  /// it, so the screen can be opened and closed as often as the user likes
  /// without either side of the video restarting.
  final RTCVideoRenderer localVideo = RTCVideoRenderer();
  final RTCVideoRenderer remoteVideo = RTCVideoRenderer();
  bool _renderersReady = false;

  /// Whether this device is sending pictures, and whether the other one is.
  bool get cameraOn => _cameraOn;
  bool get peerCameraOn => _peerCameraOn;

  /// True while either side has a camera on — which is what makes the call
  /// screen show video instead of an avatar.
  bool get videoCall => _cameraOn || _peerCameraOn;

  /// Whether turning the camera on is possible at all right now. It is not
  /// once a call has fallen back to the broker: that path carries compressed
  /// voice and nothing else.
  bool get canUseCamera => inCall && !_relaying;

  /// Where the media path has got to, for the call screen's status line.
  String get iceState => _iceState;

  /// True while the audio is going through the broker because no direct
  /// route between the two devices could be found. Surfaced on the call
  /// screen: the sound is narrower and it is fair to say why.
  bool get relaying => _relaying;
  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _remoteDescriptionSet = false;

  bool _bannerSuppressed = false;

  /// True while the call screen itself is what the user is looking at, so
  /// the "you are on a call" banner does not sit on top of the call.
  bool get bannerSuppressed => _bannerSuppressed;

  set bannerSuppressed(bool value) {
    if (_bannerSuppressed == value) return;
    _bannerSuppressed = value;
    notifyListeners();
  }

  CallState get state => _state;
  String get peerName => _peerName;

  /// The other person's picture, base64 JPEG, so the call screen can show
  /// who is ringing however the screen was reached — from the chat, from the
  /// lock screen, or from a notification.
  String get peerAvatar => _peerAvatar;
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

  /// Drops what is held for the account being left. Who you called is as
  /// much that account's business as what you wrote.
  void reset() {
    _history.clear();
    _loaded = false;
    notifyListeners();
  }

  // ------------------------------------------------------------- outgoing

  /// Rings [chat]'s peer. Only direct chats can be called.
  ///
  /// [withVideo] opens the camera before the offer goes out, so the other
  /// phone rings as a video call and shows a picture the moment it is
  /// answered rather than a second or two later.
  Future<String?> call(ChatEntry chat, {bool withVideo = false}) async {
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
    _peerAvatar = peer.avatar;
    _outgoing = true;
    _setState(CallState.dialling);

    try {
      await _startMedia();
      if (withVideo) await setCamera(true, tellPeer: false);
      final offer = await _peer!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      });
      await _peer!.setLocalDescription(offer);
      _localOffer = offer.sdp;
      await _send({'call': 'offer', 'sdp': offer.sdp, 'video': withVideo});
    } catch (error) {
      await _finish(answered: false, reason: 'Could not start the call: $error');
      return 'Could not start the call: $error';
    }

    _ringTimer = Timer(_ringTimeout, () {
      if (_state == CallState.dialling) {
        hangUp(reason: 'No answer');
      }
    });
    // The offer goes out again every couple of seconds for as long as it
    // rings. Two reasons. A lost packet no longer costs the whole call. And
    // when the other phone had ChatNyto closed, what answers first is the
    // service's own isolate, which can ring but not take a call: it puts the
    // app in front, and the app needs the offer still to be arriving when it
    // gets there. Signalling is tiny, so repeating it is cheap.
    _offerTimer?.cancel();
    _offerTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_state != CallState.dialling) return;
      _send({'call': 'offer', 'sdp': _localOffer, 'video': _cameraOn});
    });
    return null;
  }

  /// Kept for as long as the call is being offered, so it can be repeated.
  String? _localOffer;
  Timer? _offerTimer;

  // ------------------------------------------------------------- incoming

  /// Takes the call. [withVideo] turns this device's camera on as it is
  /// answered — offered on the ringing screen when the caller is already
  /// sending pictures, so answering a video call with video is one tap.
  Future<void> answer({bool withVideo = false}) async {
    await NotificationService.instance.cancelIncomingCall();
    if (_state != CallState.ringing || _peer == null) return;
    if (withVideo) await setCamera(true, tellPeer: false);
    _ringTimer?.cancel();
    _setState(CallState.connecting);
    // Armed before the negotiation rather than after it. Everything below
    // crosses a platform channel, and a channel that never answers hangs
    // instead of throwing — which left the call sitting on "Connecting…"
    // with the ring timer already cancelled and no other timer running. A
    // call must never be able to reach this state without something set to
    // rescue it.
    _armDirectTimeout();
    try {
      final answer = await _peer!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      });
      await _peer!.setLocalDescription(answer);
      await _send({'call': 'answer', 'sdp': answer.sdp, 'video': _cameraOn});
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
    VoiceRelay.instance.muted = _muted;
    for (final track in _localStream?.getAudioTracks() ?? []) {
      track.enabled = !_muted;
    }
    notifyListeners();
  }

  /// Turns this device's camera on or off mid-call.
  ///
  /// No renegotiation: the sender was created with the call, so this is a
  /// track being handed to it or taken away. [tellPeer] is false only when
  /// the camera is being started as part of placing or answering a call,
  /// where the offer or answer already carries the news.
  Future<void> setCamera(bool on, {bool tellPeer = true}) async {
    if (on == _cameraOn) return;
    if (on && !canUseCamera) return;
    try {
      if (on) {
        final stream = await navigator.mediaDevices.getUserMedia({
          'audio': false,
          'video': {
            'facingMode': _frontCamera ? 'user' : 'environment',
            // Modest on purpose. This has to survive a phone's uplink and a
            // relay in the middle; a call that keeps going at a smaller size
            // beats one that stutters at a larger one.
            'width': {'ideal': 640},
            'height': {'ideal': 480},
            'frameRate': {'ideal': 20},
          },
        });
        _cameraTrack = stream.getVideoTracks().first;
        await _videoSender?.replaceTrack(_cameraTrack);
        localVideo.srcObject = stream;
      } else {
        await _videoSender?.replaceTrack(null);
        // Stopped, not just detached: a camera that is merely unused still
        // shows the light that tells the user they are being filmed.
        await _cameraTrack?.stop();
        _cameraTrack = null;
        localVideo.srcObject = null;
      }
      _cameraOn = on;
      if (tellPeer) await _send({'call': 'video', 'on': on});
      notifyListeners();
    } catch (error) {
      debugPrint('[call] could not switch the camera: $error');
    }
  }

  Future<void> toggleCamera() => setCamera(!_cameraOn);

  /// Front to back and back again, without interrupting the call.
  Future<void> switchCamera() async {
    final track = _cameraTrack;
    if (track == null) return;
    try {
      await Helper.switchCamera(track);
      _frontCamera = !_frontCamera;
      notifyListeners();
    } catch (error) {
      debugPrint('[call] could not switch camera: $error');
    }
  }

  /// Whether the local preview should be mirrored — a front camera shown
  /// unmirrored is the thing everybody notices and nobody can name.
  bool get frontCamera => _frontCamera;

  void _setPeerCamera(bool on) {
    if (_peerCameraOn == on) return;
    _peerCameraOn = on;
    notifyListeners();
  }

  Future<void> _initRenderers() async {
    if (_renderersReady) return;
    await localVideo.initialize();
    await remoteVideo.initialize();
    _renderersReady = true;
  }

  Future<void> toggleSpeaker() async {
    _speaker = !_speaker;
    try {
      for (final track in _localStream?.getAudioTracks() ?? []) {
        await track.enableSpeakerphone(_speaker);
      }
      if (_relaying) await Helper.setSpeakerphoneOn(_speaker);
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
        // The caller repeats its offer while it rings. A repeat of the call
        // we are already ringing for is not a second call, and answering it
        // with "busy" would hang up on the very person calling us. It may
        // still carry news — the caller turning its camera on while we are
        // deciding whether to pick up.
        if (inCall && _chat?.id == chat.id) {
          _setPeerCamera(data['video'] == true);
          return;
        }
        if (inCall) {
          // Genuinely busy with somebody else: tell them rather than
          // leaving them ringing.
          await _sendTo(chat, {'call': 'decline'});
          return;
        }
        _chat = chat;
        _peerName = chat.title;
        _peerFingerprint = chat.peerIdentity?.fingerprint ?? '';
        _peerAvatar = chat.peerIdentity?.avatar ?? '';
        _outgoing = false;
        _setPeerCamera(data['video'] == true);
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
        _setPeerCamera(data['video'] == true);
        _ringTimer?.cancel();
        _offerTimer?.cancel();
        _offerTimer = null;
        _setState(CallState.connecting);
        // Same reasoning as in [answer]: the state and its rescue timer are
        // set first, so a description that never settles cannot strand the
        // call. It also used to be possible for setRemoteDescription to
        // throw straight out of here — nothing caught it — and leave the
        // caller on "Calling…" until the ring timed out.
        _armDirectTimeout();
        try {
          await _peer!.setRemoteDescription(
              RTCSessionDescription(data['sdp'] as String?, 'answer'));
          _remoteDescriptionSet = true;
          await _drainCandidates();
        } catch (error) {
          debugPrint('[call] could not take the answer: $error');
        }

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

      // A camera going on or off does not change the negotiated media — the
      // video transceiver is there from the start — so it needs no new
      // offer, only a word to say the picture is about to arrive or stop.
      case 'video':
        _setPeerCamera(data['on'] == true);

      case 'relay':
        // The other side could not find a direct route. Follow it over,
        // without telling it back — that would bounce forever.
        if (inCall) await _startRelay(tellPeer: false);

      case 'voice':
        final frame = data['f'] as String?;
        if (frame == null) return;
        // Hearing audio is itself proof the relay is working, which matters
        // for the side whose own switch-over is still in flight.
        if (!_relaying && inCall) await _startRelay(tellPeer: false);
        VoiceRelay.instance.playFrame(base64Decode(frame));

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
    await _initRenderers();
    // Audio only, even for a video call: the camera is opened separately, a
    // moment later. Asking for both at once means the camera light comes on
    // while the phone is still ringing, and for a call that is never
    // answered it never should have.
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
    // On one network the two devices find each other directly and this list
    // is empty, which is the case the app is built for. Away from it — two
    // phones on mobile data, each behind the carrier's NAT — neither knows
    // an address the other could dial, and without a STUN server to ask,
    // the call can never connect. See [IceDirectory] for where these come
    // from and why an offline app still gets none.
    final iceServers = await IceDirectory.instance.servers();
    debugPrint('[call] ice servers: ${iceServers.length}');
    _peer = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });

    for (final track in _localStream!.getTracks()) {
      await _peer!.addTrack(track, _localStream!);
    }

    // The video path is negotiated on every call, whether or not a camera is
    // ever switched on. It costs nothing when unused — an SDP section with
    // no track sends no packets — and it buys the thing that matters: the
    // camera can be turned on mid-call by handing a track to a sender that
    // already exists, with no second offer and no renegotiation for the
    // other side to get wrong.
    final transceiver = await _peer!.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv),
    );
    _videoSender = transceiver.sender;

    _peer!.onTrack = (event) {
      if (event.streams.isEmpty) return;
      remoteVideo.srcObject = event.streams.first;
      notifyListeners();
    };

    // Surfaced on the call screen and in the logs: when a call fails it is
    // almost always the network path, and "Connecting…" forever tells the
    // user nothing.
    _peer!.onIceConnectionState = (state) {
      debugPrint('[call] ice $state');
      _iceState = state.name.replaceFirst('RTCIceConnectionState', '');
      notifyListeners();
      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          // ICE is the layer that actually carries the audio, so this is the
          // honest "the call is up". Waiting only on onConnectionState cost
          // real calls: where that callback is late or never arrives, the
          // fallback timer fired and tore down a path whose media was
          // already flowing.
          _directTimer?.cancel();
          _goLive();
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          // ICE has exhausted every candidate pair. There is nothing to be
          // gained by sitting out the rest of the timeout.
          if (_connectedAt == null && !_relaying && inCall) {
            _startRelay(tellPeer: true);
          }
        default:
          break;
      }
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
          _directTimer?.cancel();
          _goLive();
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          // A direct path that fails before the call is up is not the end of
          // the call any more: there is still the broker, which both devices
          // are demonstrably able to reach.
          if (_connectedAt == null && !_relaying && inCall) {
            _startRelay(tellPeer: true);
          } else if (inCall && !_relaying) {
            _finish(answered: _connectedAt != null, reason: 'Call ended');
          }
        default:
          break;
      }
    };
  }

  /// Marks the call connected and starts the timer, whichever path the
  /// audio ended up taking.
  void _goLive() {
    if (_connectedAt != null) return;
    _connectedAt = DateTime.now();
    _tick?.cancel();
    _tick =
        Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    _setState(CallState.active);
  }

  // ------------------------------------------------------------ the relay

  /// Gives the direct path a fixed amount of time, then falls back.
  void _armDirectTimeout() {
    _directTimer?.cancel();
    _directTimer = Timer(_directTimeout, () {
      if (inCall && _connectedAt == null && !_relaying) {
        debugPrint('[call] no direct route in ${_directTimeout.inSeconds}s');
        _startRelay(tellPeer: true);
      }
    });
  }

  /// Moves the call onto the broker. [tellPeer] is set by whichever side
  /// noticed first; the other switches when it hears about it, so both ends
  /// are never half in one mode and half in the other.
  Future<void> _startRelay({required bool tellPeer}) async {
    if (_relaying || !inCall) return;
    // Asked before anything is torn down. Past the teardown below there is
    // no way back to WebRTC, so discovering only afterwards that this device
    // could never have relayed meant destroying a working attempt and
    // replacing it with nothing.
    if (!await VoiceRelay.instance.canStart()) {
      if (!inCall || _relaying) return;
      await _finish(
        answered: _connectedAt != null,
        reason: 'No direct route, and this device cannot relay a call',
      );
      return;
    }
    // Awaiting above gave the other side a chance to get here first.
    if (_relaying || !inCall) return;
    _relaying = true;
    _directTimer?.cancel();
    if (tellPeer) await _send({'call': 'relay'});

    // The relay carries compressed voice and nothing else, so any video has
    // to stop here rather than appear to keep running with a frozen picture.
    if (_cameraOn || _peerCameraOn) await _stopVideo(tellPeer: _cameraOn);

    // The microphone cannot be held twice. WebRTC's attempt is over.
    for (final track in _localStream?.getTracks() ?? []) {
      await track.stop();
    }
    await _localStream?.dispose();
    _localStream = null;
    await _peer?.close();
    _peer = null;
    // Android does not hand the microphone straight back. Opening a fresh
    // AudioRecord in the same breath as WebRTC released the old one fails
    // often enough to lose calls over, and the failure looks like a device
    // that cannot relay at all rather than one that was asked too early.
    await Future<void>.delayed(const Duration(milliseconds: 250));

    VoiceRelay.instance.onFrame = _sendVoice;
    VoiceRelay.instance.muted = _muted;
    // Bounded. Both the player setup and the capture start cross a platform
    // channel, and a channel that never answers would hang the call here —
    // the precise failure this fallback exists to prevent.
    final started = await VoiceRelay.instance
        .start()
        .timeout(const Duration(seconds: 6), onTimeout: () => false);
    if (!started) {
      _relaying = false;
      VoiceRelay.instance.onFrame = null;
      await VoiceRelay.instance.stop();
      await _finish(
        answered: _connectedAt != null,
        reason: 'Could not reach the other device',
      );
      return;
    }
    // WebRTC routed the audio while it held the call; nothing does now, so
    // the earpiece/speaker choice has to be applied again by hand.
    try {
      await Helper.setSpeakerphoneOn(_speaker);
    } catch (error) {
      debugPrint('[call] could not set the audio route: $error');
    }
    _goLive();
    notifyListeners();
  }

  /// Stops the camera and clears both pictures. Used when a call ends and
  /// when it falls back to a path that cannot carry video.
  Future<void> _stopVideo({required bool tellPeer}) async {
    if (tellPeer && _cameraOn) await _send({'call': 'video', 'on': false});
    _cameraOn = false;
    _peerCameraOn = false;
    try {
      await _cameraTrack?.stop();
    } catch (_) {
      // The track may already have gone with the peer connection.
    }
    _cameraTrack = null;
    localVideo.srcObject = null;
    remoteVideo.srcObject = null;
    notifyListeners();
  }

  void _sendVoice(Uint8List frame) {
    final chat = _chat;
    if (chat == null || !_relaying) return;
    ChatService.instance.sendVoiceFrame(chat, frame);
  }

  Future<void> _finish({required bool answered, String? reason}) async {
    await NotificationService.instance.cancelIncomingCall();
    _ringTimer?.cancel();
    _tick?.cancel();
    _directTimer?.cancel();
    _offerTimer?.cancel();
    _ringTimer = null;
    _tick = null;
    _directTimer = null;
    _offerTimer = null;
    _localOffer = null;
    if (_relaying) {
      _relaying = false;
      VoiceRelay.instance.onFrame = null;
      await VoiceRelay.instance.stop();
    }

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

    await _stopVideo(tellPeer: false);
    _videoSender = null;

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
        _peerAvatar = '';
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
