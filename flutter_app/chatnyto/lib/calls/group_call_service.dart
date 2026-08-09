import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../core/brokers/broker_service.dart';
import '../core/crypto/crypto_service.dart';
import '../revamp/chat_service.dart';
import 'ice_directory.dart';

/// One other person in a group call: the connection to them, what they are
/// sending, and how loudly.
class CallParticipant {
  CallParticipant({required this.fingerprint, required this.name});

  final String fingerprint;
  String name;

  RTCPeerConnection? peer;
  RTCRtpSender? videoSender;
  final RTCVideoRenderer video = RTCVideoRenderer();
  bool rendererReady = false;

  /// True once their camera is on and a picture is arriving.
  bool cameraOn = false;

  /// Whether the media path to this person has come up.
  bool connected = false;

  /// Their microphone level as this device hears it, 0..1.
  double level = 0;

  /// Candidates that arrived before the description they belong to.
  final List<RTCIceCandidate> pending = [];
  bool remoteDescriptionSet = false;

  /// Set on whichever side has to make the offer, so a connection is never
  /// negotiated from both ends at once.
  bool polite = false;

  Future<void> dispose() async {
    try {
      await peer?.close();
    } catch (_) {
      // Already gone.
    }
    peer = null;
    videoSender = null;
    if (rendererReady) {
      video.srcObject = null;
      await video.dispose();
      rendererReady = false;
    }
  }
}

/// Calls with more than two people in them.
///
/// There is no server here either, so the topology is a mesh: every
/// participant holds a peer connection to every other one, and each device
/// sends its own audio and video to each of the others. That is what makes
/// [maxParticipants] necessary — the uplink cost grows with the number of
/// people, and a phone encoding five separate video streams over a mobile
/// connection is already at the edge of what it can do. A group larger than
/// that needs a server to fan the streams out, and this app does not have
/// one to offer.
///
/// The signalling rides on the group's existing encrypted topic. Everybody
/// in the group receives every signal, so each one names who it is from and
/// who it is for, and a device ignores what is not addressed to it. The
/// channel key is the group's, which is the same guarantee the messages
/// have: the broker forwards it and cannot read it.
///
/// A group call is a room rather than a ring. You are in it or you are not;
/// people arrive and leave while it runs; and it ends when the last person
/// leaves rather than when somebody hangs up on somebody.
class GroupCallService extends ChangeNotifier {
  GroupCallService._();

  static final GroupCallService instance = GroupCallService._();

  /// Including yourself. See the note on the class for why this is not a
  /// number that can simply be raised.
  static const maxParticipants = 6;

  /// How often each connection is asked how loud the person on it is.
  ///
  /// Fast enough to follow a conversation, slow enough that polling every
  /// connection is not itself a cost. Below about 300ms the highlight starts
  /// to chase syllables rather than speakers.
  static const _levelPoll = Duration(milliseconds: 400);

  /// How long somebody keeps the highlight after they stop making noise.
  ///
  /// Without it the ring flickers off in the gaps between words, which reads
  /// as a fault rather than as a pause.
  static const _speakerHold = Duration(milliseconds: 1200);

  /// The level at which somebody counts as talking rather than as a room
  /// with a person in it.
  static const _speakingThreshold = 0.02;

  ChatEntry? _chat;
  String _myFingerprint = '';
  String _myName = '';
  final Map<String, CallParticipant> _participants = {};

  MediaStream? _localStream;
  MediaStreamTrack? _cameraTrack;
  final RTCVideoRenderer localVideo = RTCVideoRenderer();
  bool _localRendererReady = false;

  bool _inCall = false;
  bool _muted = false;
  bool _cameraOn = false;
  bool _frontCamera = true;
  bool _speaker = true;
  double _myLevel = 0;
  String? _loudest;
  DateTime? _loudestAt;
  DateTime? _startedAt;

  Timer? _levelTimer;
  Timer? _tick;

  /// A group call somebody else started that we have not joined. Cleared
  /// when we join it, when it ends, or when it goes quiet.
  String? _ringingChatId;
  String _ringingChatTitle = '';
  Timer? _ringingTimeout;

  bool get inCall => _inCall;
  ChatEntry? get chat => _chat;
  String get myFingerprint => _myFingerprint;
  bool get muted => _muted;
  bool get cameraOn => _cameraOn;
  bool get frontCamera => _frontCamera;
  bool get speakerOn => _speaker;
  double get myLevel => _myLevel;

  /// Everyone else in the room, in a stable order so tiles do not jump about
  /// as levels change.
  List<CallParticipant> get participants {
    final list = _participants.values.toList()
      ..sort((a, b) => a.fingerprint.compareTo(b.fingerprint));
    return list;
  }

