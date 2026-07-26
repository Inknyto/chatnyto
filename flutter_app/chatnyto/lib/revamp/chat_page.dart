import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../calls/call_page.dart';
import '../calls/call_service.dart';
import '../core/brokers/broker_service.dart';
import '../core/crypto/crypto_service.dart';
import '../core/media/image_service.dart';
import '../core/notifications/notification_service.dart';
import '../core/settings/wallpaper_picker.dart';
import '../core/theme/background_controller.dart';
import '../core/widgets/connection_status.dart';
import '../core/widgets/liquid_glass.dart';
import '../core/widgets/wa_components.dart';
import '../l10n/app_localizations.dart';
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
  final quill.QuillController _editorController =
      quill.QuillController.basic();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _editorScrollController = ScrollController();
  final FocusNode _editorFocus = FocusNode();
  List<RevampMessage> _messages = [];
  String _myFp = '';
  bool _showToolbar = false;
  bool _isOwner = false;
  bool _canAdminister = false;
  bool _sendingImage = false;

  @override
  void initState() {
    super.initState();
    // Suppress notifications for the conversation the user is looking at.
    NotificationService.instance.activeChatId = widget.chat.id;
    _load();
    _service.addListener(_onChanged);
  }

  @override
  void dispose() {
    if (NotificationService.instance.activeChatId == widget.chat.id) {
      NotificationService.instance.activeChatId = null;
    }
    _service.removeListener(_onChanged);
    _editorController.dispose();
    _editorScrollController.dispose();
    _editorFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (IdentityService.instance.isUnlocked) {
      _myFp =
          (await IdentityService.instance.publicIdentity()).fingerprint;
    }
    final owner = await _service.isGroupOwner(widget.chat);
    final admin = await _service.canAdministerGroup(widget.chat);
    final messages = await _service.messagesFor(widget.chat);
    _service.markRead(widget.chat);
    NotificationService.instance.activeChatId = widget.chat.id;
    if (mounted) {
      setState(() {
        _messages = List.of(messages);
        _isOwner = owner;
        _canAdminister = admin;
      });
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
    final document = _editorController.document;
    final text = document.toPlainText().trim();
    if (text.isEmpty) return;
    final delta = document.toDelta().toJson();
    // Only carry the formatting when there actually is some, so plain
    // messages stay small on a LoRa link.
    final formatted = delta.any((op) => op['attributes'] != null);
    final sent = await _service.sendText(
      widget.chat,
      text,
      delta: formatted ? delta : null,
    );
    if (!sent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).cannotSendLocked),
        ),
      );
      return;
    }
    _editorController.clear();
  }

  /// Renaming a group moves the whole conversation to a new topic, so it is
  /// restricted to the person who created it.
  Future<void> _renameGroup() async {
    final controller = TextEditingController(text: widget.chat.title);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).renameGroup),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: controller, autofocus: true),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).renameGroupHelp,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context).rename),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final error = await _service.renameChat(widget.chat, controller.text);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    } else {
      setState(() {});
    }
  }

  /// Rings this contact. Audio travels directly between the two devices, so
  /// both have to be on the same network.
  Future<void> _startCall() async {
    final error = await CallService.instance.call(widget.chat);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.push(
      context,
      GlassPageRoute(
          page: CallPage(avatar: widget.chat.peerIdentity?.avatar)),
    );
  }

  /// Attaches a picture: it is shrunk to a link-friendly size and sent in
  /// the same end-to-end encrypted envelope as a text message, using
  /// whatever is currently typed as its caption.
  Future<void> _attachImage() async {
    final source = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => LiquidGlass(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: Text(AppLocalizations.of(context).choosePicture),
              onTap: () => Navigator.pop(sheetContext, false),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: Text(AppLocalizations.of(context).takePhoto),
              onTap: () => Navigator.pop(sheetContext, true),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    setState(() => _sendingImage = true);
    final encoded =
        await ImageService.instance.pickAsBase64(fromCamera: source);
    if (!mounted) return;
    setState(() => _sendingImage = false);
    if (encoded == null) return;
    final caption = _editorController.document.toPlainText().trim();
    final sent = await _service.sendText(
      widget.chat,
      caption.isEmpty ? _photoLabel : caption,
      image: encoded,
    );
    if (!mounted) return;
    if (!sent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context).cannotSendLocked)),
      );
      return;
    }
    _editorController.clear();
  }

  /// Creator-only: pick, among the people visible on the network, who else
  /// may rename or delete this group.
  Future<void> _manageAdmins() async {
    final peers = BrokerService.instance.peers.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final selected = Set<String>.from(widget.chat.admins);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => AlertDialog(
          title: Text(AppLocalizations.of(context).groupAdmins),
          content: SizedBox(
            width: double.maxFinite,
            child: peers.isEmpty
                ? const Text(
                    'Nobody else is visible on the network yet. Admins can '
                    'be chosen once people appear in the People tab.')
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppLocalizations.of(context).groupAdminsHelp,
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final peer in peers)
                              CheckboxListTile(
                                dense: true,
                                title: Text(peer.name),
                                subtitle: Text(peer.fingerprint,
                                    style: const TextStyle(fontSize: 11)),
                                value:
                                    selected.contains(peer.ed25519PublicKey),
                                onChanged: (checked) => setSheetState(() {
                                  if (checked == true) {
                                    selected.add(peer.ed25519PublicKey);
                                  } else {
                                    selected.remove(peer.ed25519PublicKey);
                                  }
                                }),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final error =
        await _service.setGroupAdmins(widget.chat, selected.toList());
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${selected.length} admin(s) set for this group.')),
      );
    }
  }

  Future<void> _deleteGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${widget.chat.title}"?'),
        content: const Text(
            'The group disappears for everyone who joined it, and its '
            'messages are removed from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete for everyone'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final error = await _service.deleteGroupForEveryone(widget.chat);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    } else {
      Navigator.pop(context);
    }
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
    final l10n = AppLocalizations.of(context);
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
                Builder(builder: (context) {
                  final picture = ImageService.decode(peer?.avatar);
                  return CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    backgroundImage:
                        picture == null ? null : MemoryImage(picture),
                    child: picture != null
                        ? null
                        : Icon(
                            widget.chat.isDm
                                ? Icons.person_rounded
                                : Icons.groups_rounded,
                            color: scheme.onPrimaryContainer,
                          ),
                  );
                }),
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
                            Flexible(
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
                          const SizedBox(width: 8),
                          const ConnectionStatusChip(),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (widget.chat.isDm)
              IconButton(
                tooltip: l10n.call,
                icon: const Icon(Icons.call_rounded),
                onPressed: _startCall,
              ),
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
                  case 'rename':
                    await _renameGroup();
                  case 'delete':
                    await _deleteGroup();
                  case 'admins':
                    await _manageAdmins();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                    value: 'identity', child: Text(l10n.viewIdentity)),
                PopupMenuItem(
                    value: 'wallpaper',
                    child: Text(l10n.wallpaperForChat)),
                if (BackgroundController.instance
                    .hasOverride(widget.chat.id))
                  PopupMenuItem(
                      value: 'wallpaper_reset',
                      child: Text(l10n.useGlobalWallpaper)),
                if (_isOwner)
                  PopupMenuItem(
                      value: 'admins', child: Text(l10n.groupAdmins)),
                if (_canAdminister) ...[
                  PopupMenuItem(
                      value: 'rename', child: Text(l10n.renameGroup)),
                  PopupMenuItem(
                      value: 'delete',
                      child: Text(l10n.deleteGroupForEveryone)),
                ],
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
                          _MessageBody(message: message),
                        ],
                      ),
                    );
                  },
                ),
              ),
              if (_showToolbar)
                LiquidGlass(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  child: quill.QuillSimpleToolbar(
                    controller: _editorController,
                    config: const quill.QuillSimpleToolbarConfig(
                      showBoldButton: true,
                      showItalicButton: true,
                      showUnderLineButton: true,
                      showStrikeThrough: true,
                      showColorButton: true,
                      showBackgroundColorButton: true,
                      showListBullets: true,
                      showListNumbers: true,
                      showCodeBlock: true,
                      showQuote: true,
                      showFontFamily: false,
                      showFontSize: false,
                      showHeaderStyle: false,
                      showIndent: false,
                      showLink: false,
                      showSearchButton: false,
                      showAlignmentButtons: false,
                      showDividers: false,
                      showSubscript: false,
                      showSuperscript: false,
                    ),
                  ),
                ),
              WaInputBar(
                onSend: _send,
                leading: [
                  IconButton(
                    tooltip: l10n.formatting,
                    icon: Icon(_showToolbar
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.text_format_rounded),
                    onPressed: () =>
                        setState(() => _showToolbar = !_showToolbar),
                  ),
                  IconButton(
                    tooltip: l10n.sendPicture,
                    icon: _sendingImage
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.attach_file_rounded),
                    onPressed: _sendingImage ? null : _attachImage,
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: quill.QuillEditor(
                    controller: _editorController,
                    scrollController: _editorScrollController,
                    focusNode: _editorFocus,
                    config: quill.QuillEditorConfig(
                      placeholder: l10n.messageHint,
                      expands: false,
                      padding: EdgeInsets.zero,
                    ),
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

/// Preview text stored with a picture that has no caption.
const _photoLabel = '📷 Photo';

/// Renders a message body: the attached picture when there is one, a
/// read-only Quill document when the sender used formatting, plain text
/// otherwise (which is also what older clients and LoRa-sized messages
/// carry).
class _MessageBody extends StatelessWidget {
  const _MessageBody({required this.message});

  final RevampMessage message;

  @override
  Widget build(BuildContext context) {
    final picture = ImageService.decode(message.image);
    if (picture != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(picture, fit: BoxFit.cover),
          ),
          if (message.text.isNotEmpty && message.text != _photoLabel)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(message.text),
            ),
        ],
      );
    }
    if (!message.isRich) return Text(message.text);
    try {
      final controller = quill.QuillController(
        document: quill.Document.fromJson(message.delta!),
        selection: const TextSelection.collapsed(offset: 0),
        readOnly: true,
      );
      return quill.QuillEditor(
        controller: controller,
        scrollController: ScrollController(),
        focusNode: FocusNode(),
        config: const quill.QuillEditorConfig(
          showCursor: false,
          padding: EdgeInsets.zero,
        ),
      );
    } catch (_) {
      // Malformed delta from another client: fall back to the plain text.
      return Text(message.text);
    }
  }
}
