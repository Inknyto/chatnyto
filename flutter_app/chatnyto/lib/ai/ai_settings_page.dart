import 'package:flutter/material.dart';

import '../core/widgets/liquid_glass.dart';
import '../l10n/app_localizations.dart';
import 'ai_agent.dart';
import 'ai_provider.dart';
import 'mcp_client.dart';

/// Provider keys (BYOK) and MCP tool servers.
class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  final AiConfig _config = AiConfig.instance;
  final Map<String, bool> _hasKey = {};

  @override
  void initState() {
    super.initState();
    _config.load();
    _config.addListener(_onChanged);
    _refreshKeys();
  }

  @override
  void dispose() {
    _config.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshKeys() async {
    for (final provider in AiProvider.all) {
      if (!provider.needsKey) continue;
      _hasKey[provider.id] = await AiKeyStore.instance.has(provider.id);
    }
    if (mounted) setState(() {});
  }

  Future<void> _editKey(AiProvider provider) async {
    final controller = TextEditingController();
    final existing = await AiKeyStore.instance.read(provider.id) ?? '';
    controller.text = existing;
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(provider.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).aiApiKey,
                helperText: AppLocalizations.of(context).aiApiKeyHelp,
                helperMaxLines: 2,
              ),
            ),
            if (provider.keyUrl.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Get a key at ${provider.keyUrl}',
                  style: const TextStyle(fontSize: 12)),
            ],
          ],
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
    );
    if (saved == true) {
      await AiKeyStore.instance.write(provider.id, controller.text.trim());
      await _refreshKeys();
    }
  }

  Future<void> _editServer({McpServer? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final urlController = TextEditingController(text: existing?.url ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Add a tool server' : 'Edit server'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).brokerName),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: urlController,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).aiMcpEndpoint,
                hintText: 'https://example.com/mcp',
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'ChatNyto speaks MCP over HTTP, so the server can run on this '
              'network or anywhere reachable. Servers launched as a local '
              'command (stdio) cannot be used from a phone.',
              style: TextStyle(fontSize: 12),
            ),
          ],
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
    );
    if (saved != true) return;
    if (nameController.text.trim().isEmpty ||
        urlController.text.trim().isEmpty) {
      return;
    }
    final server = McpServer(
      id: existing?.id ?? AiConfig.newId(),
      name: nameController.text.trim(),
      url: urlController.text.trim(),
      enabled: existing?.enabled ?? true,
    );
    McpClient.instance.forget(server);
    await _config.saveServer(server);
  }

  /// Connects to a server and reports what it offers — the quickest way to
  /// tell a working endpoint from a typo.
  Future<void> _testServer(McpServer server) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Asking ${server.name} for its tools…')),
    );
    try {
      McpClient.instance.forget(server);
      final tools = await McpClient.instance.listTools(server, refresh: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tools.isEmpty
              ? '${server.name} answered, but offers no tools.'
              : '${server.name}: ${tools.map((t) => t.name).join(', ')}'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
            title: Text(AppLocalizations.of(context).aiProvidersAndTools)),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
              child: Text(
                AppLocalizations.of(context).aiByokIntro,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            for (final provider in AiProvider.all)
              if (provider.needsKey)
                LiquidGlass(
                  margin: const EdgeInsets.symmetric(vertical: 5),
                  child: ListTile(
                    leading: Icon(
                      _hasKey[provider.id] == true
                          ? Icons.key_rounded
                          : Icons.key_off_rounded,
                      color: _hasKey[provider.id] == true
                          ? Colors.greenAccent
                          : null,
                    ),
                    title: Text(provider.name),
                    subtitle: Text(
                      _hasKey[provider.id] == true
                          ? AppLocalizations.of(context).aiKeySaved
                          : (provider.note.isNotEmpty
                              ? provider.note
                              : AppLocalizations.of(context).aiNoKeyYet),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _editKey(provider),
                  ),
                ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 20, 4, 4),
              child: Text(
                AppLocalizations.of(context).aiToolsMcp,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(
                AppLocalizations.of(context).aiToolsMcpHelp,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            for (final server in _config.servers)
              LiquidGlass(
                margin: const EdgeInsets.symmetric(vertical: 5),
                child: ListTile(
                  leading: Icon(
                    Icons.build_rounded,
                    color: server.enabled ? Colors.lightBlueAccent : null,
                  ),
                  title: Text(server.name),
                  subtitle: Text(server.url),
                  onTap: () => _editServer(existing: server),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Test',
                        icon: const Icon(Icons.play_arrow_rounded),
                        onPressed: () => _testServer(server),
                      ),
                      Switch(
                        value: server.enabled,
                        onChanged: (value) {
                          server.enabled = value;
                          _config.saveServer(server);
                        },
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => _config.removeServer(server),
                      ),
                    ],
                  ),
                ),
              ),
            LiquidGlass(
              margin: const EdgeInsets.symmetric(vertical: 5),
              child: ListTile(
                leading: const Icon(Icons.add_rounded),
                title: Text(AppLocalizations.of(context).aiAddToolServer),
                onTap: () => _editServer(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Create or edit one agent.
class AiAgentEditPage extends StatefulWidget {
  const AiAgentEditPage({super.key, required this.agent, this.isNew = false});

  final AiAgent agent;
  final bool isNew;

  @override
  State<AiAgentEditPage> createState() => _AiAgentEditPageState();
}

class _AiAgentEditPageState extends State<AiAgentEditPage> {
  late final TextEditingController _name =
      TextEditingController(text: widget.agent.name);
  late final TextEditingController _model =
      TextEditingController(text: widget.agent.model);
  late final TextEditingController _baseUrl =
      TextEditingController(text: widget.agent.baseUrlOverride);
  late final TextEditingController _system =
      TextEditingController(text: widget.agent.systemPrompt);
  late String _providerId = widget.agent.providerId;
  late double _temperature = widget.agent.temperature;
  late final Set<String> _servers = Set.from(widget.agent.mcpServerIds);

  @override
  void dispose() {
    _name.dispose();
    _model.dispose();
    _baseUrl.dispose();
    _system.dispose();
    super.dispose();
  }

  AiProvider get _provider => AiProvider.byId(_providerId);

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _model.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A name and a model are required.')),
      );
      return;
    }
    widget.agent
      ..name = name
      ..providerId = _providerId
      ..model = _model.text.trim()
      ..baseUrlOverride = _baseUrl.text.trim()
      ..systemPrompt = _system.text.trim()
      ..temperature = _temperature
      ..mcpServerIds = _servers.toList();
    await AiConfig.instance.saveAgent(widget.agent);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final servers = AiConfig.instance.servers;
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(widget.isNew
              ? AppLocalizations.of(context).aiNewAgent
              : AppLocalizations.of(context).aiEditAgent),
          actions: [
            IconButton(
              icon: const Icon(Icons.check_rounded),
              onPressed: _save,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            LiquidGlass(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  TextField(
                    controller: _name,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context).aiAgentName,
                      hintText: 'Research buddy',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _providerId,
                    decoration: InputDecoration(
                        labelText: AppLocalizations.of(context).aiProvider),
                    items: [
                      for (final provider in AiProvider.all)
                        DropdownMenuItem(
                          value: provider.id,
                          child: Text(provider.name),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _providerId = value;
                        final models = AiProvider.byId(value).models;
                        if (models.isNotEmpty) _model.text = models.first;
                      });
                    },
                  ),
                  if (_provider.note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_provider.note,
                          style: const TextStyle(fontSize: 12)),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _model,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context).aiModel,
                      helperText: AppLocalizations.of(context).aiModelHelp,
                    ),
                  ),
                  if (_provider.models.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 6,
                        children: [
                          for (final model in _provider.models)
                            ActionChip(
                              label: Text(model,
                                  style: const TextStyle(fontSize: 11)),
                              onPressed: () =>
                                  setState(() => _model.text = model),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _baseUrl,
                    decoration: InputDecoration(
                      labelText:
                          AppLocalizations.of(context).aiServerAddress,
                      hintText: _provider.baseUrl.isEmpty
                          ? 'http://192.168.1.20:11434/v1'
                          : _provider.baseUrl,
                      helperText: 'Set it for a self-hosted or proxied '
                          'endpoint',
                      helperMaxLines: 2,
                    ),
                  ),
                ],
              ),
            ),
            LiquidGlass(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _system,
                    minLines: 3,
                    maxLines: 8,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context).aiInstructions,
                      hintText: 'How should this agent behave?',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(AppLocalizations.of(context).aiCreativity),
                      Expanded(
                        child: Slider(
                          value: _temperature,
                          max: 1.0,
                          divisions: 10,
                          label: _temperature.toStringAsFixed(1),
                          onChanged: (value) =>
                              setState(() => _temperature = value),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            LiquidGlass(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(AppLocalizations.of(context).aiToolsAllowed,
                        style:
                            const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  if (servers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(4),
                      child: Text(
                        'No MCP servers configured yet — add one in AI '
                        'settings to give this agent skills.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  for (final server in servers)
                    CheckboxListTile(
                      dense: true,
                      value: _servers.contains(server.id),
                      title: Text(server.name),
                      subtitle: Text(server.url,
                          style: const TextStyle(fontSize: 11)),
                      onChanged: (checked) => setState(() {
                        if (checked == true) {
                          _servers.add(server.id);
                        } else {
                          _servers.remove(server.id);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
