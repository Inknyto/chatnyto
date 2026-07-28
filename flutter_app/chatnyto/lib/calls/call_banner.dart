import 'package:flutter/material.dart';

import 'call_service.dart';

/// The strip that says "you are on a call" wherever you happen to be.
///
/// A call and the rest of the app are not alternatives: people look up an
/// address, check a message or read something out while they are talking.
/// Leaving the call screen has to be allowed, and once it is allowed there
/// has to be a way back — otherwise the call is running somewhere you cannot
/// reach, and the only way to hang up is to wait for the other person.
///
/// Sits above everything, like the system call bar it is modelled on, and
/// hides itself while the call screen is the thing on screen.
class CallBanner extends StatefulWidget {
  const CallBanner({super.key, required this.onTap, required this.child});

  /// Opens the call screen.
  final VoidCallback onTap;

  /// Whatever the app was already showing.
  final Widget child;

  @override
  State<CallBanner> createState() => _CallBannerState();
}

class _CallBannerState extends State<CallBanner> {
  final CallService _calls = CallService.instance;

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
    if (mounted) setState(() {});
  }

  /// Shown for a call that is up or on its way up, but not while it is
  /// ringing — a ring gets the whole screen, not a strip.
  bool get _visible =>
      !_calls.bannerSuppressed &&
      (_calls.state == CallState.active ||
          _calls.state == CallState.connecting ||
          _calls.state == CallState.dialling);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    return Stack(
      children: [
        // The app keeps its full height and slides down under the banner,
        // rather than being resized — a relayout on every call would move
        // whatever the user was reading.
        Padding(
          padding: EdgeInsets.only(top: _visible ? 34 : 0),
          child: widget.child,
        ),
        if (_visible)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Material(
              color: Colors.green.shade700,
              child: InkWell(
                onTap: widget.onTap,
                child: Padding(
                  padding: EdgeInsets.only(
                    top: media.padding.top,
                    bottom: 6,
                    left: 12,
                    right: 12,
                  ),
                  child: DefaultTextStyle(
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.phone_in_talk_rounded,
                            size: 15, color: Colors.white),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _calls.state == CallState.active
                                ? '${_calls.peerName} · '
                                    '${_calls.elapsedLabel}'
                                : 'Calling ${_calls.peerName}…',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text('Tap to return',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.white
                                  .withValues(alpha: scheme.brightness ==
                                          Brightness.dark
                                      ? 0.85
                                      : 0.9),
                            )),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