  /// How many people are in the call, counting yourself.
  int get headcount => _participants.length + (_inCall ? 1 : 0);

  /// Whose tile is highlighted: the loudest person, held briefly so it does
  /// not blink between words. Empty when nobody is saying anything.
  String get speaking {
    final at = _loudestAt;
    if (at == null || DateTime.now().difference(at) > _speakerHold) return '';
    return _loudest ?? '';
  }

  bool isSpeaking(String fingerprint) =>
      fingerprint.isNotEmpty && speaking == fingerprint;

  /// Set while a group call is running that this device has not joined.
  String? get ringingChatId => _ringingChatId;
  String get ringingChatTitle => _ringingChatTitle;

  int get elapsed => _startedAt == null
      ? 0
      : DateTime.now().difference(_startedAt!).inSeconds;

  String get elapsedLabel {
    final total = elapsed;
    final minutes = (total ~/ 60).toString().padLeft(2, '0');
    final seconds = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void init() {
    ChatService.instance.onGroupCallSignal = _onSignal;
  }

  // ------------------------------------------------------------- joining

  /// Joins the call in [chat], starting it if nobody else has.
  ///
  /// There is no difference between the two from here, which is the point of
  /// modelling it as a room: the first person in announces themselves to an
  /// empty room and waits, and everybody after that announces themselves to
  /// whoever answers.
  Future<String?> join(ChatEntry chat, {bool withVideo = false}) async {
    if (chat.isDm) return 'This is a one-to-one chat.';
    if (_inCall) return 'You are already in a call.';
    if (!BrokerService.instance.anyConnected) {
      return 'Not connected to a network, so there is nobody to call.';
    }
    if (!IdentityService.instance.isUnlocked) {
      return 'Unlock your account to make a call.';
    }
    final me = await IdentityService.instance.publicIdentity();
    _myFingerprint = me.fingerprint;
    _myName = me.name;
    _chat = chat;
    _clearRinging();

    try {
      await _startLocalMedia();
    } catch (error) {
      await _teardown();
      return 'Could not open the microphone: $error';
    }

    _inCall = true;
    _startedAt = DateTime.now();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    _levelTimer = Timer.periodic(_levelPoll, (_) => _readLevels());
    if (withVideo) await setCamera(true, tellPeers: false);

    // Two things at once: it tells the room somebody has arrived, and it is
    // what an empty room hears when the call begins.
    await _send({'call': 'join', 'video': _cameraOn});
    notifyListeners();
    return null;
  }

  /// Leaves. The call itself goes on for whoever is still in it.
  Future<void> leave() async {
    if (!_inCall) return;
    await _send({'call': 'leave'});
    await _teardown();
  }

  Future<void> _teardown() async {
    _inCall = false;
    _levelTimer?.cancel();
    _tick?.cancel();
    _levelTimer = null;
    _tick = null;
    _startedAt = null;
    _loudest = null;
    _loudestAt = null;
    _myLevel = 0;

    for (final participant in _participants.values) {
      await participant.dispose();
    }
    _participants.clear();

    _cameraOn = false;
    try {
      await _cameraTrack?.stop();
    } catch (_) {
      // It may already have gone with the connection.
    }
    _cameraTrack = null;
    if (_localRendererReady) localVideo.srcObject = null;
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await track.stop();
    }
    await _localStream?.dispose();
    _localStream = null;
    _chat = null;
    _muted = false;
    notifyListeners();
  }

  // --------------------------------------------------------------- media

  Future<void> _startLocalMedia() async {
    if (!_localRendererReady) {
      await localVideo.initialize();
      _localRendererReady = true;
    }
    // Audio only to begin with, as in a one-to-one call: the camera light
    // should not come on before there is a call to use it for.
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
  }

  Future<void> toggleMute() async {
    _muted = !_muted;
    for (final track in _localStream?.getAudioTracks() ?? []) {
      track.enabled = !_muted;
    }
    if (_muted) _myLevel = 0;
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    _speaker = !_speaker;
    try {
      await Helper.setSpeakerphoneOn(_speaker);
    } catch (error) {
      debugPrint('[group call] could not switch the speaker: $error');
    }
    notifyListeners();
  }

  Future<void> toggleCamera() => setCamera(!_cameraOn);

