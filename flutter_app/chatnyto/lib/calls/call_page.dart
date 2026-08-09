import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../core/widgets/liquid_glass.dart';
import '../core/widgets/person_avatar.dart';
import 'call_service.dart';

/// The full-screen call: who you are talking to, how long for, and the
/// controls — ringing, connecting and connected all use the same layout so
/// nothing jumps around when the state changes.
class CallPage extends StatefulWidget {
  const CallPage({super.key, this.avatar});

  /// Base64 JPEG of the other person, when they published one.
  final String? avatar;

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  final CallService _calls = CallService.instance;

  @override
  void initState() {
    super.initState();
    _calls.addListener(_onChanged);
    _calls.bannerSuppressed = true;
  }

  @override
  void dispose() {
    _calls.removeListener(_onChanged);
    // After the frame: this runs while the route is being torn down, and
    // the banner that reappears must not be asked to rebuild mid-teardown.
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _calls.bannerSuppressed = false);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    // Leave the screen once the call is over.
    if (_calls.state == CallState.idle && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  String get _status {
    switch (_calls.state) {
      case CallState.dialling:
        return 'Calling…';
      case CallState.ringing:
        return 'Incoming call';
      case CallState.connecting:
        // Naming the network stage turns a hang into something diagnosable.
        return _calls.iceState.isEmpty
            ? 'Connecting…'
            : 'Connecting… (${_calls.iceState.toLowerCase()})';
      case CallState.active:
        return _calls.elapsedLabel;
      case CallState.ended:
        return _calls.endedReason ?? 'Call ended';
      case CallState.idle:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The caller's own screen is opened with the picture it already has;
    // an incoming call is pushed from the app shell, which knows nothing —
    // so the service carries it too.
    final avatar = widget.avatar?.isNotEmpty == true
        ? widget.avatar
        : _calls.peerAvatar;
    final ringing = _calls.state == CallState.ringing;
    final active = _calls.state == CallState.active;
    // With a picture on screen the avatar and the glass background are in
    // the way, so the whole layout changes rather than the video being
    // squeezed into the space the avatar had.
    if (_calls.videoCall && !ringing) return _videoLayout(scheme);
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              // Leaving a call running while you look something up is
              // normal; the banner at the top of the app brings you back.
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: 'Back to the app',
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  onPressed: Navigator.canPop(context)
                      ? () => Navigator.pop(context)
                      : null,
                ),
              ),
              const Spacer(),
              PersonAvatar(
                name: _calls.peerName,
                avatar: avatar,
                radius: 62,
              ),
              const SizedBox(height: 20),
              Text(
                _calls.peerName,
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _status,
                style: TextStyle(
                  fontSize: 15,
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 12),
              LiquidGlass(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                radius: 20,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_rounded, size: 14),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        // Worth saying which road the audio took: relayed
                        // calls sound narrower, and that is the reason.
                        _calls.relaying
                            ? 'End-to-end encrypted · relayed through your '
                                'network, because there is no direct route'
                            : 'End-to-end encrypted · direct between your '
                                'devices',
                        style: const TextStyle(fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (active || _calls.state == CallState.connecting)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _round(
                      icon: _calls.muted
                          ? Icons.mic_off_rounded
                          : Icons.mic_rounded,
                      label: _calls.muted ? 'Unmute' : 'Mute',
                      onTap: _calls.toggleMute,
                      background: scheme.surfaceContainerHighest,
                      foreground: scheme.onSurface,
                    ),
                    const SizedBox(width: 24),
                    _round(
                      icon: _calls.speakerOn
                          ? Icons.volume_up_rounded
                          : Icons.phone_in_talk_rounded,
                      label: _calls.speakerOn ? 'Speaker' : 'Earpiece',
                      onTap: _calls.toggleSpeaker,
                      background: scheme.surfaceContainerHighest,
                      foreground: scheme.onSurface,
                    ),
                    // Offered on every call, not only on ones that started
                    // as video: turning a voice call into a video one is
                    // the commonest reason to want a camera at all.
                    if (_calls.canUseCamera) ...[
                      const SizedBox(width: 24),
                      _round(
                        icon: Icons.videocam_rounded,
                        label: 'Video',
                        onTap: _calls.toggleCamera,
                        background: scheme.surfaceContainerHighest,
                        foreground: scheme.onSurface,
                      ),
                    ],
                  ],
                ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: ringing
                    ? MainAxisAlignment.spaceEvenly
                    : MainAxisAlignment.center,
                children: [
                  // Someone ringing with their camera on is asking for a
                  // video call, so answering with video is offered beside
                  // answering with voice — never instead of it. Being seen
                  // has to stay a choice made on this end.
                  if (ringing && _calls.peerCameraOn)
                    _round(
                      icon: Icons.videocam_rounded,
                      label: 'Video',
                      onTap: () => _calls.answer(withVideo: true),
                      background: Colors.green,
                      foreground: Colors.white,
                      size: 68,
                    ),
                  if (ringing)
                    _round(
                      icon: Icons.call_rounded,
                      label: _calls.peerCameraOn ? 'Voice' : 'Answer',
                      onTap: () => _calls.answer(),
                      background:
                          _calls.peerCameraOn ? Colors.teal : Colors.green,
                      foreground: Colors.white,
                      size: 68,
                    ),
                  _round(
                    icon: Icons.call_end_rounded,
                    label: ringing ? 'Decline' : 'End',
                    onTap: ringing
                        ? _calls.decline
                        : () => _calls.hangUp(),
                    background: Colors.red,
                    foreground: Colors.white,
                    size: 68,
                  ),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  /// The call as a picture: the other person fills the screen, this device's
  /// own camera sits in a corner, and everything else floats on top so none
  /// of it eats into the video.
  Widget _videoLayout(ColorScheme scheme) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_calls.peerCameraOn)
            RTCVideoView(
              _calls.remoteVideo,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            // Their camera is off but ours is not: their name and picture
            // hold the space, so the screen never goes blank.
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PersonAvatar(
                    name: _calls.peerName,
                    avatar: _calls.peerAvatar,
                    radius: 54,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _calls.peerName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  const Text('Camera off',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),

          // Name and timer over the video, in a gradient rather than a bar,
          // so they stay readable on a bright picture without boxing it in.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 4,
                bottom: 24,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back to the app',
                    icon: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: Colors.white),
                    onPressed: Navigator.canPop(context)
                        ? () => Navigator.pop(context)
                        : null,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          _calls.peerName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600),
                        ),
                        Text(_status,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Switch camera',
                    icon: const Icon(Icons.cameraswitch_rounded,
                        color: Colors.white),
                    onPressed: _calls.cameraOn ? _calls.switchCamera : null,
                  ),
                ],
              ),
            ),
          ),

          if (_calls.cameraOn)
            Positioned(
              right: 12,
              top: MediaQuery.of(context).padding.top + 64,
              width: 104,
              height: 150,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: RTCVideoView(
                  _calls.localVideo,
                  // A front camera shown unmirrored is the thing everybody
                  // notices and nobody can name.
                  mirror: _calls.frontCamera,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: 30,
                bottom: MediaQuery.of(context).padding.bottom + 24,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _round(
                    icon: _calls.muted
                        ? Icons.mic_off_rounded
                        : Icons.mic_rounded,
                    label: _calls.muted ? 'Unmute' : 'Mute',
                    onTap: _calls.toggleMute,
                    background: Colors.white24,
                    foreground: Colors.white,
                    labelColor: Colors.white,
                  ),
                  _round(
                    icon: _calls.cameraOn
                        ? Icons.videocam_rounded
                        : Icons.videocam_off_rounded,
                    label: _calls.cameraOn ? 'Camera' : 'Camera off',
                    onTap: _calls.toggleCamera,
                    background: Colors.white24,
                    foreground: Colors.white,
                    labelColor: Colors.white,
                  ),
                  _round(
                    icon: _calls.speakerOn
                        ? Icons.volume_up_rounded
                        : Icons.phone_in_talk_rounded,
                    label: _calls.speakerOn ? 'Speaker' : 'Earpiece',
                    onTap: _calls.toggleSpeaker,
                    background: Colors.white24,
                    foreground: Colors.white,
                    labelColor: Colors.white,
                  ),
                  _round(
                    icon: Icons.call_end_rounded,
                    label: 'End',
                    onTap: () => _calls.hangUp(),
                    background: Colors.red,
                    foreground: Colors.white,
                    labelColor: Colors.white,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _round({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color background,
    required Color foreground,
    double size = 56,
    // On the video layout the labels sit on the picture and have to be
    // light; on the ordinary one they follow the theme.
    Color? labelColor,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: background,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, color: foreground, size: size * 0.45),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 12, color: labelColor)),
      ],
    );
  }
}
