// ~/Documents/git/chatnyto/flutter_app/chatnyto/lib/revamp/home_shell.dart 26 Jul 2026 at 02:33:16 PM
import 'package:flutter/material.dart';

import '../account/account_page.dart';
import '../account/security_page.dart';
import '../ai/ai_agents_page.dart';
import '../ais/ais_page.dart';
import '../calls/calls_tab.dart';
import '../core/brokers/broker_service.dart';
import '../core/brokers/brokers_page.dart';
import '../account/share_pages.dart';
import '../core/crypto/contact_book.dart';
import '../core/crypto/crypto_service.dart';
import '../core/settings/wallpaper_picker.dart';
import '../core/theme/theme_controller.dart';
import '../core/widgets/connection_status.dart';
import '../core/widgets/liquid_glass.dart';
import '../core/widgets/person_avatar.dart';
import '../core/widgets/wa_components.dart';
import '../humans/contacts_page.dart';
import '../humans/humans_page.dart';
import '../l10n/app_localizations.dart';
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final titles = [
      l10n.appTitle,
      l10n.tabCalls,
      l10n.tabPeople,
      l10n.tabUpdates,
      l10n.tabCommunities,
    ];
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            titles[_tab],
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            const ConnectionStatusChip(compact: true),
            IconButton(
              tooltip: l10n.toggleTheme,
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
                  'contacts' => const ContactsPage(),
                  'settings' => const AccountPage(),
                  'security' => const SecurityPage(),
                  'brokers' => const BrokersPage(),
                  _ => null,
                };
                if (page != null) {
                  Navigator.push(context, GlassPageRoute(page: page));
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                    value: 'contacts', child: Text('Contacts')),
                PopupMenuItem(
                    value: 'settings', child: Text(l10n.menuSettings)),
                PopupMenuItem(
                    value: 'security', child: Text(l10n.menuSecurity)),
                PopupMenuItem(
                    value: 'brokers', child: Text(l10n.menuNetworks)),
              ],
            ),
          ],
        ),
        body: IndexedStack(
          index: _tab,
          children: const [
            ChatsTab(),
            CallsTab(),
            PeopleTab(),
            UpdatesTab(),
            CommunitiesTab(),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _tab,
          onTap: (index) => setState(() => _tab = index),
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.message_outlined),
              activeIcon: const Icon(Icons.message_rounded),
              label: l10n.tabChats,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.call_outlined),
              activeIcon: const Icon(Icons.call_rounded),
              label: l10n.tabCalls,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.people_alt_outlined),
              activeIcon: const Icon(Icons.people_alt_rounded),
              label: l10n.tabPeople,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.notifications_outlined),
              activeIcon: const Icon(Icons.notifications_rounded),
              label: l10n.tabUpdates,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.groups_outlined),
              activeIcon: const Icon(Icons.groups_rounded),
              label: l10n.tabCommunities,
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
    final l10n = AppLocalizations.of(context);
    final nameController = TextEditingController();
    final secretController = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.newGroup),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: InputDecoration(labelText: l10n.groupName),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: secretController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.groupPassphrase,
                helperText: l10n.groupPassphraseHelp,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.create),
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

  /// Long-press edit mode: rename, per-chat wallpaper, delete. Renaming a
  /// group and deleting it for everyone are reserved to its creator.
  Future<void> _showChatOptions(ChatEntry chat) async {
    final isOwner = await _service.canAdministerGroup(chat);
    final canRename = chat.isDm || isOwner;
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => LiquidGlass(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canRename)
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: Text(chat.isDm ? l10n.rename : l10n.renameGroup),
                subtitle:
                    chat.isDm ? null : Text(l10n.renameGroupHelp),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final controller =
                      TextEditingController(text: chat.title);
                  final saved = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(
                          chat.isDm ? l10n.renameChat : l10n.renameGroup),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                              controller: controller, autofocus: true),
                          if (!chat.isDm) ...[
                            const SizedBox(height: 8),
                            Text(
                              l10n.renameGroupHelp,
                              style: const TextStyle(fontSize: 12),
                            ),
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
                  if (saved != true) return;
                  final error =
                      await _service.renameChat(chat, controller.text);
                  if (error != null && mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(error)));
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.wallpaper_rounded),
              title: Text(l10n.wallpaperForChat),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  GlassPageRoute(
                      page: WallpaperPickerPage(chatId: chat.id)),
                );
              },
            ),
            if (isOwner)
              ListTile(
                leading: const Icon(Icons.group_remove_rounded,
                    color: Colors.redAccent),
                title: Text(l10n.deleteGroupForEveryone),
                subtitle: const Text('You administer this group'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final remove = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text('Delete "${chat.title}" for everyone?'),
                      content: const Text(
                          'The group disappears for everyone who joined it.'),
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
                  if (remove != true) return;
                  final error =
                      await _service.deleteGroupForEveryone(chat);
                  if (error != null && mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(error)));
                  }
                },
              ),
            ListTile(
              leading:
                  const Icon(Icons.delete_rounded, color: Colors.redAccent),
              title: Text(chat.isDm ? l10n.deleteChat : l10n.leaveGroup),
              onTap: () async {
                Navigator.pop(sheetContext);
                final remove = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(chat.isDm
                        ? 'Delete "${chat.title}"?'
                        : 'Leave "${chat.title}"?'),
                    content: Text(l10n.deleteLocalWarning),
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
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chats = _service.chats;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: chats.isEmpty
          ? Center(
              child: LiquidGlass(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(20),
                child: Text(
                  AppLocalizations.of(context).chatsEmpty,
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
                  avatar: chat.peerIdentity?.avatar,
                  subtitle: chat.lastMessage.isEmpty
                      ? (chat.isDm
                          ? AppLocalizations.of(context).sayHello
                          : AppLocalizations.of(context).groupSubtitle)
                      : chat.lastMessage,
                  timeStamp: time,
                  unreadCount: chat.unread,
                  lastStatus: chat.isDm ? chat.lastStatus : null,
                  leadingIcon: chat.isDm ? null : Icons.groups_rounded,
                  onTap: () => Navigator.push(
                    context,
                    GlassPageRoute(page: RevampChatPage(chat: chat)),
                  ),
                  onLongPress: () => _showChatOptions(chat),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _newGroup,
        tooltip: AppLocalizations.of(context).newGroup,
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
  final ContactBook _contacts = ContactBook.instance;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _brokers.addListener(_onChanged);
    _contacts.addListener(_onChanged);
    _contacts.load();
  }

  @override
  void dispose() {
    _brokers.removeListener(_onChanged);
    _contacts.removeListener(_onChanged);
    super.dispose();
  }

  /// Adds someone from their contact code. It is the answer to the awkward
  /// case the network cannot solve: reaching a person who is not currently
  /// on the air.
  Future<void> _scanContact() async {
    final result = await Navigator.push<(ScanOutcome, String)?>(
      context,
      GlassPageRoute(page: const ContactScanPage()),
    );
    if (!mounted || result == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result.$1 == ScanOutcome.contact
          ? 'Saved ${result.$2} as a contact.'
          : '${result.$2} is now on this device.'),
    ));
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<String> _myFingerprint() async {
    if (!IdentityService.instance.isUnlocked) return '';
    return (await IdentityService.instance.publicIdentity()).fingerprint;
  }

  /// What can be done with the person in this row: keep them, rename them,
  /// or stop keeping them.
  void _contactOptions(PublicIdentity peer) {
    final saved = _contacts.knows(peer.x25519PublicKey);
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
              leading: PersonAvatar(
                name: _contacts.displayName(peer),
                avatar: peer.avatar,
                radius: 20,
              ),
              title: Text(_contacts.displayName(peer)),
              subtitle: Text(
                peer.fingerprint,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.message_rounded),
              title: Text(AppLocalizations.of(context).message),
              onTap: () async {
                Navigator.pop(sheetContext);
                final chat = await ChatService.instance.startDm(peer);
                if (!mounted) return;
                Navigator.push(
                    context, GlassPageRoute(page: RevampChatPage(chat: chat)));
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: const Text('Rename'),
              subtitle: const Text('Only on this device'),
              onTap: () {
                Navigator.pop(sheetContext);
                _renameContact(peer);
              },
            ),
            ListTile(
              leading: Icon(
                saved
                    ? Icons.person_remove_rounded
                    : Icons.person_add_alt_rounded,
                color: saved ? Colors.redAccent : null,
              ),
              title: Text(saved ? 'Forget this contact' : 'Save as contact'),
              onTap: () async {
                Navigator.pop(sheetContext);
                if (saved) {
                  await _contacts.remove(peer.x25519PublicKey);
                } else {
                  await _contacts.add(peer);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.contacts_rounded),
              title: const Text('All contacts'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                    context, GlassPageRoute(page: const ContactsPage()));
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameContact(PublicIdentity peer) async {
    final controller = TextEditingController(
        text: _contacts.hasAlias(peer.x25519PublicKey)
            ? _contacts.displayName(peer)
            : '');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Rename ${peer.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Your name for them',
            helperText: 'Leave empty to use ${peer.name} again.',
            helperMaxLines: 2,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null) return;
    await _contacts.setAlias(peer.x25519PublicKey, name);
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
            PersonAvatar(name: peer.name, avatar: peer.avatar, radius: 36),
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
              label: Text(AppLocalizations.of(context).message),
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
            // Keeping someone means keeping their key, so they stay
            // reachable once they drop off the network.
            TextButton.icon(
              icon: Icon(
                _contacts.knows(peer.x25519PublicKey)
                    ? Icons.bookmark_remove_rounded
                    : Icons.bookmark_add_rounded,
                size: 18,
              ),
              label: Text(_contacts.knows(peer.x25519PublicKey)
                  ? 'Forget this contact'
                  : 'Save as contact'),
              onPressed: () async {
                if (_contacts.knows(peer.x25519PublicKey)) {
                  await _contacts.remove(peer.x25519PublicKey);
                } else {
                  await _contacts.add(peer);
                }
                if (context.mounted) Navigator.pop(context);
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
        // Saved contacts and whoever is announcing themselves right now,
        // each appearing once: the same person heard on the network and
        // scanned from a code is one entry, keyed by their public key.
        final live = _brokers.peers;
        final onAir =
            live.map((p) => p.x25519PublicKey).toSet();
        final peers = _contacts
            .merged(live)
            .where((p) => p.fingerprint != myFp)
            .where((p) =>
                _query.isEmpty ||
                p.name.toLowerCase().contains(_query.toLowerCase()))
            .toList();
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
                decoration: InputDecoration(
                  icon: const Icon(Icons.search_rounded),
                  border: InputBorder.none,
                  hintText: AppLocalizations.of(context).searchPeople,
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
                    ? AppLocalizations.of(context).connectedPeopleAppear
                    : AppLocalizations.of(context).searchingNetwork),
                subtitle: Text(connected > 0
                    ? AppLocalizations.of(context)
                        .networksReachable(connected)
                    : AppLocalizations.of(context).turnOnLoraHint),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Add someone by code',
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      onPressed: _scanContact,
                    ),
                    IconButton(
                      tooltip: 'Retry connections',
                      icon: const Icon(Icons.refresh_rounded),
                      onPressed: () async {
                        // The user asking is reason enough to ignore any
                        // backoff and try everything again now.
                        _brokers.retryNow();
                        await _brokers.autoConnectAll();
                        await _brokers.advertiseEverywhere();
                      },
                    ),
                  ],
                ),
              ),
            ),
            for (final peer in peers)
              WaChatTile(
                title: _contacts.displayName(peer),
                subtitle: onAir.contains(peer.x25519PublicKey)
                    ? AppLocalizations.of(context)
                        .verifiedKey(peer.fingerprint)
                    : 'Saved contact · ${peer.fingerprint}',
                leadingIcon: null,
                avatar: peer.avatar,
                onTap: () => _showIdentity(peer),
                // Same gesture as the chat list: hold for what you can do
                // with this row, rather than a menu hidden one level down.
                onLongPress: () => _contactOptions(peer),
              ),
            if (peers.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: GlassShimmer(count: 3),
              ),
            if (_brokers.publicGroups.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 20, 8, 4),
                child: Text(AppLocalizations.of(context).publicGroupsOnMesh,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              for (final group in _brokers.publicGroups
                  .where((g) =>
                      _query.isEmpty ||
                      g.name.toLowerCase().contains(_query.toLowerCase())))
                WaChatTile(
                  title: group.name,
                  subtitle:
                      AppLocalizations.of(context).publicGroupTapToJoin,
                  leadingIcon: Icons.groups_rounded,
                  onTap: () async {
                    final chat =
                        await ChatService.instance.joinPublicGroup(group);
                    if (context.mounted) {
                      Navigator.push(
                        context,
                        GlassPageRoute(page: RevampChatPage(chat: chat)),
                      );
                    }
                  },
                ),
            ],
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
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Text(AppLocalizations.of(context).onlineNow,
              style:
                  TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        SizedBox(
          height: 92,
          child: peers.isEmpty
              ? Center(
                  child: Text(AppLocalizations.of(context).nobodyYet))
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
                              // The tap belongs to the tile, which opens the
                              // person's details — where the picture can be
                              // opened properly.
                              child: PersonAvatar(
                                name: peer.name,
                                avatar: peer.avatar,
                                radius: 26,
                                viewable: false,
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
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Text(AppLocalizations.of(context).networks,
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
                  _brokers.isConnected(broker)
                      ? AppLocalizations.of(context).connected
                      : AppLocalizations.of(context).unreachable),
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
          AppLocalizations.of(context).communityPeople,
          AppLocalizations.of(context).communityPeopleSub,
          const HumansPage(),
        ),
        tile(
          Icons.devices_other_rounded,
          AppLocalizations.of(context).communityIot,
          AppLocalizations.of(context).communityIotSub,
          const RobotsPage(),
        ),
        tile(
          Icons.auto_awesome_rounded,
          AppLocalizations.of(context).communityAi,
          AppLocalizations.of(context).communityAiSub,
          const AiAgentsPage(),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 18, 16, 6),
          child: Text('Classic rooms',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        tile(
          Icons.forum_outlined,
          'MQTT rooms (old app)',
          'The original broker/topic screens',
          const AIsPage(),
        ),
      ],
    );
  }
}
