import 'package:flutter/material.dart';

import '../account/share_pages.dart';
import '../core/brokers/broker_service.dart';
import '../core/crypto/contact_book.dart';
import '../core/crypto/crypto_service.dart';
import '../core/widgets/liquid_glass.dart';
import '../core/widgets/person_avatar.dart';
import '../core/widgets/wa_components.dart';
import '../revamp/chat_page.dart';
import '../revamp/chat_service.dart';

/// The people this device knows, and everything you can do about that.
///
/// The People tab answers "who is around?" — it is mostly other people's
/// doing, and it changes as they come and go. This page answers "who have I
/// kept?", which is entirely yours: a fixed list you added to deliberately,
/// can rename, and can remove from. Keeping the two apart means neither has
/// to pretend to be the other.
class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  final ContactBook _contacts = ContactBook.instance;
  final BrokerService _brokers = BrokerService.instance;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _contacts.load();
    _contacts.addListener(_onChanged);
    _brokers.addListener(_onChanged);
  }

  @override
  void dispose() {
    _contacts.removeListener(_onChanged);
    _brokers.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _add() async {
    final result = await Navigator.push<(ScanOutcome, String)?>(
      context,
      GlassPageRoute(page: const ContactScanPage()),
    );
    if (!mounted || result == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved ${result.$2}.')),
    );
  }

  Future<void> _rename(PublicIdentity person) async {
    final controller = TextEditingController(
        text: _contacts.hasAlias(person.x25519PublicKey)
            ? _contacts.displayName(person)
            : '');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Rename ${person.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Your name for them',
            helperText: 'Leave empty to use ${person.name} again.',
            helperMaxLines: 2,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null) return;
    await _contacts.setAlias(person.x25519PublicKey, name);
  }

  Future<void> _forget(PublicIdentity person) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Forget ${_contacts.displayName(person)}?'),
        content: const Text(
          'Their key is removed from this device. Your conversation stays; '
          'you will only be able to reach them again while they are on a '
          'network you share, or once they hand over their code again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _contacts.remove(person.x25519PublicKey);
  }

  Future<void> _message(PublicIdentity person) async {
    final chat = await ChatService.instance.startDm(person);
    if (!mounted) return;
    Navigator.push(context, GlassPageRoute(page: RevampChatPage(chat: chat)));
  }

  void _options(PublicIdentity person, bool saved) {
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
                name: _contacts.displayName(person),
                avatar: person.avatar,
                radius: 20,
              ),
              title: Text(_contacts.displayName(person)),
              subtitle: Text(
                person.fingerprint,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.message_rounded),
              title: const Text('Message'),
              onTap: () {
                Navigator.pop(sheetContext);
                _message(person);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: const Text('Rename'),
              subtitle: const Text('Only on this device'),
              onTap: () {
                Navigator.pop(sheetContext);
                _rename(person);
              },
            ),
            if (saved)
              ListTile(
                leading: const Icon(Icons.person_remove_rounded,
                    color: Colors.redAccent),
                title: const Text('Forget this contact'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _forget(person);
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.person_add_alt_rounded),
                title: const Text('Save as contact'),
                subtitle: const Text(
                    'Keeps their key, so they stay reachable when they go '
                    'off the network'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _contacts.add(person);
                },
              ),
          ],
        ),
      ),
    );
  }

  bool _matches(PublicIdentity person) =>
      _query.isEmpty ||
      _contacts.displayName(person).toLowerCase().contains(
            _query.toLowerCase(),
          ) ||
      person.fingerprint.contains(_query.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final saved = _contacts.contacts.where(_matches).toList();
    final onAir = _contacts.contacts.map((c) => c.x25519PublicKey).toSet();
    // People announcing themselves who are not in the book yet — the ones
    // worth offering to keep.
    final strangers =
        _brokers.peers.where((p) => !onAir.contains(p.x25519PublicKey))
            .where(_matches)
            .toList();
    final live = _brokers.peers.map((p) => p.x25519PublicKey).toSet();

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Contacts'),
          actions: [
            IconButton(
              tooltip: 'Add by code',
              icon: const Icon(Icons.qr_code_scanner_rounded),
              onPressed: _add,
            ),
            IconButton(
              tooltip: 'My contact code',
              icon: const Icon(Icons.qr_code_2_rounded),
              onPressed: () => Navigator.push(
                context,
                GlassPageRoute(page: const MyContactPage()),
              ),
            ),
          ],
        ),
        body: ListView(
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
                  hintText: 'Search contacts',
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            if (saved.isEmpty)
              const LiquidGlass(
                margin: EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  leading: Icon(Icons.person_add_alt_rounded),
                  title: Text('No contacts kept yet'),
                  subtitle: Text(
                      'Scan someone\'s code, or save one of the people below '
                      'so you can still reach them once they go offline.'),
                ),
              ),
            for (final person in saved)
              WaChatTile(
                title: _contacts.displayName(person),
                avatar: person.avatar,
                subtitle: live.contains(person.x25519PublicKey)
                    ? 'On the network now · ${person.fingerprint}'
                    : 'Saved · ${person.fingerprint}',
                onTap: () => _message(person),
                onLongPress: () => _options(person, true),
              ),
            if (strangers.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 20, 8, 4),
                child: Text(
                  'On the network, not kept',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              for (final person in strangers)
                WaChatTile(
                  title: person.name,
                  avatar: person.avatar,
                  subtitle: 'Tap and hold to keep · ${person.fingerprint}',
                  onTap: () => _message(person),
                  onLongPress: () => _options(person, false),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
