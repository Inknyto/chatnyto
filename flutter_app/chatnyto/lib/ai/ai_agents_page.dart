import 'package:flutter/material.dart';

import '../core/widgets/liquid_glass.dart';
import '../core/widgets/wa_components.dart';
import '../l10n/app_localizations.dart';
import 'ai_agent.dart';
import 'ai_chat_page.dart';
import 'ai_provider.dart';
import 'ai_settings_page.dart';

/// The AI side of ChatNyto: your agents, each one a provider + model +
/// instructions, optionally allowed to use tools from MCP servers.
class AiAgentsPage extends StatefulWidget {
  const AiAgentsPage({super.key});

  @override
  State<AiAgentsPage> createState() => _AiAgentsPageState();
}

class _AiAgentsPageState extends State<AiAgentsPage> {
  final AiConfig _config = AiConfig.instance;

  @override
  void initState() {
    super.initState();
    _config.load();
    _config.addListener(_onChanged);
  }

  @override
  void dispose() {
    _config.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _newAgent() async {
    final agent = AiAgent(
      id: AiConfig.newId(),
      name: '',
      providerId: AiProvider.anthropic.id,
      model: AiProvider.anthropic.models.first,
    );
    await Navigator.push(
      context,
      GlassPageRoute(page: AiAgentEditPage(agent: agent, isNew: true)),
    );
  }

  void _options(AiAgent agent) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => LiquidGlass(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.tune_rounded),
              title: Text(AppLocalizations.of(context).aiEditAgent),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  GlassPageRoute(page: AiAgentEditPage(agent: agent)),
                );
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_rounded, color: Colors.redAccent),
              title: Text(AppLocalizations.of(context).aiDeleteAgent),
              onTap: () {
                Navigator.pop(sheetContext);
                _config.removeAgent(agent);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final agents = _config.agents;
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(l10n.aiAgents),
          actions: [
            IconButton(
              tooltip: l10n.aiProvidersAndTools,
              icon: const Icon(Icons.settings_rounded),
              onPressed: () => Navigator.push(
                context,
                GlassPageRoute(page: const AiSettingsPage()),
              ),
            ),
          ],
        ),
        body: agents.isEmpty
            ? Center(
                child: LiquidGlass(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome_rounded, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        l10n.aiNoAgents,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.aiNoAgentsHelp,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _newAgent,
                        icon: const Icon(Icons.add_rounded),
                        label: Text(l10n.aiAddAgent),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: agents.length,
                itemBuilder: (context, index) {
                  final agent = agents[index];
                  final toolCount = _config.serversFor(agent).length;
                  return WaChatTile(
                    title: agent.name,
                    leadingIcon: Icons.auto_awesome_rounded,
                    subtitle: '${agent.provider.name} · ${agent.model}'
                        '${toolCount > 0 ? ' · $toolCount tool server(s)' : ''}',
                    onTap: () => Navigator.push(
                      context,
                      GlassPageRoute(page: AiChatPage(agent: agent)),
                    ),
                    onLongPress: () => _options(agent),
                  );
                },
              ),
        floatingActionButton: agents.isEmpty
            ? null
            : FloatingActionButton(
                onPressed: _newAgent,
                tooltip: l10n.aiAddAgent,
                child: const Icon(Icons.add_rounded),
              ),
      ),
    );
  }
}