  /// Turns this device's camera on or off for everybody at once.
  ///
  /// The track is handed to each participant's sender, all of which were
  /// created when their connection was, so nothing is renegotiated — the
  /// same trick as in a one-to-one call, done n times.
  Future<void> setCamera(bool on, {bool tellPeers = true}) async {
    if (!_inCall || on == _cameraOn) return;
    try {
      if (on) {
        final stream = await navigator.mediaDevices.getUserMedia({
          'audio': false,
          'video': {
            'facingMode': _frontCamera ? 'user' : 'environment',
            // Smaller than a one-to-one call asks for, deliberately. This
            // picture is encoded and sent once per person in the room.
            'width': {'ideal': 480},
            'height': {'ideal': 360},
            'frameRate': {'ideal': 15},
          },
        });
        _cameraTrack = stream.getVideoTracks().first;
        localVideo.srcObject = stream;
        for (final participant in _participants.values) {
          await participant.videoSender?.replaceTrack(_cameraTrack);
        }
      } else {
        for (final participant in _participants.values) {
          await participant.videoSender?.replaceTrack(null);
        }
        // Stopped rather than merely detached: a camera nobody is watching
        // still shows the light that says somebody might be.
        await _cameraTrack?.stop();
        _cameraTrack = null;
        localVideo.srcObject = null;
      }
      _cameraOn = on;
      if (tellPeers) await _send({'call': 'video', 'on': on});
      notifyListeners();
    } catch (error) {
      debugPrint('[group call] could not switch the camera: $error');
    }
  }

  Future<void> switchCamera() async {
    final track = _cameraTrack;
    if (track == null) return;
    try {
      await Helper.switchCamera(track);
      _frontCamera = !_frontCamera;
      notifyListeners();
    } catch (error) {
      debugPrint('[group call] could not switch camera: $error');
    }
  }

  // --------------------------------------------------------- signalling

  Future<void> _send(Map<String, dynamic> data, {String? to}) async {
    final chat = _chat;
    if (chat == null) return;
    await ChatService.instance.sendCallSignal(chat, {
      ...data,
      if (to != null) 'to': to,
    });
  }

  Future<void> _onSignal(ChatEntry chat, Map<String, dynamic> data) async {
    final kind = data['call'] as String?;
    final from = data['from'] as String? ?? '';
    if (kind == null || from.isEmpty) return;

    // Everybody in the group hears everything on this topic. A signal
    // addressed to somebody else is somebody else's business.
    final to = data['to'] as String?;
    if (to != null && to != _myFingerprint) return;

    if (!_inCall) {
      // Not in the call, but somebody is: put up the invitation.
      if (kind == 'join' || kind == 'here') {
        _ringingChatId = chat.id;
        _ringingChatTitle = chat.title;
        _ringingTimeout?.cancel();
        // The invitation is not cancelled by anybody in particular; it goes
        // stale on its own if the room falls silent, which also covers the
        // case where everybody left while this phone was asleep.
        _ringingTimeout = Timer(const Duration(seconds: 60), _clearRinging);
        notifyListeners();
      } else if (kind == 'leave') {
        // Not enough to know the room emptied — somebody else may still be
        // in it — but it is a reason to let the invitation expire quietly.
      }
      return;
    }
    if (_chat?.id != chat.id) return;

    switch (kind) {
      case 'join':
        // Somebody arrived. Answer so they know we are here, then decide
        // which of us makes the offer.
        await _send({'call': 'here', 'video': _cameraOn}, to: from);
        await _meet(from, theirCameraOn: data['video'] == true);

      case 'here':
        await _meet(from, theirCameraOn: data['video'] == true);

      case 'offer':
        await _takeOffer(from, data['sdp'] as String?);

      case 'answer':
        final participant = _participants[from];
        if (participant?.peer == null) return;
        try {
          await participant!.peer!.setRemoteDescription(
              RTCSessionDescription(data['sdp'] as String?, 'answer'));
          participant.remoteDescriptionSet = true;
          await _drain(participant);
        } catch (error) {
          debugPrint('[group call] could not take an answer: $error');
        }

      case 'ice':
        final participant = _participants[from];
        if (participant?.peer == null) return;
        final candidate = RTCIceCandidate(
          data['candidate'] as String?,
          data['sdpMid'] as String?,
          (data['sdpMLineIndex'] as num?)?.toInt(),
        );
        if (participant!.remoteDescriptionSet) {
          await participant.peer!.addCandidate(candidate);
        } else {
          participant.pending.add(candidate);
        }

      case 'video':
        final participant = _participants[from];
        if (participant == null) return;
        participant.cameraOn = data['on'] == true;
        notifyListeners();

      case 'leave':
        final participant = _participants.remove(from);
        await participant?.dispose();
        notifyListeners();
    }
  }

