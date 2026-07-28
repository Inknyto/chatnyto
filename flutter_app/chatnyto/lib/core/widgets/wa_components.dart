import 'package:flutter/material.dart';

import '../../revamp/chat_service.dart' show MessageStatus;
import '../theme/glass_controller.dart';
import 'liquid_glass.dart';
import 'person_avatar.dart';

/// WhatsApp-clone components (chat list tile, message bubble, input bar)
/// re-styled with the liquid glass design language.

/// Chat list entry: avatar, name, message preview, timestamp, ticks and an
/// unread badge — the layout of the clone's MessagesWidget.
class WaChatTile extends StatelessWidget {
  const WaChatTile({
    super.key,
    required this.title,
    required this.subtitle,
    this.timeStamp = '',
    this.unreadCount = 0,
    this.lastStatus,
    this.leadingIcon,
    this.avatar,
    this.onTap,
    this.onLongPress,
  });

  final String title;
  final String subtitle;
  final String timeStamp;
  final int unreadCount;

  /// Set when the newest message is one of ours, so the preview carries the
  /// same tick as the bubble does. Null for anything we did not send.
  final MessageStatus? lastStatus;
  final IconData? leadingIcon;

  /// Base64 JPEG profile picture, when the person published one.
  final String? avatar;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LiquidGlass(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        // Not viewable here: in a list of conversations the whole row means
        // "open this chat", and a tap that did something else would be a
        // trap the width of a thumbnail.
        leading: PersonAvatar(
          name: title,
          avatar: avatar,
          icon: leadingIcon,
          viewable: false,
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (timeStamp.isNotEmpty)
              Text(
                timeStamp,
                style: TextStyle(
                  fontSize: 12,
                  color: unreadCount > 0
                      ? scheme.primary
                      : scheme.onSurface.withOpacity(0.6),
                ),
              ),
          ],
        ),
        subtitle: Row(
          children: [
            if (lastStatus != null) ...[
              _StatusTicks(
                status: lastStatus!,
                dim: scheme.onSurface.withOpacity(0.5),
              ),
              const SizedBox(width: 5),
            ],
            Expanded(
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurface.withOpacity(0.65)),
              ),
            ),
            if (unreadCount > 0)
              Container(
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(6),
                child: Text(
                  '$unreadCount',
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Sender/receiver message bubble in the clone's shape (three rounded
/// corners, timestamp + ticks bottom-right), on a translucent glass card.
class WaMessageBubble extends StatelessWidget {
  const WaMessageBubble({
    super.key,
    required this.isMine,
    required this.child,
    this.timeStamp = '',
    this.showTicks = true,
    this.status,
  });

  final bool isMine;
  final Widget child;
  final String timeStamp;
  final bool showTicks;

  /// How far this message has got. Null in a group, where "delivered" has
  /// no single answer, and the ticks are left off rather than guessed at.
  final MessageStatus? status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width;
    // Bubbles follow the same solidity slider as the rest of the glass.
    return ValueListenableBuilder<double>(
      valueListenable: GlassController.instance,
      builder: (context, solidity, _) => _bubble(
        context,
        scheme,
        isDark,
        width,
        (isDark ? 0.30 + 0.45 * solidity : 0.48 + 0.45 * solidity)
            .clamp(0.0, 1.0),
      ),
    );
  }

  Widget _bubble(BuildContext context, ColorScheme scheme, bool isDark,
      double width, double bubbleOpacity) {
    final bubbleColor = isMine
        ? scheme.primaryContainer.withOpacity(bubbleOpacity)
        : scheme.surface.withOpacity(bubbleOpacity);
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width * .72),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(isMine ? 14 : 2),
              topRight: Radius.circular(isMine ? 2 : 14),
              bottomLeft: const Radius.circular(14),
              bottomRight: const Radius.circular(14),
            ),
            border: Border.all(
              color: Colors.white.withOpacity(isDark ? 0.08 : 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              child,
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (timeStamp.isNotEmpty)
                    Text(
                      timeStamp,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurface.withOpacity(0.55),
                      ),
                    ),
                  if (isMine && showTicks && status != null) ...[
                    const SizedBox(width: 4),
                    _StatusTicks(
                      status: status!,
                      dim: scheme.onSurface.withOpacity(0.55),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The tick, or ticks, at the corner of your own message.
///
/// A clock while it is still waiting for a network, one tick once a broker
/// has it, two once the other device has answered for it, and two in blue
/// once the person has opened the conversation. Each step is something the
/// app actually observed — nothing here is decoration.
class _StatusTicks extends StatelessWidget {
  const _StatusTicks({required this.status, required this.dim});

  final MessageStatus status;
  final Color dim;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageStatus.pending:
        return Icon(Icons.schedule_rounded, size: 13, color: dim);
      case MessageStatus.sent:
        return Icon(Icons.done_rounded, size: 14, color: dim);
      case MessageStatus.delivered:
        return Icon(Icons.done_all_rounded, size: 14, color: dim);
      case MessageStatus.read:
        return const Icon(Icons.done_all_rounded,
            size: 14, color: Color(0xFF00AEFF));
    }
  }
}

/// Rounded input bar + circular send button, like the clone's
/// SendMessageAndRecordAudioWidget, hosting an arbitrary editor [child].
class WaInputBar extends StatelessWidget {
  const WaInputBar({
    super.key,
    required this.child,
    required this.onSend,
    this.leading,
    this.trailing,
  });

  final Widget child;
  final VoidCallback onSend;
  final List<Widget>? leading;
  final List<Widget>? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: LiquidGlass(
              radius: 24,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ...?leading,
                  Expanded(child: child),
                  ...?trailing,
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: onSend,
              icon: Icon(Icons.send_rounded, color: scheme.onPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
