import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_agent.dart';
import 'ai_provider.dart';
import 'mcp_client.dart';

/// One turn in an AI conversation. Tool traffic is kept in the same list so
/// the model sees a coherent history and the UI can show what it did.
class AiMessage {
  AiMessage({
    required this.role, // 'user' | 'assistant' | 'tool'
    required this.text,
    this.toolCalls = const [],
    this.toolCallId = '',
    this.toolName = '',
    int? ts,
  }) : ts = ts ?? DateTime.now().millisecondsSinceEpoch;

  final String role;
  String text;
  final List<AiToolCall> toolCalls;
  final String toolCallId;
  final String toolName;
  final int ts;

  bool get isUser => role == 'user';
  bool get isTool => role == 'tool';

  Map<String, dynamic> toJson() => {
        'role': role,
        'text': text,
        'ts': ts,
        if (toolCallId.isNotEmpty) 'toolCallId': toolCallId,
        if (toolName.isNotEmpty) 'toolName': toolName,
        if (toolCalls.isNotEmpty)
          'calls': toolCalls.map((c) => c.toJson()).toList(),
      };

  static AiMessage fromJson(Map<String, dynamic> json) => AiMessage(
        role: json['role'] as String,
        text: json['text'] as String? ?? '',
        ts: (json['ts'] as num?)?.toInt(),
        toolCallId: json['toolCallId'] as String? ?? '',
        toolName: json['toolName'] as String? ?? '',
        toolCalls: (json['calls'] as List? ?? [])
            .map((c) => AiToolCall.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

class AiToolCall {
  AiToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name; // qualified: <serverId>__<tool>
  final Map<String, dynamic> arguments;

  String get displayName => name.contains('__') ? name.split('__').last : name;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'arguments': arguments};

  static AiToolCall fromJson(Map<String, dynamic> json) => AiToolCall(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        arguments: Map<String, dynamic>.from(json['arguments'] as Map? ?? {}),
      );
}

/// Talks to whichever provider an agent is configured for, and runs the MCP
/// tool loop when the model asks for a tool.
class AiClient {
  AiClient._();

  static final AiClient instance = AiClient._();

  /// Maximum model round-trips per user turn, so a model that keeps asking
  /// for tools cannot loop forever.
  static const _maxToolRounds = 5;

  /// Sends [history] to the agent's model and returns every message
  /// produced (tool calls, tool results and the final answer), reporting
  /// each one through [onProgress] as it happens.
  Future<List<AiMessage>> send({
    required AiAgent agent,
    required List<AiMessage> history,
    void Function(AiMessage message)? onProgress,
  }) async {
    final provider = agent.provider;
    final key = await AiKeyStore.instance.read(agent.providerId) ?? '';
    if (provider.needsKey && key.isEmpty) {
      throw AiException(
          'No API key for ${provider.name}. Add one in AI settings.');
    }
    if (agent.baseUrl.isEmpty) {
      throw AiException('This agent has no server address configured.');
    }

    final tools = await McpClient.instance.toolsFor(agent);
    final produced = <AiMessage>[];
    var working = List<AiMessage>.from(history);

    for (var round = 0; round < _maxToolRounds; round++) {
      final reply = await _complete(agent, key, working, tools);
      produced.add(reply);
      working = [...working, reply];
      onProgress?.call(reply);

      if (reply.toolCalls.isEmpty) return produced;

      for (final call in reply.toolCalls) {
        final result = await _runTool(agent, call);
        produced.add(result);
        working = [...working, result];
        onProgress?.call(result);
      }
    }
    final gaveUp = AiMessage(
      role: 'assistant',
      text: 'Stopped after $_maxToolRounds rounds of tool calls.',
    );
    produced.add(gaveUp);
    onProgress?.call(gaveUp);
    return produced;
  }

  Future<AiMessage> _runTool(AiAgent agent, AiToolCall call) async {
    final parts = call.name.split('__');
    final serverId = parts.first;
    final toolName = parts.length > 1 ? parts.sublist(1).join('__') : call.name;
    final server = AiConfig.instance.servers
        .where((s) => s.id == serverId)
        .cast<McpServer?>()
        .firstWhere((s) => true, orElse: () => null);
    String output;
    if (server == null) {
      output = 'Unknown tool server.';
    } else {
      try {
        output =
            await McpClient.instance.callTool(server, toolName, call.arguments);
      } catch (error) {
        output = 'Tool failed: $error';
      }
    }
    return AiMessage(
      role: 'tool',
      text: output,
      toolCallId: call.id,
      toolName: call.displayName,
    );
  }

  Future<AiMessage> _complete(AiAgent agent, String key,
      List<AiMessage> history, List<McpTool> tools) async {
    switch (agent.provider.protocol) {
      case AiProtocol.anthropic:
        return _anthropic(agent, key, history, tools);
      case AiProtocol.gemini:
        return _gemini(agent, key, history, tools);
      case AiProtocol.openAiCompatible:
        return _openAi(agent, key, history, tools);
    }
  }

  // ------------------------------------------------------- OpenAI-shaped

  Future<AiMessage> _openAi(AiAgent agent, String key,
      List<AiMessage> history, List<McpTool> tools) async {
    final messages = <Map<String, dynamic>>[
      if (agent.systemPrompt.isNotEmpty)
        {'role': 'system', 'content': agent.systemPrompt},
    ];
    for (final message in history) {
      if (message.isTool) {
        messages.add({
          'role': 'tool',
          'tool_call_id': message.toolCallId,
          'content': message.text,
        });
      } else if (message.toolCalls.isNotEmpty) {
        messages.add({
          'role': 'assistant',
          'content': message.text.isEmpty ? null : message.text,
          'tool_calls': [
            for (final call in message.toolCalls)
              {
                'id': call.id,
                'type': 'function',
                'function': {
                  'name': call.name,
                  'arguments': jsonEncode(call.arguments),
                },
              },
          ],
        });
      } else {
        messages.add({'role': message.role, 'content': message.text});
      }
    }

    final body = <String, dynamic>{
      'model': agent.model,
      'messages': messages,
      'temperature': agent.temperature,
      if (tools.isNotEmpty)
        'tools': [
          for (final tool in tools)
            {
              'type': 'function',
              'function': {
                'name': tool.qualifiedName,
                'description': '${tool.description} (${tool.serverName})',
                'parameters': tool.inputSchema,
              },
            },
        ],
    };

    final json = await _post(
      '${agent.baseUrl}/chat/completions',
      headers: {
        'content-type': 'application/json',
        if (key.isNotEmpty) 'authorization': 'Bearer $key',
      },
      body: body,
    );

    final choice = (json['choices'] as List?)?.firstOrNull;
    final message = choice?['message'] as Map<String, dynamic>? ?? {};
    final calls = <AiToolCall>[];
    for (final raw in (message['tool_calls'] as List? ?? [])) {
      final function = raw['function'] as Map<String, dynamic>;
      calls.add(AiToolCall(
        id: raw['id'] as String? ?? function['name'] as String,
        name: function['name'] as String,
        arguments: _decodeArguments(function['arguments']),
      ));
    }
    return AiMessage(
      role: 'assistant',
      text: (message['content'] as String?)?.trim() ?? '',
      toolCalls: calls,
    );
  }

  // ---------------------------------------------------------- Anthropic

  Future<AiMessage> _anthropic(AiAgent agent, String key,
      List<AiMessage> history, List<McpTool> tools) async {
    final messages = <Map<String, dynamic>>[];
    for (final message in history) {
      if (message.isTool) {
        messages.add({
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': message.toolCallId,
              'content': message.text,
            }
          ],
        });
      } else if (message.toolCalls.isNotEmpty) {
        messages.add({
          'role': 'assistant',
          'content': [
            if (message.text.isNotEmpty)
              {'type': 'text', 'text': message.text},
            for (final call in message.toolCalls)
              {
                'type': 'tool_use',
                'id': call.id,
                'name': call.name,
                'input': call.arguments,
              },
          ],
        });
      } else {
        messages.add({'role': message.role, 'content': message.text});
      }
    }

    final json = await _post(
      '${agent.baseUrl}/messages',
      headers: {
        'content-type': 'application/json',
        'x-api-key': key,
        'anthropic-version': '2023-06-01',
      },
      body: {
        'model': agent.model,
        'max_tokens': 4096,
        'temperature': agent.temperature,
        if (agent.systemPrompt.isNotEmpty) 'system': agent.systemPrompt,
        'messages': messages,
        if (tools.isNotEmpty)
          'tools': [
            for (final tool in tools)
              {
                'name': tool.qualifiedName,
                'description': '${tool.description} (${tool.serverName})',
                'input_schema': tool.inputSchema,
              },
          ],
      },
    );

    final buffer = StringBuffer();
    final calls = <AiToolCall>[];
    for (final block in (json['content'] as List? ?? [])) {
      final map = block as Map<String, dynamic>;
      if (map['type'] == 'text') {
        buffer.write(map['text'] as String? ?? '');
      } else if (map['type'] == 'tool_use') {
        calls.add(AiToolCall(
          id: map['id'] as String? ?? '',
          name: map['name'] as String? ?? '',
          arguments: Map<String, dynamic>.from(map['input'] as Map? ?? {}),
        ));
      }
    }
    return AiMessage(
      role: 'assistant',
      text: buffer.toString().trim(),
      toolCalls: calls,
    );
  }

