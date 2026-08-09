import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../calls/call_page.dart';
import '../calls/call_service.dart';
import '../core/brokers/broker_service.dart';
import '../core/crypto/crypto_service.dart';
import '../core/media/image_service.dart';
import '../core/media/image_viewer.dart';
import '../core/media/voice_composer.dart';
import '../core/media/voice_note.dart';
import '../core/media/voice_waveform.dart';
import '../core/notifications/notification_service.dart';
import '../core/settings/wallpaper_picker.dart';
import '../core/theme/background_controller.dart';
import '../core/widgets/connection_status.dart';
import '../core/widgets/liquid_glass.dart';
import '../core/widgets/person_avatar.dart';
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
  bool _recordingVoice = false;

  /// Whether the composer holds anything worth sending. Drives the round
  /// button between "send" and "hold to record", the way a messenger does.
  bool _hasText = false;

  /// The message being answered, shown quoted above the composer until it is
  /// sent or dismissed.
  RevampMessage? _replyTo;

  /// A message that was just jumped to from a quote, flashed briefly so the
  /// eye can find it in a wall of bubbles.
  String? _highlighted;

  /// One key per message that has been built, so a quote can scroll back to
  /// the message it quotes.
  final Map<String, GlobalKey> _messageKeys = {};

  final GlobalKey<VoiceComposerState> _voiceKey =
      GlobalKey<VoiceComposerState>();

  @override
  void initState() {
    super.initState();
    // Suppress notifications for the conversation the user is looking at.
    NotificationService.instance.activeChatId = widget.chat.id;
    _load();
    _service.addListener(_onChanged);
    _editorController.addListener(_onTyped);
  }

  /// The round button swaps between sending and recording, so the composer
  /// has to know when it goes from empty to not.
  void _onTyped() {
    final has = _editorController.document.toPlainText().trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
    // Called on every keystroke; the service does the throttling, because
    // how often to say it is a property of the protocol rather than of this
    // screen.
    _service.setTyping(widget.chat, has);
  }

  @override
  void dispose() {
    if (NotificationService.instance.activeChatId == widget.chat.id) {
      NotificationService.instance.activeChatId = null;
    }
    _service.removeListener(_onChanged);
    // Leaving the screen with half a sentence in the box is not typing.
    _service.setTyping(widget.chat, false);
    VoiceNotePlayer.instance.stop();
    _editorController.removeListener(_onTyped);
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
      replyTo: _replyTo,
    );
    if (sent && mounted) setState(() => _replyTo = null);
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

  /// Sends a finished recording as an ordinary message with an audio
  /// attachment, so it is encrypted, chunked, receipted and stored exactly
  /// like everything else in the conversation.
  Future<void> _sendVoice(VoiceRecording recording) async {
    final sent = await _service.sendText(
      widget.chat,
      _voiceLabel,
      audio: base64Encode(recording.bytes),
      audioMs: recording.duration.inMilliseconds,
      waveform: VoiceNotes.encodeWaveform(recording.waveform),
      replyTo: _replyTo,
    );
    if (sent && mounted) setState(() => _replyTo = null);
    if (!sent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).cannotSendLocked),
        ),
      );
    }
  }

  // ------------------------------------------------- what a message can do

  /// The six a messenger offers. More than this and the row stops being
  /// something the thumb can hit without reading.
  static const _reactionChoices = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  void _startReply(RevampMessage message) {
    if (message.deleted) return;
    HapticFeedback.selectionClick();
    setState(() => _replyTo = message);
    _editorFocus.requestFocus();
  }

  /// Scrolls back to the message a quote refers to, and flashes it.
  ///
  /// Two steps, because the list only builds what is on screen: an
  /// approximate jump by position in the conversation first, then — once
  /// that frame has been laid out and the target actually exists — an exact
  /// one. A quote whose original was never received (deleted here, or from
  /// before this device joined) says so rather than doing nothing.
  Future<void> _jumpTo(String id) async {
    final index = _messages.indexWhere((m) => m.id == id);
    if (index < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The original message is not here.')),
      );
      return;
    }
    if (_scrollController.hasClients && _messages.length > 1) {
      final extent = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(extent * index / (_messages.length - 1));
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted) return;
    final target = _messageKeys[id]?.currentContext;
    if (target != null && target.mounted) {
      await Scrollable.ensureVisible(target,
          duration: const Duration(milliseconds: 200), alignment: 0.4);
    }
    if (!mounted) return;
    setState(() => _highlighted = id);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted && _highlighted == id) setState(() => _highlighted = null);
  }

  /// Finds a message in this conversation and goes to it.
  ///
  /// A sheet rather than a bar over the list: the results have to show who
  /// said what and when to be worth anything, and a conversation searched
  /// for "tomorrow" can easily have thirty hits.
  Future<void> _searchInChat() async {
    final found = await showModalBottomSheet<RevampMessage>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _SearchSheet(messages: _messages, myFp: _myFp),
    );
    if (found != null) await _jumpTo(found.id);
  }

  Future<void> _react(RevampMessage message, String emoji) async {
    HapticFeedback.selectionClick();
    await _service.react(widget.chat, message, emoji);
  }

  void _copy(RevampMessage message) {
    Clipboard.setData(ClipboardData(text: message.text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied.')),
    );
  }

  /// Passes a message on to another conversation. It is sent afresh rather
  /// than moved: the other chat has its own key, and a forwarded message is
  /// labelled so nobody mistakes a repetition for the thing itself.
  Future<void> _forward(RevampMessage message) async {
    final others =
        _service.chats.where((c) => c.id != widget.chat.id).toList();
    if (others.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('There is nowhere else to send it.')),
      );
      return;
    }
    final target = await showModalBottomSheet<ChatEntry>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              dense: true,
              title: Text('Forward to',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final chat in others)
                    ListTile(
                      leading: Icon(chat.isDm
                          ? Icons.person_outline_rounded
                          : Icons.groups_rounded),
                      title: Text(chat.title),
                      onTap: () => Navigator.pop(context, chat),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (target == null) return;
    final sent = await _service.sendText(
      target,
      message.text,
      delta: message.delta,
      image: message.image,
      audio: message.audio,
      audioMs: message.audioMs,
      waveform: message.waveform,
      forwarded: true,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(sent ? 'Sent to ${target.title}.' : 'Could not send it.'),
      ),
    );
  }

  Future<void> _delete(RevampMessage message, bool mine) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: Text(mine
            ? 'Taking it back removes it from both devices. Deleting it here '
                'leaves the copy the other person already has.'
            : 'It is removed from this device. The person who sent it keeps '
                'their copy — only they can take it back.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'me'),
            child: const Text('Delete for me'),
          ),
          if (mine)
            FilledButton(
              onPressed: () => Navigator.pop(context, 'everyone'),
              child: const Text('Delete for everyone'),
            ),
        ],
      ),
    );
    if (choice == null) return;
    if (choice == 'me') {
      await _service.deleteForMe(widget.chat, message);
      return;
    }
    final error = await _service.deleteForEveryone(widget.chat, message);
    if (error != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  /// The long-press sheet: the reactions first, because they are what the
  /// gesture is most often for, then the things done to a message.
  void _openActions(RevampMessage message, bool mine) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!message.deleted)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final emoji in _reactionChoices)
                      IconButton(
                        onPressed: () {
                          Navigator.pop(sheet);
                          _react(message, emoji);
                        },
                        icon: Text(emoji,
                            style: const TextStyle(fontSize: 24)),
                      ),
                  ],
                ),
              ),
            const Divider(height: 8),
            if (!message.deleted)
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(sheet);
                  _startReply(message);
                },
              ),
            if (!message.deleted && message.text.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Copy'),
                onTap: () {
                  Navigator.pop(sheet);
                  _copy(message);
                },
              ),
            if (!message.deleted)
              ListTile(
                leading: const Icon(Icons.forward_rounded),
                title: const Text('Forward'),
                onTap: () {
                  Navigator.pop(sheet);
                  _forward(message);
                },
              ),
            if (!message.deleted)
              ListTile(
                leading: Icon(message.starred
                    ? Icons.star_rounded
                    : Icons.star_border_rounded),
                title: Text(message.starred ? 'Unstar' : 'Star'),
                onTap: () {
                  Navigator.pop(sheet);
                  _service.toggleStar(widget.chat, message);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(sheet);
                _delete(message, mine);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// One message: the bubble, whatever hangs off it, and the two gestures
  /// that reach it.
  ///
  /// The drag-to-reply is a [Dismissible] that never dismisses. It is the
  /// only widget in the framework that gives a horizontal drag with a
  /// rubber-band return and a threshold for free, and refusing the dismissal
  /// in [Dismissible.confirmDismiss] is what turns "swipe away" into "swipe
  /// and let go" — which is the gesture people already have for replying.
  Widget _buildMessage(RevampMessage message, ColorScheme scheme) {
    final mine = message.from.isNotEmpty && message.from == _myFp;
    final key = _messageKeys.putIfAbsent(message.id, GlobalKey.new);
    final highlighted = _highlighted == message.id;

    final bubble = WaMessageBubble(
      isMine: mine,
      timeStamp: message.deleted ? '' : message.timeLabel,
      // Only in a one-to-one chat: a group has no single "they have it", so
      // it shows no ticks at all.
      status: widget.chat.isDm && !message.deleted ? message.status : null,
      meta: message.starred
          ? Icon(Icons.star_rounded,
              size: 12, color: scheme.onSurface.withValues(alpha: 0.55))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine && !widget.chat.isDm && !message.deleted)
            Text(
              message.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: scheme.primary,
              ),
            ),
          if (message.forwarded && !message.deleted)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.forward_rounded,
                      size: 13,
                      color: scheme.onSurface.withValues(alpha: 0.55)),
                  const SizedBox(width: 4),
                  Text(
                    'Forwarded',
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: scheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
          if (message.isReply && !message.deleted)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _QuotedMessage(
                // An anonymous message has an id beginning with '-', which
                // an empty fingerprint would match — so nobody is "You"
                // until we know who we are.
                author: _myFp.isNotEmpty &&
                        message.replyTo!.startsWith('$_myFp-')
                    ? 'You'
                    : (message.replyName ?? ''),
                text: message.replyText ?? '',
                onTap: () => _jumpTo(message.replyTo!),
              ),
            ),
          if (message.deleted)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.block_rounded,
                    size: 14,
                    color: scheme.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 6),
                Text(
                  ChatService.deletedLabel,
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            )
          else
            _MessageBody(message: message),
          if (message.reactions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _Reactions(
                reactions: message.reactions,
                mine: _myFp,
                onTap: (emoji) => _react(message, emoji),
              ),
            ),
        ],
      ),
    );

    return KeyedSubtree(
      key: key,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        color: highlighted
            ? scheme.primary.withValues(alpha: 0.16)
            : Colors.transparent,
        child: Dismissible(
          key: ValueKey('swipe-${message.id}'),
          direction: message.deleted
              ? DismissDirection.none
              : DismissDirection.startToEnd,
          dismissThresholds: const {DismissDirection.startToEnd: 0.22},
          confirmDismiss: (_) async {
            _startReply(message);
            return false;
          },
          background: Padding(
            padding: const EdgeInsets.only(left: 22),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Icon(Icons.reply_rounded,
                  color: scheme.primary.withValues(alpha: 0.8)),
            ),
          ),
          child: GestureDetector(
            onLongPress: () => _openActions(message, mine),
            child: bubble,
          ),
        ),
      ),
    );
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
  Future<void> _startCall({bool video = false}) async {
    final error =
        await CallService.instance.call(widget.chat, withVideo: video);
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
            PersonAvatar(
              name: widget.chat.title,
              avatar: peer?.avatar,
              radius: 36,
              icon: widget.chat.isDm
                  ? Icons.person_rounded
                  : Icons.groups_rounded,
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
                // The header's tap opens the details sheet, which is the
                // route to the picture; a second meaning on the avatar
                // alone would just be a smaller, less findable version.
                PersonAvatar(
                  name: widget.chat.title,
                  avatar: peer?.avatar,
                  viewable: false,
                  icon: widget.chat.isDm
                      ? Icons.person_rounded
                      : Icons.groups_rounded,
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
                      // "typing…" takes the whole line while it lasts. It is
                      // the most perishable thing the header can say, and
                      // squeezing it in beside the fingerprint would make it
                      // the least noticeable.
                      if (_service.isTyping(widget.chat.id))
                        Text(
                          'typing…',
                          style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: scheme.primary,
                          ),
                        )
                      else
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
            IconButton(
              tooltip: 'Search in this chat',
              icon: const Icon(Icons.search_rounded),
              onPressed: _searchInChat,
            ),
            if (widget.chat.isDm) ...[
              IconButton(
                tooltip: 'Video call',
                icon: const Icon(Icons.videocam_rounded),
                onPressed: () => _startCall(video: true),
              ),
              IconButton(
                tooltip: l10n.call,
                icon: const Icon(Icons.call_rounded),
                onPressed: _startCall,
              ),
            ],
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
                  itemBuilder: (context, index) =>
                      _buildMessage(_messages[index], scheme),
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
              // What is being answered, above the composer, until it is sent
              // or dismissed — so a reply written a minute later is still
              // visibly a reply to something.
              if (_replyTo != null && !_recordingVoice)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: _QuotedMessage(
                          author: _myFp.isNotEmpty && _replyTo!.from == _myFp
                              ? 'You'
                              : _replyTo!.name,
                          text: ChatService.quotedPreview(_replyTo!),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cancel reply',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(() => _replyTo = null),
                      ),
                    ],
                  ),
                ),
              WaInputBar(
                onSend: _send,
                // An empty composer offers the microphone; the moment there
                // is something to say in writing, it becomes send again.
                // The recorder stays mounted while recording — it holds the
                // gesture and the elapsed time, and taking it out of the
                // tree mid-press would cancel both.
                action: _hasText || !VoiceNotes.canRecord
                    ? null
                    : VoiceComposer(
                        key: _voiceKey,
                        onRecorded: _sendVoice,
                        onRecordingChanged: (recording) =>
                            setState(() => _recordingVoice = recording),
                        onTick: () => setState(() {}),
                      ),
                // While recording there is nothing to format and nothing to
                // attach, and a discard button is what the hand wants.
                leading: _recordingVoice
                    ? [
                        IconButton(
                          tooltip: 'Discard',
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => _voiceKey.currentState?.discard(),
                        ),
                      ]
                    : [
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
                // The text field's place is taken by the level meter, so
                // the composer never shows a keyboard target that a tap
                // would use to interrupt the recording.
                child: _recordingVoice
                    ? VoiceRecordingStrip(
                        elapsed:
                            _voiceKey.currentState?.elapsed ?? Duration.zero,
                        level: _voiceKey.currentState?.level ?? 0,
                        locked: _voiceKey.currentState?.locked ?? false,
                        cancelProgress:
                            _voiceKey.currentState?.cancelProgress ?? 0,
                        lockProgress: _voiceKey.currentState?.lockProgress ?? 0,
                        samples:
                            _voiceKey.currentState?.samples ?? const [],
                      )
                    : Padding(
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

/// Searching one conversation. Matches are shown newest first, because that
/// is the half of a conversation anyone is usually looking for.
class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.messages, required this.myFp});

  final List<RevampMessage> messages;
  final String myFp;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  String _query = '';

  List<RevampMessage> get _results {
    final needle = _query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    return widget.messages.reversed
        .where((m) => !m.deleted && m.text.toLowerCase().contains(needle))
        .take(80)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final results = _results;
    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search this conversation',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _query.trim().isEmpty
                  ? const SizedBox.shrink()
                  : results.isEmpty
                      ? Center(
                          child: Text(
                            'Nothing matches.',
                            style: TextStyle(
                              color:
                                  scheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: results.length,
                          itemBuilder: (context, index) {
                            final message = results[index];
                            return ListTile(
                              dense: true,
                              title: Text(
                                message.from == widget.myFp
                                    ? 'You'
                                    : message.name,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: scheme.primary,
                                ),
                              ),
                              subtitle: Text(
                                message.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Text(
                                message.timeLabel,
                                style: const TextStyle(fontSize: 11),
                              ),
                              onTap: () => Navigator.pop(context, message),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The quoted block: above the composer while a reply is being written, and
/// inside the bubble once it has been sent. The same widget in both places
/// on purpose — what you are answering should look the same before and after
/// you answer it.
class _QuotedMessage extends StatelessWidget {
  const _QuotedMessage({required this.author, required this.text, this.onTap});

  final String author;
  final String text;

  /// Set inside a bubble, where the quote is a way back to the original.
  /// Null above the composer, where there is nowhere to go.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
          // The coloured spine is the whole visual grammar of a quote.
          border: Border(left: BorderSide(color: scheme.primary, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (author.isNotEmpty)
              Text(
                author,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: scheme.primary,
                ),
              ),
            Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The reactions on a message, grouped: one pill an emoji, with how many
/// people chose it. Ours is outlined, so it is obvious which one to tap
/// again to take it back.
class _Reactions extends StatelessWidget {
  const _Reactions({
    required this.reactions,
    required this.mine,
    required this.onTap,
  });

  /// Fingerprint to emoji.
  final Map<String, String> reactions;

  /// Our own fingerprint, to find ours among them.
  final String mine;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final counts = <String, int>{};
    for (final emoji in reactions.values) {
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }
    final ours = reactions[mine];
    return Wrap(
      spacing: 4,
      children: [
        for (final entry in counts.entries)
          InkWell(
            onTap: () => onTap(entry.key),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: entry.key == ours
                      ? scheme.primary
                      : scheme.onSurface.withValues(alpha: 0.15),
                ),
              ),
              child: Text(
                entry.value > 1 ? '${entry.key} ${entry.value}' : entry.key,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }
}

/// Preview text stored with a picture that has no caption.
const _photoLabel = '📷 Photo';

/// "14 Mar, 21:05" for the header of the full-screen picture.
String _sentAtLabel(int ts) {
  if (ts == 0) return '';
  final at = DateTime.fromMillisecondsSinceEpoch(ts);
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final hour = at.hour.toString().padLeft(2, '0');
  final minute = at.minute.toString().padLeft(2, '0');
  return '${at.day} ${months[at.month - 1]}, $hour:$minute';
}

/// Renders a message body: the attached picture when there is one, a
/// read-only Quill document when the sender used formatting, plain text
/// otherwise (which is also what older clients and LoRa-sized messages
/// carry).
class _MessageBody extends StatelessWidget {
  const _MessageBody({required this.message});

  final RevampMessage message;

  @override
  Widget build(BuildContext context) {
    final note = VoiceNotes.decode(message.audio);
    if (note != null) {
      return _VoiceBubble(
        id: '${message.from}-${message.ts}',
        bytes: note,
        duration: Duration(milliseconds: message.audioMs),
        waveform: VoiceNotes.decodeWaveform(message.waveform),
      );
    }
    final picture = ImageService.decode(message.image);
    if (picture != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tapping opens it full screen, where it can be zoomed, saved or
          // passed to another app.
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => ImageViewerPage(
                  bytes: picture,
                  title: message.name,
                  subtitle: _sentAtLabel(message.ts),
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(picture, fit: BoxFit.cover),
            ),
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

/// Preview text stored with a voice note, so a chat list and a notification
/// have something to say without decoding the audio.
const _voiceLabel = '🎤 Voice message';

/// A voice note in the conversation: play/pause, the shape of what was said,
/// and the length.
///
/// The waveform shows the *sent* length until playback starts, because that
/// is known from the message itself — waiting for the player to report a
/// duration would leave every note reading 0:00 until it was opened.
class _VoiceBubble extends StatelessWidget {
  const _VoiceBubble({
    required this.id,
    required this.bytes,
    required this.duration,
    this.waveform,
  });

  final String id;
  final Uint8List bytes;
  final Duration duration;

  /// The bars measured when the note was recorded, or null for a note that
  /// arrived without them.
  final Uint8List? waveform;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: VoiceNotePlayer.instance,
      builder: (context, _) {
        final player = VoiceNotePlayer.instance;
        final playing = player.isPlaying(id);
        final total = playing && player.duration > Duration.zero
            ? player.duration
            : duration;
        final position = playing ? player.position : Duration.zero;
        final progress = total.inMilliseconds == 0
            ? 0.0
            : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
        return SizedBox(
          width: 210,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(playing
                    ? Icons.pause_circle_filled_rounded
                    : Icons.play_circle_fill_rounded),
                iconSize: 34,
                color: scheme.primary,
                onPressed: () => player.toggle(id, bytes),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    VoiceWaveform(
                      bars: waveform,
                      progress: progress,
                      played: scheme.primary,
                      unplayed: scheme.onSurface.withValues(alpha: 0.3),
                      // Scrubbing only makes sense on the note that is
                      // actually playing; on the others the bars are a
                      // picture of it and dragging them would mean nothing.
                      onSeek: playing
                          ? (value) => player.seek(Duration(
                              milliseconds:
                                  (total.inMilliseconds * value).round()))
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 2),
                      child: Text(
                        voiceDurationLabel(playing ? position : total),
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurface.withValues(alpha: 0.7),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
