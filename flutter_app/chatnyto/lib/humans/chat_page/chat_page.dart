import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'mqtt_service.dart';
import 'message_storage.dart';
import 'models/chat_message.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.deviceIP,
    required this.brokerIP,
    required this.topicName
  });

  final String brokerIP;
  final String topicName;
  final String deviceIP;

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
    return Scaffold(
      appBar: AppBar(
        title: Text(_isConnected ? 'Chatnyto, $_deviceIp 🟢Online' : 'Chatnyto, $_deviceIp 🔴Offline'),
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          if (_showToolbar) _buildToolbar(),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return quill.QuillToolbar.simple(
      configurations: quill.QuillSimpleToolbarConfigurations(
        controller: _messageController,
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
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: quill.QuillEditor(
            configurations: quill.QuillEditorConfigurations(
              controller: quill.QuillController(
                document: _messages[index].toDocument(),
                selection: const TextSelection.collapsed(offset: 0),
                readOnly: true,
              ),
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
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
        
          IconButton(
            icon: Icon(_showToolbar ? Icons.arrow_drop_up_sharp : Icons.arrow_drop_down_sharp),
            onPressed: () => setState(() => _showToolbar = !_showToolbar),
          ),
       
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: quill.QuillEditor(
                configurations: quill.QuillEditorConfigurations(
                  controller: _messageController,
                  autoFocus: true,
                  placeholder: 'Type a message...',
                  expands: false,
                  padding: EdgeInsets.zero,
                ),
                scrollController: ScrollController(),
                focusNode: FocusNode(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _sendMessage,
          ),
        ],
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