  void _clearRinging() {
    _ringingTimeout?.cancel();
    _ringingTimeout = null;
    if (_ringingChatId == null) return;
    _ringingChatId = null;
    _ringingChatTitle = '';
    notifyListeners();
  }

  /// Which of two people makes the offer.
  ///
  /// Decided by comparing fingerprints rather than by who arrived first.
  /// Both sides learn of each other in the same instant — the arriver from
  /// the "here", the resident from the "join" — so "whoever noticed first"
  /// is not a rule either of them could apply, and both offering at once is
  /// the classic way to end up with two half-built connections and no call.
  /// Comparing two strings is something both can do and both get the same
  /// answer to.
  static bool offersTo(String me, String them) => me.compareTo(them) < 0;

  /// Sets up the connection to one other person.
  Future<void> _meet(String fingerprint, {required bool theirCameraOn}) async {
    if (fingerprint == _myFingerprint) return;
    if (_participants.containsKey(fingerprint)) return;
    if (headcount >= maxParticipants) {
      debugPrint('[group call] room full; ignoring $fingerprint');
      return;
    }

    final participant = CallParticipant(
      fingerprint: fingerprint,
      name: _nameFor(fingerprint),
    )..cameraOn = theirCameraOn;
    _participants[fingerprint] = participant;
    notifyListeners();

    final offering = offersTo(_myFingerprint, fingerprint);
    participant.polite = !offering;
    await _connect(participant, offering: offering);

    if (offering) {
      try {
        final offer = await participant.peer!.createOffer({});
        await participant.peer!.setLocalDescription(offer);
        await _send({'call': 'offer', 'sdp': offer.sdp}, to: fingerprint);
      } catch (error) {
        debugPrint('[group call] could not offer to $fingerprint: $error');
      }
    }
  }

