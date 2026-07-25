import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/crypto/crypto_service.dart';
import '../core/settings/wallpaper_picker.dart';
import '../core/theme/background_controller.dart';
import '../core/widgets/liquid_glass.dart';
import '../core/widgets/wa_components.dart';
import 'chat_service.dart';

/// The revamped chat screen: identity of the person in the header, WA-style
/// bubbles on the chosen wallpaper, simple text input.
class RevampChatPage extends StatefulWidget {
  const RevampChatPage({super.key, required this.chat});

  final ChatEntry chat;

  @override
  State<RevampChatPage> createState() => _RevampChatPageState();
}

class _RevampChatPageState extends State<RevampChatPage> {
  final ChatService _service = ChatService.instance;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<RevampMessage> _messages = [];
  String _myFp = '';

  @override
  void initState() {
    super.initState();
    _load();
    _service.addListener(_onChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onChanged);
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (IdentityService.instance.isUnlocked) {
      _myFp =
          (await IdentityService.instance.publicIdentity()).fingerprint;
    }
    final messages = await _service.messagesFor(widget.chat);
    _service.markRead(widget.chat);
    if (mounted) {
      setState(() => _messages = List.of(messages));
      _scrollToEnd();
    }
  }

  void _onChanged() => _load();

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController
            .jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    final sent = await _service.sendText(widget.chat, text);
    if (!sent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot send: unlock your identity first '
              '(menu → Security & identity).'),
        ),
      );
      return;
    }
    _textController.clear();
  }

  void _showIdentitySheet() {
    final peer = widget.chat.peerIdentity;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => LiquidGlass(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 36,
              child: Icon(
                widget.chat.isDm
                    ? Icons.person_rounded
                    : Icons.groups_rounded,
                size: 36,
              ),
            ),
            const SizedBox(height: 12),
            Text(widget.chat.title,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (peer != null) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.verified_rounded,
                      color: Colors.greenAccent, size: 18),
                  const SizedBox(width: 6),
                  Text('Verified key · ${peer.fingerprint}'),
                ],
              ),
              const SizedBox(height: 8),
              SelectableText(
                'Public key: ${peer.x25519PublicKey}',
                style: const TextStyle(fontSize: 12),
                maxLines: 2,
              ),
              TextButton.icon(
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy public key'),
                onPressed: () => Clipboard.setData(
                    ClipboardData(text: peer.x25519PublicKey)),
              ),
              const SizedBox(height: 4),
              const Text(
                'Messages in this chat are end-to-end encrypted with a key '
                'only the two of you can compute.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
            ] else ...[
              Text('Encrypted group · topic ${widget.chat.topic}',
                  style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              Text(
                widget.chat.secret.isEmpty
                    ? 'Anyone who creates a group with the same name joins '
                        'this conversation.'
                    : 'Protected by a shared passphrase.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final peer = widget.chat.peerIdentity;
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leadingWidth: 30,
          title: InkWell(
            onTap: _showIdentitySheet,
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(
                    widget.chat.isDm
                        ? Icons.person_rounded
                        : Icons.groups_rounded,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.chat.title,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        children: [
                          if (peer != null) ...[
                            const Icon(Icons.verified_rounded,
                                color: Colors.greenAccent, size: 13),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                peer.fingerprint,
                                style: const TextStyle(fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ] else
                            Text(
                              'encrypted group',
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            PopupMenuButton<String>(
              onSelected: (choice) async {
                switch (choice) {
                  case 'identity':
                    _showIdentitySheet();
                  case 'wallpaper':
                    await Navigator.push(
                      context,
                      GlassPageRoute(
                        page: WallpaperPickerPage(chatId: widget.chat.id),
                      ),
                    );
                    if (mounted) setState(() {});
                  case 'wallpaper_reset':
                    await BackgroundController.instance
                        .selectForChat(widget.chat.id, null);
                    if (mounted) setState(() {});
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                    value: 'identity', child: Text('View identity')),
                const PopupMenuItem(
                    value: 'wallpaper',
                    child: Text('Wallpaper for this chat')),
                if (BackgroundController.instance
                    .hasOverride(widget.chat.id))
                  const PopupMenuItem(
                      value: 'wallpaper_reset',
                      child: Text('Use global wallpaper')),
              ],
            ),
          ],
        ),
        body: WallpaperBackdrop(
          chatId: widget.chat.id,
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    final mine = message.from.isNotEmpty
                        ? message.from == _myFp
                        : false;
                    return WaMessageBubble(
                      isMine: mine,
                      timeStamp: message.timeLabel,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!mine && !widget.chat.isDm)
                            Text(
                              message.name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: scheme.primary,
                              ),
                            ),
                          Text(message.text),
                        ],
                      ),
                    );
                  },
                ),
              ),
              WaInputBar(
                onSend: _send,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  child: TextField(
                    controller: _textController,
                    minLines: 1,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      filled: false,
                      hintText: 'Message',
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
