import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/background_controller.dart';
import '../core/widgets/liquid_glass.dart';
import '../core/widgets/wa_components.dart';
import '../l10n/app_localizations.dart';
import 'ai_agent.dart';
import 'ai_client.dart';

/// Conversation with one AI agent, in the same bubbles as the human chats.
/// Tool calls appear inline so it is always visible what the agent did on
/// your behalf.
class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key, required this.agent});

  final AiAgent agent;

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<AiMessage> _messages = [];
  bool _thinking = false;
  String? _error;

  String get _storageKey => 'ai.history.${widget.agent.id}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_storageKey) ?? [];
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(stored.map(
            (s) => AiMessage.fromJson(jsonDecode(s) as Map<String, dynamic>)));
    });
    _scrollToEnd();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    // Keep the tail only: model context is bounded anyway.
    final tail = _messages.length > 200
        ? _messages.sublist(_messages.length - 200)
        : _messages;
    await prefs.setStringList(
        _storageKey, tail.map((m) => jsonEncode(m.toJson())).toList());
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _thinking) return;
    _input.clear();
    setState(() {
      _messages.add(AiMessage(role: 'user', text: text));
      _thinking = true;
      _error = null;
    });
    _scrollToEnd();
    await _save();

    try {
      await AiClient.instance.send(
        agent: widget.agent,
        history: List.of(_messages),
        onProgress: (message) {
          if (!mounted) return;
          setState(() => _messages.add(message));
          _scrollToEnd();
        },
      );
    } on AiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _thinking = false);
      await _save();
      _scrollToEnd();
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear this conversation?'),
        content: const Text('The messages are removed from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(_messages.clear);
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible =
        _messages.where((m) => m.isUser || m.isTool || m.text.isNotEmpty ||
            m.toolCalls.isNotEmpty).toList();
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leadingWidth: 30,
          title: Row(
            children: [
              CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                child: Icon(Icons.auto_awesome_rounded,
                    color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.agent.name,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis),
                    Text(
                      _thinking
                          ? AppLocalizations.of(context).aiThinking
                          : widget.agent.model,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurface.withValues(alpha: 0.65),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: AppLocalizations.of(context).aiClearConversation,
              icon: const Icon(Icons.delete_sweep_rounded),
              onPressed: _clear,
            ),
          ],
        ),
        body: WallpaperBackdrop(
          chatId: 'ai:${widget.agent.id}',
          child: Column(
            children: [
              Expanded(
                child: visible.isEmpty
                    ? Center(
                        child: LiquidGlass(
                          margin: const EdgeInsets.all(24),
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'Say something to ${widget.agent.name}.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: visible.length,
                        itemBuilder: (context, index) =>
                            _bubble(visible[index], scheme),
                      ),
              ),
              if (_error != null)
                LiquidGlass(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: Colors.redAccent),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_error!)),
                    ],
                  ),
                ),
              if (_thinking)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              WaInputBar(
                onSend: _send,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 5,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      filled: false,
                      hintText: AppLocalizations.of(context).messageHint,
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

  Widget _bubble(AiMessage message, ColorScheme scheme) {
    if (message.isTool) return _toolCard(message, scheme, isResult: true);
    if (message.toolCalls.isNotEmpty && message.text.isEmpty) {
      return Column(
        children: [
          for (final call in message.toolCalls) _callCard(call, scheme),
        ],
      );
    }
    return Column(
      children: [
        WaMessageBubble(
          isMine: message.isUser,
          showTicks: false,
          timeStamp: _time(message.ts),
          child: SelectableText(message.text),
        ),
        for (final call in message.toolCalls) _callCard(call, scheme),
      ],
    );
  }

  Widget _callCard(AiToolCall call, ColorScheme scheme) => LiquidGlass(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            const Icon(Icons.build_rounded, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Using ${call.displayName}'
                '${call.arguments.isEmpty ? '' : ' ${jsonEncode(call.arguments)}'}',
                style: const TextStyle(fontSize: 12),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );

  Widget _toolCard(AiMessage message, ColorScheme scheme,
          {bool isResult = false}) =>
      LiquidGlass(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_outline_rounded, size: 16),
                const SizedBox(width: 8),
                Text('${message.toolName} result',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              message.text,
              style: const TextStyle(fontSize: 12),
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );

  String _time(int ts) {
    final time = DateTime.fromMillisecondsSinceEpoch(ts);
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }
}