  Future<void> _connect(CallParticipant participant,
      {required bool offering}) async {
    if (!participant.rendererReady) {
      await participant.video.initialize();
      participant.rendererReady = true;
    }
    final iceServers = await IceDirectory.instance.servers();
    final peer = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });
    participant.peer = peer;

    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await peer.addTrack(track, _localStream!);
    }

    // Same asymmetry as a one-to-one call, and for the same reason: a
    // transceiver made here cannot be matched to an incoming offer's m=
    // line, so only the offering side creates one and the answering side
    // adopts what the offer brings.
    if (offering) {
      final transceiver = await peer.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(
          direction: TransceiverDirection.SendRecv,
          streams: [_localStream!],
        ),
      );
      participant.videoSender = transceiver.sender;
      if (_cameraOn && _cameraTrack != null) {
        await participant.videoSender!.replaceTrack(_cameraTrack);
      }
    }

    peer.onTrack = (event) async {
      if (event.track.kind != 'video') return;
      try {
        final stream = event.streams.isNotEmpty
            ? event.streams.first
            : await createLocalMediaStream('remote-${event.track.id}');
        if (event.streams.isEmpty) await stream.addTrack(event.track);
        await participant.video
            .setSrcObject(stream: stream, trackId: event.track.id);
        notifyListeners();
      } catch (error) {
        debugPrint('[group call] could not show a camera: $error');
      }
    };

    peer.onIceCandidate = (candidate) {
      final line = candidate.candidate ?? '';
      if (line.contains(' 127.0.0.1 ') || line.contains(' ::1 ')) return;
      _send({
        'call': 'ice',
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      }, to: participant.fingerprint);
    };

    peer.onIceConnectionState = (state) {
      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          participant.connected = true;
          notifyListeners();
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
        case RTCIceConnectionState.RTCIceConnectionStateClosed:
          // One connection failing is not the call failing. The person drops
          // out of the room and everybody else carries on — which is the one
          // real advantage a mesh has over a server in the middle.
          participant.connected = false;
          _participants.remove(participant.fingerprint);
          participant.dispose();
          notifyListeners();
        default:
          break;
      }
    };
  }

  Future<void> _takeOffer(String fingerprint, String? sdp) async {
    var participant = _participants[fingerprint];
    if (participant == null) {
      // An offer from somebody we have not met yet: they heard our join
      // before we heard their here.
      await _meet(fingerprint, theirCameraOn: false);
      participant = _participants[fingerprint];
    }
    final peer = participant?.peer;
    if (participant == null || peer == null) return;
    try {
      await peer.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
      participant.remoteDescriptionSet = true;
      await _adoptVideo(participant);
      await _drain(participant);
      final answer = await peer.createAnswer({});
      await peer.setLocalDescription(answer);
      await _send({'call': 'answer', 'sdp': answer.sdp}, to: fingerprint);
    } catch (error) {
      debugPrint('[group call] could not answer $fingerprint: $error');
    }
  }

  /// Turns the recvonly video transceiver the offer created into a two-way
  /// one and keeps its sender, so this side can switch its camera on later
  /// without renegotiating. See [_connect] for why it has to be done this
  /// way round.
  Future<void> _adoptVideo(CallParticipant participant) async {
    final peer = participant.peer;
    if (peer == null || participant.videoSender != null) return;
    try {
      for (final transceiver in await peer.getTransceivers()) {
        if (transceiver.receiver.track?.kind != 'video') continue;
        await transceiver.setDirection(TransceiverDirection.SendRecv);
        participant.videoSender = transceiver.sender;
        final stream = _localStream;
        if (stream != null) {
          await participant.videoSender!.setStreams([stream]);
        }
        if (_cameraOn && _cameraTrack != null) {
          await participant.videoSender!.replaceTrack(_cameraTrack);
        }
        return;
      }
    } catch (error) {
      debugPrint('[group call] could not take over a video track: $error');
    }
  }

  Future<void> _drain(CallParticipant participant) async {
    for (final candidate in participant.pending) {
      await participant.peer?.addCandidate(candidate);
    }
    participant.pending.clear();
  }

  String _nameFor(String fingerprint) {
    final peer = BrokerService.instance.peers
        .where((p) => p.fingerprint == fingerprint)
        .firstOrNull;
    if (peer != null) return peer.name;
    // Better a short piece of the fingerprint than an empty tile: it is at
    // least something the person could be identified by.
    return fingerprint.length > 8 ? fingerprint.substring(0, 8) : fingerprint;
  }

  /// The picture the tiles need: who is talking, and how much.
  String get myName => _myName;

  // ------------------------------------------------------ who is talking

  /// Asks each connection how loud the person on it is.
  ///
  /// WebRTC measures this at the point the audio is received, which is the
  /// only place it can be measured honestly: it is the sound this device is
  /// actually playing, after everything the network did to it. Nobody has to
  /// be trusted to report their own volume.
  Future<void> _readLevels() async {
    if (!_inCall) return;
    var loudest = '';
    var loudestLevel = _speakingThreshold;

    for (final participant in _participants.values) {
      final peer = participant.peer;
      if (peer == null) continue;
      try {
        final level = audioLevelOf(await peer.getStats(), inbound: true);
        participant.level = level;
        if (level > loudestLevel) {
          loudestLevel = level;
          loudest = participant.fingerprint;
        }
      } catch (_) {
        // A connection that is going away; not worth a line in the log
        // four times a second.
      }
    }

    // Our own level comes from the same place, so it is on the same scale as
    // everybody else's and the comparison means something.
    if (!_muted) {
      final peer = _participants.values.firstOrNull?.peer;
      if (peer != null) {
        try {
          _myLevel = audioLevelOf(await peer.getStats(), inbound: false);
          if (_myLevel > loudestLevel) {
            loudestLevel = _myLevel;
            loudest = _myFingerprint;
          }
        } catch (_) {
          // Same.
        }
      }
    }

    if (loudest.isNotEmpty) {
      _loudest = loudest;
      _loudestAt = DateTime.now();
    }
    notifyListeners();
  }

  /// Digs the audio level out of a stats report.
  ///
  /// Which entry carries it depends on the platform and the libwebrtc
  /// version — inbound-rtp on newer ones, a separate track entry on older —
  /// so all the plausible places are tried rather than one being assumed.
  @visibleForTesting
  static double audioLevelOf(List<StatsReport> reports,
      {required bool inbound}) {
    final wanted = inbound
        ? const ['inbound-rtp', 'track', 'remote-inbound-rtp']
        : const ['media-source', 'track'];
    var best = 0.0;
    for (final report in reports) {
      if (!wanted.contains(report.type)) continue;
      final values = report.values;
      final kind = values['kind'] ?? values['mediaType'];
      if (kind != null && kind != 'audio') continue;
      // An outbound track entry and an inbound one look alike apart from
      // this, and taking the wrong one would light up the speaker's own tile
      // whenever anybody else spoke.
      if (values.containsKey('remoteSource')) {
        if (values['remoteSource'] != inbound) continue;
      }
      final level = values['audioLevel'];
      if (level is num && level > best) best = level.toDouble();
    }
    return best.clamp(0.0, 1.0);
  }

  /// Drops the ringing state when the account changes. A call belongs to
  /// whoever was signed in when it started.
  void reset() {
    _clearRinging();
    if (_inCall) _teardown();
  }
}
