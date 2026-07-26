import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_provider.dart';

/// A configured AI agent: which provider and model to use, how it should
/// behave, and which MCP servers it may call tools on.
///
/// The API key never lives here — it is kept per provider in the device
/// keystore (see [AiKeyStore]), so exporting or syncing agents can never
/// leak it.
class AiAgent {
  AiAgent({
    required this.id,
    required this.name,
    required this.providerId,
    required this.model,
    this.baseUrlOverride = '',
    this.systemPrompt = '',
    this.temperature = 0.7,
    List<String>? mcpServerIds,
  }) : mcpServerIds = mcpServerIds ?? [];

  final String id;
  String name;
  String providerId;
  String model;

  /// Set for self-hosted or proxied endpoints (Ollama on another machine,
  /// an OpenAI-compatible gateway).
  String baseUrlOverride;

  String systemPrompt;
  double temperature;

  /// MCP servers this agent is allowed to use tools from.
  List<String> mcpServerIds;

  AiProvider get provider => AiProvider.byId(providerId);

  String get baseUrl =>
      baseUrlOverride.isNotEmpty ? baseUrlOverride : provider.baseUrl;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'provider': providerId,
        'model': model,
        'baseUrl': baseUrlOverride,
        'system': systemPrompt,
        'temperature': temperature,
        'mcp': mcpServerIds,
      };

  static AiAgent fromJson(Map<String, dynamic> json) => AiAgent(
        id: json['id'] as String,
        name: json['name'] as String,
        providerId: json['provider'] as String,
        model: json['model'] as String? ?? '',
        baseUrlOverride: json['baseUrl'] as String? ?? '',
        systemPrompt: json['system'] as String? ?? '',
        temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
        mcpServerIds:
            json['mcp'] == null ? null : List<String>.from(json['mcp']),
      );
}

/// An MCP server the app can call tools on.
///
/// Only the streamable HTTP transport is supported: a phone cannot spawn
/// the stdio servers that desktop MCP hosts launch, so servers must be
/// reachable over HTTP — including on the local network, which fits the
/// offline-first story.
class McpServer {
  McpServer({
    required this.id,
    required this.name,
    required this.url,
    this.enabled = true,
  });

  final String id;
  String name;
  String url;
  bool enabled;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'url': url, 'enabled': enabled};

  static McpServer fromJson(Map<String, dynamic> json) => McpServer(
        id: json['id'] as String,
        name: json['name'] as String,
        url: json['url'] as String,
        enabled: json['enabled'] as bool? ?? true,
      );
}

/// Stores agents and MCP servers (preferences) and API keys (keystore).
class AiConfig extends ChangeNotifier {
  AiConfig._();

  static final AiConfig instance = AiConfig._();

  static const _agentsKey = 'ai.agents.v1';
  static const _serversKey = 'ai.mcp.v1';

  final List<AiAgent> _agents = [];
  final List<McpServer> _servers = [];
  bool _loaded = false;

  List<AiAgent> get agents => List.unmodifiable(_agents);
  List<McpServer> get servers => List.unmodifiable(_servers);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    _agents.addAll((prefs.getStringList(_agentsKey) ?? []).map(
        (s) => AiAgent.fromJson(jsonDecode(s) as Map<String, dynamic>)));
    _servers.addAll((prefs.getStringList(_serversKey) ?? []).map(
        (s) => McpServer.fromJson(jsonDecode(s) as Map<String, dynamic>)));
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _agentsKey, _agents.map((a) => jsonEncode(a.toJson())).toList());
    await prefs.setStringList(
        _serversKey, _servers.map((s) => jsonEncode(s.toJson())).toList());
  }

  static String newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  Future<void> saveAgent(AiAgent agent) async {
    final index = _agents.indexWhere((a) => a.id == agent.id);
    if (index == -1) {
      _agents.add(agent);
    } else {
      _agents[index] = agent;
    }
    await _save();
    notifyListeners();
  }

  Future<void> removeAgent(AiAgent agent) async {
    _agents.removeWhere((a) => a.id == agent.id);
    await _save();
    notifyListeners();
  }

  Future<void> saveServer(McpServer server) async {
    final index = _servers.indexWhere((s) => s.id == server.id);
    if (index == -1) {
      _servers.add(server);
    } else {
      _servers[index] = server;
    }
    await _save();
    notifyListeners();
  }

  Future<void> removeServer(McpServer server) async {
    _servers.removeWhere((s) => s.id == server.id);
    for (final agent in _agents) {
      agent.mcpServerIds.remove(server.id);
    }
    await _save();
    notifyListeners();
  }

  List<McpServer> serversFor(AiAgent agent) => _servers
      .where((s) => s.enabled && agent.mcpServerIds.contains(s.id))
      .toList();
}

/// API keys, one per provider, kept in the platform keystore.
class AiKeyStore {
  AiKeyStore._();

  static final AiKeyStore instance = AiKeyStore._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static String _key(String providerId) => 'ai.key.$providerId';

  Future<String?> read(String providerId) async {
    try {
      return await _storage.read(key: _key(providerId));
    } catch (error) {
      debugPrint('Could not read the API key: $error');
      return null;
    }
  }

  Future<void> write(String providerId, String value) async {
    try {
      if (value.isEmpty) {
        await _storage.delete(key: _key(providerId));
      } else {
        await _storage.write(key: _key(providerId), value: value);
      }
    } catch (error) {
      debugPrint('Could not store the API key: $error');
    }
  }

  Future<bool> has(String providerId) async =>
      (await read(providerId))?.isNotEmpty ?? false;
}
