import 'package:flutter/material.dart';

import '../account/account_page.dart';
import '../account/security_page.dart';
import '../ais/ais_page.dart';
import '../core/brokers/broker_service.dart';
import '../core/brokers/brokers_page.dart';
import '../core/crypto/crypto_service.dart';
import '../core/theme/theme_controller.dart';
import '../core/widgets/liquid_glass.dart';
import '../core/widgets/wa_components.dart';
import '../humans/humans_page.dart';
import '../robots/robots_page.dart';
import 'chat_page.dart';
import 'chat_service.dart';

/// WhatsApp-style home: chats first, people discovery, updates and the
/// communities (the classic humans/robots/AIs sections).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  static const _titles = ['ChatNyto', 'People', 'Updates', 'Communities'];

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            _titles[_tab],
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              tooltip: 'Toggle dark/light mode',
              icon: Icon(
                Theme.of(context).brightness == Brightness.dark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
              ),
              onPressed: ThemeController.instance.toggle,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (choice) {
                final page = switch (choice) {
                  'settings' => const AccountPage(),
                  'security' => const SecurityPage(),
                  'brokers' => const BrokersPage(),
                  _ => null,
                };
                if (page != null) {
                  Navigator.push(context, GlassPageRoute(page: page));
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'settings', child: Text('Settings')),
                PopupMenuItem(
                    value: 'security', child: Text('Security & identity')),
                PopupMenuItem(
                    value: 'brokers', child: Text('Networks (advanced)')),
              ],
            ),
          ],
        ),
        body: IndexedStack(
          index: _tab,
          children: const [
            ChatsTab(),
            PeopleTab(),
            UpdatesTab(),
            CommunitiesTab(),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _tab,
          onTap: (index) => setState(() => _tab = index),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.message_outlined),
              activeIcon: Icon(Icons.message_rounded),
              label: 'Chats',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_alt_outlined),
              activeIcon: Icon(Icons.people_alt_rounded),
              label: 'People',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.notifications_outlined),
              activeIcon: Icon(Icons.notifications_rounded),
              label: 'Updates',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.groups_outlined),
              activeIcon: Icon(Icons.groups_rounded),
              label: 'Communities',
            ),
          ],
        ),
      ),
    );
  }
}

/// Default tab: the chat list.
class ChatsTab extends StatefulWidget {
  const ChatsTab({super.key});

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  final ChatService _service = ChatService.instance;

