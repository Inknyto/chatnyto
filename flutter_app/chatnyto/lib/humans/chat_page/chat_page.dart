import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../../core/theme/background_controller.dart';
import '../../core/widgets/liquid_glass.dart';
import '../../core/widgets/wa_components.dart';
import 'mqtt_service.dart';
import 'message_storage.dart';
import 'models/chat_message.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.deviceIP,
    required this.brokerIP,
    required this.topicName,
    this.channelSecret = '',
  });

  final String brokerIP;
  final String topicName;
  final String deviceIP;

  /// Optional passphrase upgrading this channel to a private E2EE channel.
  final String channelSecret;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final MqttService _mqttService = MqttService();
  final MessageStorage _messageStorage = MessageStorage();
  final List<ChatMessage> _messages = [];
  late quill.QuillController _messageController;
  bool _isConnected = false;
  String _deviceIp = '';
  bool _showToolbar = false;

  @override
  void initState() {
    super.initState();
    _messageController = quill.QuillController.basic();
    _loadMessages();
    _connectToMqttBroker();
  }

  Future<void> _loadMessages() async {
    final loadedMessages = await _messageStorage.loadMessages(widget.brokerIP, widget.topicName);
    setState(() {
      _messages.addAll(loadedMessages);
    });
  }

  void _connectToMqttBroker() async {
    _deviceIp = await _mqttService.getDeviceIPAddress();
    _mqttService.connect(
      brokerIP: widget.brokerIP,
      topicName: widget.topicName,
      deviceIP: _deviceIp,
      channelSecret: widget.channelSecret,
      onConnected: () => setState(() => _isConnected = true),
      onDisconnected: () => setState(() => _isConnected = false),
      onMessageReceived: _onMessageReceived,
    );
  }

  void _onMessageReceived(ChatMessage message) {
          setState(() {
          _messages.add(message);
        });

    _messageStorage.saveMessages(_messages, widget.brokerIP, widget.topicName);
  }

  void _sendMessage() {
    if (_isConnected) {
      final delta = _messageController.document.toDelta().toJson();
      if (delta.isNotEmpty) {
        final message = ChatMessage(sender: _deviceIp, delta: delta);
        _mqttService.sendMessage(message);
// bad idea, since this adds the message on send, and not on recieve
//        setState(() {
//          _messages.add(message);
//        });
        _messageStorage.saveMessages(_messages, widget.brokerIP, widget.topicName);
        _messageController.clear();
      }
    } else {
      _showNotConnectedDialog();
    }
  }

  void _showNotConnectedDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Not Connected'),
          content: const Text('You are not connected to the MQTT broker.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leadingWidth: 30,
          title: Row(
            children: [
              CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                child: Text(
                  widget.topicName.isEmpty
                      ? '?'
                      : widget.topicName[0].toUpperCase(),
                  style: TextStyle(color: scheme.onPrimaryContainer),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.topicName,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _isConnected ? '$_deviceIp · online' : 'offline',
                      style: TextStyle(
                        fontSize: 12,
                        color: _isConnected
                            ? Colors.greenAccent
                            : scheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Tooltip(
                message: widget.channelSecret.isEmpty
                    ? 'Encrypted (public channel key)'
                    : 'End-to-end encrypted (private passphrase)',
                child: Icon(
                  widget.channelSecret.isEmpty
                      ? Icons.lock_outline_rounded
                      : Icons.lock_rounded,
                ),
              ),
            ),
          ],
        ),
        body: WallpaperBackdrop(
          child: Column(
            children: [
              Expanded(child: _buildMessageList()),
              if (_showToolbar) LiquidGlass(child: _buildToolbar()),
              _buildMessageInput(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return quill.QuillSimpleToolbar(
      controller: _messageController,
      config: const quill.QuillSimpleToolbarConfig(
        showBoldButton: true,
        showItalicButton: true,
        showUnderLineButton: true,
        showStrikeThrough: true,
        showColorButton: true,
        showBackgroundColorButton: true,
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return WaMessageBubble(
          isMine: message.sender == _deviceIp,
          timeStamp: message.timeLabel,
          child: quill.QuillEditor(
            controller: quill.QuillController(
              document: message.toDocument(),
              selection: const TextSelection.collapsed(offset: 0),
              readOnly: true,
            ),
            config: const quill.QuillEditorConfig(
              showCursor: false,
              padding: EdgeInsets.zero,
            ),
            scrollController: ScrollController(),
            focusNode: FocusNode(),
          ),
        );
      },
    );
  }

  Widget _buildMessageInput() {
    return WaInputBar(
      onSend: _sendMessage,
      leading: [
        IconButton(
          tooltip: 'Formatting',
          icon: Icon(_showToolbar
              ? Icons.keyboard_arrow_down_rounded
              : Icons.text_format_rounded),
          onPressed: () => setState(() => _showToolbar = !_showToolbar),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: quill.QuillEditor(
          controller: _messageController,
          config: const quill.QuillEditorConfig(
            autoFocus: true,
            placeholder: 'Message',
            expands: false,
            padding: EdgeInsets.zero,
          ),
          scrollController: ScrollController(),
          focusNode: FocusNode(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _mqttService.disconnect();
    _messageController.dispose();
    super.dispose();
  }
}
