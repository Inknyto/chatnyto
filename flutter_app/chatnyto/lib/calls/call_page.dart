import 'package:flutter/material.dart';

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
                  ],
                ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: ringing
                    ? MainAxisAlignment.spaceEvenly
                    : MainAxisAlignment.center,
                children: [
                  if (ringing)
                    _round(
                      icon: Icons.call_rounded,
                      label: 'Answer',
                      onTap: _calls.answer,
                      background: Colors.green,
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

  Widget _round({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color background,
    required Color foreground,
    double size = 56,
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
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