  // ------------------------------------------------------------- Gemini

  Future<AiMessage> _gemini(AiAgent agent, String key, List<AiMessage> history,
      List<McpTool> tools) async {
    final contents = <Map<String, dynamic>>[];
    for (final message in history) {
      if (message.isTool) {
        contents.add({
          'role': 'user',
          'parts': [
            {
              'functionResponse': {
                'name': message.toolName,
                'response': {'result': message.text},
              }
            }
          ],
        });
      } else if (message.toolCalls.isNotEmpty) {
        contents.add({
          'role': 'model',
          'parts': [
            if (message.text.isNotEmpty) {'text': message.text},
            for (final call in message.toolCalls)
              {
                'functionCall': {
                  'name': call.name,
                  'args': call.arguments,
                }
              },
          ],
        });
      } else {
        contents.add({
          'role': message.isUser ? 'user' : 'model',
          'parts': [
            {'text': message.text}
          ],
        });
      }
    }

    final json = await _post(
      '${agent.baseUrl}/models/${agent.model}:generateContent',
      headers: {
        'content-type': 'application/json',
        'x-goog-api-key': key,
      },
      body: {
        'contents': contents,
        'generationConfig': {'temperature': agent.temperature},
        if (agent.systemPrompt.isNotEmpty)
          'systemInstruction': {
            'parts': [
              {'text': agent.systemPrompt}
            ]
          },
        if (tools.isNotEmpty)
          'tools': [
            {
              'functionDeclarations': [
                for (final tool in tools)
                  {
                    'name': tool.qualifiedName,
                    'description':
                        '${tool.description} (${tool.serverName})',
                    'parameters': tool.inputSchema,
                  },
              ]
            }
          ],
      },
    );

    final parts = (json['candidates'] as List?)?.firstOrNull?['content']
            ?['parts'] as List? ??
        [];
    final buffer = StringBuffer();
    final calls = <AiToolCall>[];
    var index = 0;
    for (final part in parts) {
      final map = part as Map<String, dynamic>;
      if (map['text'] != null) buffer.write(map['text']);
      final call = map['functionCall'] as Map<String, dynamic>?;
      if (call != null) {
        calls.add(AiToolCall(
          id: 'gemini-${index++}',
          name: call['name'] as String? ?? '',
          arguments: Map<String, dynamic>.from(call['args'] as Map? ?? {}),
        ));
      }
    }
    return AiMessage(
      role: 'assistant',
      text: buffer.toString().trim(),
      toolCalls: calls,
    );
  }

