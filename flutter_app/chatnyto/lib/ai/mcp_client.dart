import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ai_agent.dart';

/// A tool an MCP server offers, in the form the model APIs want it.
class McpTool {
  McpTool({
    required this.serverId,
    required this.serverName,
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  final String serverId;
  final String serverName;
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  /// Namespaced name sent to the model, so two servers can both offer a
  /// tool called "search" without colliding.
  String get qualifiedName => '${serverId}__$name';
}

/// Minimal Model Context Protocol client over streamable HTTP.
///
/// It speaks JSON-RPC 2.0: `initialize`, then `tools/list` and
/// `tools/call`. Responses may come back as plain JSON or as an SSE stream
/// (`text/event-stream`), and both are handled. stdio servers are out of
/// scope — a phone cannot spawn processes — so servers are reached over
/// HTTP, local network included.
class McpClient {
  McpClient._();

  static final McpClient instance = McpClient._();

  static const _protocolVersion = '2025-06-18';

  final Map<String, String> _sessions = {}; // server id -> session id
  final Map<String, List<McpTool>> _toolCache = {};

  int _nextId = 1;

  /// Lists the tools of every server the agent may use. Servers that fail
  /// are skipped: one unreachable server must not break the conversation.
  Future<List<McpTool>> toolsFor(AiAgent agent) async {
    final tools = <McpTool>[];
    for (final server in AiConfig.instance.serversFor(agent)) {
      try {
        tools.addAll(await listTools(server));
      } catch (error) {
        debugPrint('MCP server ${server.name} unavailable: $error');
      }
    }
    return tools;
  }

  Future<List<McpTool>> listTools(McpServer server,
      {bool refresh = false}) async {
    if (!refresh && _toolCache.containsKey(server.id)) {
      return _toolCache[server.id]!;
    }
    await _initialize(server);
    final result = await _rpc(server, 'tools/list', {});
    final list = (result?['tools'] as List? ?? []).map((raw) {
      final tool = raw as Map<String, dynamic>;
      return McpTool(
        serverId: server.id,
        serverName: server.name,
        name: tool['name'] as String,
        description: tool['description'] as String? ?? '',
        inputSchema: Map<String, dynamic>.from(
            tool['inputSchema'] as Map? ?? {'type': 'object'}),
      );
    }).toList();
    _toolCache[server.id] = list;
    return list;
  }

  /// Runs a tool and returns its result rendered as text for the model.
  Future<String> callTool(
    McpServer server,
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    await _initialize(server);
    final result = await _rpc(server, 'tools/call', {
      'name': toolName,
      'arguments': arguments,
    });
    if (result == null) return 'The tool returned nothing.';
    if (result['isError'] == true) {
      return 'Tool error: ${_renderContent(result['content'])}';
    }
    return _renderContent(result['content']);
  }

  String _renderContent(dynamic content) {
    if (content is! List) return jsonEncode(content);
    final parts = <String>[];
    for (final item in content) {
      if (item is! Map) continue;
      switch (item['type']) {
        case 'text':
          parts.add(item['text'] as String? ?? '');
        case 'resource':
          final resource = item['resource'];
          parts.add(resource is Map
              ? (resource['text'] as String? ?? jsonEncode(resource))
              : jsonEncode(resource));
        default:
          parts.add(jsonEncode(item));
      }
    }
    return parts.join('\n').trim();
  }

  Future<void> _initialize(McpServer server) async {
    if (_sessions.containsKey(server.id)) return;
    final response = await _post(server, {
      'jsonrpc': '2.0',
      'id': _nextId++,
      'method': 'initialize',
      'params': {
        'protocolVersion': _protocolVersion,
        'capabilities': {},
        'clientInfo': {'name': 'ChatNyto', 'version': '1.0'},
      },
    });
    // Servers that keep state hand back a session id to quote from then on.
    final session = response.headers['mcp-session-id'];
    _sessions[server.id] = session ?? '';
    _decode(response); // surfaces a protocol error early
    await _post(server, {
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
    });
  }

  Future<Map<String, dynamic>?> _rpc(
      McpServer server, String method, Map<String, dynamic> params) async {
    final response = await _post(server, {
      'jsonrpc': '2.0',
      'id': _nextId++,
      'method': method,
      'params': params,
    });
    final message = _decode(response);
    if (message == null) return null;
    if (message['error'] != null) {
      throw Exception(message['error']['message'] ?? 'MCP error');
    }
    return message['result'] as Map<String, dynamic>?;
  }

  Future<http.Response> _post(
      McpServer server, Map<String, dynamic> body) async {
    final session = _sessions[server.id];
    final response = await http
        .post(
          Uri.parse(server.url),
          headers: {
            'content-type': 'application/json',
            'accept': 'application/json, text/event-stream',
            if (session != null && session.isNotEmpty)
              'mcp-session-id': session,
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode >= 400) {
      throw Exception('MCP ${response.statusCode}: ${response.body}');
    }
    return response;
  }

  /// Reads a JSON-RPC message out of either a plain JSON body or an SSE
  /// stream, which the streamable HTTP transport may use for either.
  Map<String, dynamic>? _decode(http.Response response) {
    final body = utf8.decode(response.bodyBytes).trim();
    if (body.isEmpty) return null;
    if (!body.startsWith('{') && !body.startsWith('[')) {
      Map<String, dynamic>? last;
      for (final line in const LineSplitter().convert(body)) {
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty || payload == '[DONE]') continue;
        try {
          last = jsonDecode(payload) as Map<String, dynamic>;
        } catch (_) {
          // Ignore keep-alive or non-JSON events.
        }
      }
      return last;
    }
    final decoded = jsonDecode(body);
    if (decoded is List) {
      return decoded.isEmpty ? null : decoded.last as Map<String, dynamic>;
    }
    return decoded as Map<String, dynamic>;
  }

  void forget(McpServer server) {
    _sessions.remove(server.id);
    _toolCache.remove(server.id);
  }
}
