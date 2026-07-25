import 'package:flutter/material.dart';

import 'liquid_glass.dart';

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
    this.isSender = false,
    this.isRead = false,
    this.leadingIcon,
    this.onTap,
    this.onLongPress,
  });

  final String title;
  final String subtitle;
  final String timeStamp;
  final int unreadCount;
  final bool isSender;
  final bool isRead;
  final IconData? leadingIcon;
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
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: scheme.primaryContainer,
          child: leadingIcon != null
              ? Icon(leadingIcon, color: scheme.onPrimaryContainer)
              : Text(
                  title.isEmpty ? '?' : title[0].toUpperCase(),
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
            if (isSender) ...[
              Icon(
                Icons.done_all_rounded,
                size: 16,
                color: isRead
                    ? const Color(0xFF00AEFF)
                    : scheme.onSurface.withOpacity(0.5),
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
  });

  final bool isMine;
  final Widget child;
  final String timeStamp;
  final bool showTicks;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width;
    final bubbleColor = isMine
        ? scheme.primaryContainer.withOpacity(isDark ? 0.55 : 0.75)
        : scheme.surface.withOpacity(isDark ? 0.45 : 0.75);
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
                  if (isMine && showTicks) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.done_all_rounded,
                        size: 14, color: Color(0xFF00AEFF)),
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