  // ------------------------------------------------------------ plumbing

  Map<String, dynamic> _decodeArguments(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        // Models occasionally emit invalid JSON; treat it as no arguments.
      }
    }
    return {};
  }

  Future<Map<String, dynamic>> _post(
    String url, {
    required Map<String, String> headers,
    required Map<String, dynamic> body,
  }) async {
    late http.Response response;
    try {
      response = await http
          .post(Uri.parse(url), headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 120));
    } catch (error) {
      throw AiException('Could not reach the model: $error');
    }
    if (response.statusCode >= 400) {
      throw AiException(_explain(response));
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } catch (error) {
      throw AiException('The provider sent a reply we could not read.');
    }
  }

  /// Turns a provider error into something a user can act on.
  String _explain(http.Response response) {
    String detail = response.body;
    try {
      final json = jsonDecode(response.body);
      detail = (json['error']?['message'] ?? json['message'] ?? detail)
          .toString();
    } catch (_) {
      // Keep the raw body.
    }
    switch (response.statusCode) {
      case 401:
      case 403:
        return 'The provider refused the API key ($detail).';
      case 404:
        return 'Unknown model or endpoint ($detail).';
      case 429:
        return 'Rate limited by the provider — try again shortly.';
      default:
        return 'Provider error ${response.statusCode}: $detail';
    }
  }
}

class AiException implements Exception {
  AiException(this.message);

  final String message;

  @override
  String toString() => message;
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
