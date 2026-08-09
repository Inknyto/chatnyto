import 'package:flutter/material.dart';

import '../media/image_service.dart';
import '../media/image_viewer.dart';

/// Someone's face, wherever they appear.
///
/// A profile picture is the fastest way to recognise who a row is about, so
/// every list, header and sheet that names a person should show it — and
/// every one of them should show it the same way, which is what this widget
/// is for. Where there is no picture, the initial on a coloured disc stands
/// in, rather than a grey silhouette that makes everyone look alike.
///
/// Tapping opens the picture full screen, with the same zoom, save and share
/// as a picture from a chat. Someone's face is a picture like any other, and
/// looking at it properly should not require them to send it to you.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.name,
    this.avatar,
    this.radius = 24,
    this.icon,
    this.viewable = true,
    this.onTap,
    this.online,
  });

  final String name;

  /// Base64 JPEG, as advertised with the person's identity.
  final String? avatar;

  final double radius;

  /// Stands in for the initial — for a group, or a robot.
  final IconData? icon;

  /// Whether a tap opens the picture. Off where the tap already means
  /// something else, like opening the conversation.
  final bool viewable;

  /// Overrides the tap entirely.
  final VoidCallback? onTap;

  /// Online status: null = no indicator, true = green dot, false = gray dot.
  final bool? online;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final picture = ImageService.decode(avatar);
    final circle = picture != null
        ? CircleAvatar(radius: radius, backgroundImage: MemoryImage(picture))
        : CircleAvatar(
            radius: radius,
            backgroundColor: scheme.primaryContainer,
            child: icon != null
                ? Icon(icon,
                    color: scheme.onPrimaryContainer, size: radius * 0.9)
                : Text(
                    name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                      fontSize: radius * 0.8,
                    ),
                  ),
          );

    // Add online status indicator if provided
    final avatar = online != null
        ? Stack(
            children: [
              circle,
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: radius * 0.45,
                  height: radius * 0.45,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: online! ? Colors.greenAccent : Colors.grey,
                    border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ],
          )
        : circle;

    final action = onTap ??
        (viewable && picture != null
            ? () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ImageViewerPage(
                      bytes: picture,
                      title: name,
                      subtitle: 'Profile picture',
                    ),
                  ),
                )
            : null);
    if (action == null) return avatar;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: action,
      child: avatar,
    );
  }
}
