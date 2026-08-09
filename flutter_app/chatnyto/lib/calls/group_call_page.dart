import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../core/widgets/person_avatar.dart';
import 'group_call_service.dart';

/// A group call: one tile a person, and a ring round whoever is talking.
///
/// The grid is square-ish rather than a row of thumbnails under one big
/// picture. In a call with no server there is no "main speaker" the system
/// decided on — everybody's stream arrives on equal terms — and a layout
/// that promotes one of them would be inventing an authority that does not
/// exist. The highlight does the work instead: it is measured, it moves, and
/// it costs nobody any screen space when nobody is talking.
class GroupCallPage extends StatefulWidget {
  const GroupCallPage({super.key});

  @override
  State<GroupCallPage> createState() => _GroupCallPageState();
}

class _GroupCallPageState extends State<GroupCallPage> {
  final GroupCallService _calls = GroupCallService.instance;

  @override
  void initState() {
    super.initState();
    _calls.addListener(_onChanged);
  }

  @override
  void dispose() {
    _calls.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    // The call ending is the screen's cue to leave, wherever it was reached
    // from.
    if (!_calls.inCall && Navigator.canPop(context)) {
      Navigator.pop(context);
      return;
    }
    setState(() {});
  }

  /// How many tiles fit across. Two is right for almost every group this can
  /// hold; one avoids a tall thin sliver when it is just the two of you.
  int _columns(int tiles, double width) {
    if (tiles <= 1) return 1;
    if (tiles <= 4) return 2;
    return width > 500 ? 3 : 2;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final others = _calls.participants;
    final tiles = others.length + 1;

    return PopScope(
      // Backing out goes back to the conversation; it does not leave the
      // call. Leaving is a deliberate act with a red button.
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _calls.chat?.title ?? 'Group call',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${_calls.headcount} in the call · '
                            '${_calls.elapsedLabel}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_calls.cameraOn)
                      IconButton(
                        tooltip: 'Switch camera',
                        onPressed: _calls.switchCamera,
                        icon: const Icon(Icons.cameraswitch_rounded,
                            color: Colors.white),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => GridView.count(
                    padding: const EdgeInsets.all(8),
                    crossAxisCount: _columns(tiles, constraints.maxWidth),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.8,
                    children: [
                      _Tile(
                        name: 'You',
                        speaking: _calls.isSpeaking(_calls.myFingerprint),
                        muted: _calls.muted,
                        cameraOn: _calls.cameraOn,
                        renderer: _calls.localVideo,
                        mirror: _calls.frontCamera,
                        connecting: false,
                      ),
                      for (final participant in others)
                        _Tile(
                          name: participant.name,
                          speaking: _calls.isSpeaking(participant.fingerprint),
                          muted: false,
                          cameraOn: participant.cameraOn,
                          renderer: participant.video,
                          mirror: false,
                          connecting: !participant.connected,
                        ),
                    ],
                  ),
                ),
              ),
              if (others.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Waiting for somebody to join. They will see the call in '
                    'the group.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _round(
                      icon: _calls.muted
                          ? Icons.mic_off_rounded
                          : Icons.mic_rounded,
                      label: _calls.muted ? 'Unmute' : 'Mute',
                      onTap: _calls.toggleMute,
                      active: _calls.muted,
                      scheme: scheme,
                    ),
                    _round(
                      icon: _calls.cameraOn
                          ? Icons.videocam_rounded
                          : Icons.videocam_off_rounded,
                      label: 'Camera',
                      onTap: _calls.toggleCamera,
                      active: _calls.cameraOn,
                      scheme: scheme,
                    ),
                    _round(
                      icon: _calls.speakerOn
                          ? Icons.volume_up_rounded
                          : Icons.phone_in_talk_rounded,
                      label: 'Speaker',
                      onTap: _calls.toggleSpeaker,
                      active: _calls.speakerOn,
                      scheme: scheme,
                    ),
                    _round(
                      icon: Icons.call_end_rounded,
                      label: 'Leave',
                      onTap: _calls.leave,
                      active: false,
                      background: Colors.redAccent,
                      scheme: scheme,
                    ),
                  ],
                ),
              ),
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
    required bool active,
    required ColorScheme scheme,
    Color? background,
  }) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: background ??
                (active
                    ? Colors.white.withValues(alpha: 0.9)
                    : Colors.white.withValues(alpha: 0.15)),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Icon(
                  icon,
                  color: background != null
                      ? Colors.white
                      : (active ? Colors.black87 : Colors.white),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 11,
            ),
          ),
        ],
      );
}

/// One person's square.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.name,
    required this.speaking,
    required this.muted,
    required this.cameraOn,
    required this.renderer,
    required this.mirror,
    required this.connecting,
  });

  final String name;
  final bool speaking;
  final bool muted;
  final bool cameraOn;
  final RTCVideoRenderer renderer;
  final bool mirror;
  final bool connecting;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        // The whole point of the tile: a ring that follows the voice.
        border: Border.all(
          color: speaking ? scheme.primary : Colors.transparent,
          width: 3,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (cameraOn && renderer.textureId != null)
              RTCVideoView(
                renderer,
                mirror: mirror,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            else
              Center(
                child: PersonAvatar(name: name, radius: 28, viewable: false),
              ),
            if (connecting)
              Container(
                color: Colors.black45,
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white70),
                ),
              ),
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              child: Row(
                children: [
                  if (muted)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.mic_off_rounded,
                          size: 14, color: Colors.white70),
                    ),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