  @override
  void initState() {
    super.initState();
    _service.init();
    _service.addListener(_onChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _newGroup() async {
    final nameController = TextEditingController();
    final secretController = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Group name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: secretController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Passphrase (optional)',
                helperText: 'Only people with the passphrase can read',
              ),
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
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (created == true && nameController.text.trim().isNotEmpty) {
      final chat = await _service.createGroup(
        nameController.text,
        secret: secretController.text,
      );
      if (mounted) {
        Navigator.push(
            context, GlassPageRoute(page: RevampChatPage(chat: chat)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final chats = _service.chats;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: chats.isEmpty
          ? const Center(
              child: LiquidGlass(
                margin: EdgeInsets.all(24),
                padding: EdgeInsets.all(20),
                child: Text(
                  'No chats yet.\n\nFind someone in the People tab, or '
                  'create a group with the button below.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: chats.length,
              itemBuilder: (context, index) {
                final chat = chats[index];
                final time = chat.lastTs == 0
                    ? ''
                    : RevampMessage(
                        from: '', name: '', text: '', ts: chat.lastTs)
                        .timeLabel;
                return WaChatTile(
                  title: chat.title,
                  subtitle: chat.lastMessage.isEmpty
                      ? (chat.isDm
                          ? 'Say hello 👋'
                          : 'Group · anyone with the name can join')
                      : chat.lastMessage,
                  timeStamp: time,
                  unreadCount: chat.unread,
                  leadingIcon: chat.isDm ? null : Icons.groups_rounded,
                  onTap: () => Navigator.push(
                    context,
                    GlassPageRoute(page: RevampChatPage(chat: chat)),
                  ),
                  onLongPress: () async {
                    final remove = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('Delete "${chat.title}"?'),
                        content: const Text(
                            'Removes the chat and its messages on this '
                            'device.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: Colors.red),
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (remove == true) _service.removeChat(chat);
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _newGroup,
        tooltip: 'New group',
        child: const Icon(Icons.group_add_rounded),
      ),
    );
  }
}

/// People discovered across all connected brokers, with identity
/// verification and one-tap messaging.
class PeopleTab extends StatefulWidget {
  const PeopleTab({super.key});

  @override
  State<PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends State<PeopleTab> {
  final BrokerService _brokers = BrokerService.instance;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _brokers.addListener(_onChanged);
  }

  @override
  void dispose() {
    _brokers.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<String> _myFingerprint() async {
    if (!IdentityService.instance.isUnlocked) return '';
    return (await IdentityService.instance.publicIdentity()).fingerprint;
  }

  void _showIdentity(PublicIdentity peer) {
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
              child: Text(
                peer.name.isEmpty ? '?' : peer.name[0].toUpperCase(),
                style: const TextStyle(fontSize: 28),
              ),
            ),
            const SizedBox(height: 12),
            Text(peer.name,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified_rounded,
                    color: Colors.greenAccent, size: 18),
                const SizedBox(width: 6),
                Text('Verified key · ${peer.fingerprint}',
                    style: const TextStyle(fontSize: 13)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'The signature of this identity was checked against its '
              'public key. Compare the fingerprint with your contact '
              'through another channel for full certainty.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color:
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.message_rounded),
              label: const Text('Message'),
              onPressed: () async {
                final chat = await ChatService.instance.startDm(peer);
                if (context.mounted) {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    GlassPageRoute(page: RevampChatPage(chat: chat)),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _myFingerprint(),
      builder: (context, snapshot) {
        final myFp = snapshot.data ?? '';
        final peers = _brokers.peers
            .where((p) => p.fingerprint != myFp)
            .where((p) =>
                _query.isEmpty ||
                p.name.toLowerCase().contains(_query.toLowerCase()))
            .toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        final connected =
            _brokers.brokers.where(_brokers.isConnected).length;
        return ListView(
          padding: const EdgeInsets.all(8),
          children: [
            LiquidGlass(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              radius: 24,
              child: TextField(
                decoration: const InputDecoration(
                  icon: Icon(Icons.search_rounded),
                  border: InputBorder.none,
                  hintText: 'Search people by name',
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            LiquidGlass(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: Icon(
                  connected > 0
                      ? Icons.wifi_tethering_rounded
                      : Icons.wifi_tethering_off_rounded,
                  color: connected > 0 ? Colors.greenAccent : null,
                ),
                title: Text(connected > 0
                    ? 'Connected — people appear automatically'
                    : 'Searching for a network…'),
                subtitle: Text(connected > 0
                    ? '$connected network(s) reachable'
                    : 'Turn on the LoRa box or join the same WiFi, then '
                        'people around you show up here.'),
                trailing: IconButton(
                  tooltip: 'Retry connections',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () async {
                    await _brokers.autoConnectAll();
                    await _brokers.advertiseEverywhere();
                  },
                ),
              ),
            ),
            for (final peer in peers)
              WaChatTile(
                title: peer.name,
                subtitle: 'Verified · ${peer.fingerprint}',
                leadingIcon: null,
                onTap: () => _showIdentity(peer),
              ),
            if (peers.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: GlassShimmer(count: 3),
              ),
          ],
        );
      },
    );
  }
}

/// Presence updates feed (who appeared on the network) — the social pulse.
class UpdatesTab extends StatefulWidget {
  const UpdatesTab({super.key});

  @override
  State<UpdatesTab> createState() => _UpdatesTabState();
}

class _UpdatesTabState extends State<UpdatesTab> {
  final BrokerService _brokers = BrokerService.instance;

  @override
  void initState() {
    super.initState();
    _brokers.addListener(_onChanged);
  }

  @override
  void dispose() {
    _brokers.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final peers = _brokers.peers;
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Text('Online now',
              style:
                  TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        SizedBox(
          height: 92,
          child: peers.isEmpty
              ? const Center(child: Text('Nobody on the network yet'))
              : ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    for (final peer in peers)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Column(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color:
                                      Theme.of(context).colorScheme.primary,
                                  width: 2,
                                ),
                              ),
                              padding: const EdgeInsets.all(3),
                              child: CircleAvatar(
                                radius: 26,
                                child: Text(peer.name.isEmpty
                                    ? '?'
                                    : peer.name[0].toUpperCase()),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(peer.name,
                                style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        const Divider(),
        const Padding(
          padding: EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Text('Networks',
              style:
                  TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        for (final broker in _brokers.brokers)
          LiquidGlass(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: Icon(
                _brokers.isConnected(broker)
                    ? Icons.cloud_done_rounded
                    : Icons.cloud_off_rounded,
                color:
                    _brokers.isConnected(broker) ? Colors.greenAccent : null,
              ),
              title: Text(broker.name),
              subtitle: Text(
                  _brokers.isConnected(broker) ? 'Connected' : 'Unreachable'),
            ),
          ),
      ],
    );
  }
}

/// The classic ChatNyto sections, presented as communities.
class CommunitiesTab extends StatelessWidget {
  const CommunitiesTab({super.key});

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData icon, String title, String subtitle, Widget page) {
      return LiquidGlass(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: ListTile(
          leading: Icon(icon, size: 32),
          title: Text(title,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () =>
              Navigator.push(context, GlassPageRoute(page: page)),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        tile(
          Icons.people_alt_rounded,
          'Humans',
          'Classic rooms with rich-text messages',
          const HumansPage(),
        ),
        tile(
          Icons.smart_toy_rounded,
          'Robots',
          'Talk to your connected devices',
          const RobotsPage(),
        ),
        tile(
          Icons.auto_awesome_rounded,
          'AIs',
          'Local and cloud AI assistants',
          const AIsPage(),
        ),
      ],
    );
  }
}
