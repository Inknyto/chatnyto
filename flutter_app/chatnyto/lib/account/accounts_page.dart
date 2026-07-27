import 'package:flutter/material.dart';

import '../core/brokers/broker_service.dart';
import '../core/crypto/crypto_service.dart';
import '../core/crypto/password_vault.dart';
import '../core/widgets/liquid_glass.dart';
import '../revamp/chat_service.dart';
import '../revamp/home_shell.dart';
import '../revamp/onboarding.dart';
import 'recovery_pages.dart';
import 'share_pages.dart';

/// Every identity this device holds, and the way between them.
///
/// An account is its key pair, not a row in a database somewhere: the same
/// account can sit on several devices at once, and one person can keep
/// several apart — a personal identity and a work one — without either
/// knowing about the other. Each keeps its own chats, contacts and picture,
/// because each is encrypted under its own key.
class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  final IdentityService _identity = IdentityService.instance;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _identity.exists().then((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  // -------------------------------------------------------------- actions

  /// Switches identity: everything held for the old one is dropped, and the
  /// new one is unlocked before anything is shown.
  Future<void> _switchTo(StoredAccount account) async {
    if (account.id == _identity.activeAccountId && _identity.isUnlocked) {
      return;
    }
    final password = await _askPassword(
      title: 'Open ${account.name}',
      message: 'Enter this account\'s password.',
    );
    if (password == null) return;

    final ok = await _identity.unlock(password, accountId: account.id);
    if (!mounted) return;
    if (!ok) {
      _say('Wrong password for ${account.name}.');
      return;
    }

    // The previous account's chats are not merely hidden — they are
    // encrypted under a key this account does not have. Dropping them keeps
    // the UI honest about that.
    ChatService.instance.reset();
    await PasswordVault.instance.remember(password);
    await startRevampServices();
    await BrokerService.instance.advertiseEverywhere();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      GlassPageRoute(page: const HomeShell()),
      (route) => false,
    );
  }

  Future<void> _addAccount() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => LiquidGlass(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add_alt_rounded),
              title: const Text('Create a new identity'),
              subtitle: const Text(
                  'A separate name and key pair, with its own chats.'),
              onTap: () => Navigator.pop(sheetContext, 'new'),
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner_rounded),
              title: const Text('Open an account from another device'),
              subtitle: const Text(
                  'Scan the transfer code shown on the other device.'),
              onTap: () => Navigator.pop(sheetContext, 'scan'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'new') {
      await Navigator.push(
        context,
        GlassPageRoute(page: const NewIdentityPage()),
      );
      if (mounted) setState(() {});
      return;
    }
    final result = await Navigator.push<(ScanOutcome, String)?>(
      context,
      GlassPageRoute(page: const ContactScanPage()),
    );
    if (!mounted || result == null) return;
    setState(() {});
    _say(result.$1 == ScanOutcome.account
        ? '${result.$2} is now on this device. Open it with its password.'
        : 'Saved ${result.$2} as a contact.');
  }

  Future<void> _transfer(StoredAccount account) async {
    final blob = _identity.exportAccount(account.id);
    if (blob == null) {
      _say('This account cannot be transferred until it has been opened '
          'once on this device.');
      return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      GlassPageRoute(
        page: AccountTransferPage(blob: blob, name: account.name),
      ),
    );
  }

  Future<void> _showRecoveryCode(StoredAccount account) async {
    if (account.id != _identity.activeAccountId || !_identity.isUnlocked) {
      _say('Open this account first to issue a recovery code for it.');
      return;
    }
    final code = await _identity.regenerateRecoveryCode();
    if (code == null || !mounted) return;
    await Navigator.push(
      context,
      GlassPageRoute(page: RecoveryCodePage(code: code, isNew: false)),
    );
    if (mounted) setState(() {});
  }

  Future<void> _rename(StoredAccount account) async {
    final controller = TextEditingController(text: account.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename this identity'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Display name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await _identity.renameAccount(account.id, name);
    if (account.id == _identity.activeAccountId) {
      await BrokerService.instance.advertiseEverywhere();
    }
    if (mounted) setState(() {});
  }

  Future<void> _delete(StoredAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${account.name}?'),
        content: const Text(
          'Its chats and keys are erased from this device. Unless you have '
          'the transfer code or another device holding the same account, it '
          'is gone for good.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _identity.deleteAccount(account.id);
    if (mounted) setState(() {});
  }

  Future<String?> _askPassword({
    required String title,
    required String message,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Password'),
              onSubmitted: (value) => Navigator.pop(dialogContext, value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }

  void _say(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final accounts = _identity.accounts;
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Accounts'),
          actions: [
            IconButton(
              tooltip: 'My contact code',
              icon: const Icon(Icons.qr_code_2_rounded),
              onPressed: _identity.isUnlocked
                  ? () => Navigator.push(
                        context,
                        GlassPageRoute(page: const MyContactPage()),
                      )
                  : null,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addAccount,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final account in accounts)
                    _AccountTile(
                      account: account,
                      active: account.id == _identity.activeAccountId,
                      unlocked: account.id == _identity.activeAccountId &&
                          _identity.isUnlocked,
                      onOpen: () => _switchTo(account),
                      onRename: () => _rename(account),
                      onTransfer: () => _transfer(account),
                      onRecovery: () => _showRecoveryCode(account),
                      onForgotPassword: () async {
                        final done = await Navigator.push<bool>(
                          context,
                          GlassPageRoute(
                            page: RecoverAccountPage(accountId: account.id),
                          ),
                        );
                        if (done == true && mounted) setState(() {});
                      },
                      onDelete:
                          accounts.length > 1 ? () => _delete(account) : null,
                    ),
                  const SizedBox(height: 12),
                  LiquidGlass(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: const ListTile(
                      leading: Icon(Icons.info_outline_rounded),
                      title: Text('One key, many devices',
                          style: TextStyle(fontSize: 14)),
                      subtitle: Text(
                        'An account is its key pair. Transfer it to another '
                        'device and both hold the same identity — the same '
                        'name, the same key, and messages that verify as '
                        'yours either way.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.account,
    required this.active,
    required this.unlocked,
    required this.onOpen,
    required this.onRename,
    required this.onTransfer,
    required this.onRecovery,
    required this.onForgotPassword,
    this.onDelete,
  });

  final StoredAccount account;
  final bool active;
  final bool unlocked;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onTransfer;
  final VoidCallback onRecovery;
  final VoidCallback onForgotPassword;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LiquidGlass(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          ListTile(
            onTap: active && unlocked ? null : onOpen,
            leading: CircleAvatar(
              backgroundColor:
                  active ? scheme.primary : scheme.surfaceContainerHighest,
              foregroundColor:
                  active ? scheme.onPrimary : scheme.onSurface,
              child: Text(
                account.name.isEmpty ? '?' : account.name[0].toUpperCase(),
              ),
            ),
            title: Text(account.name),
            subtitle: Text(
              account.keysKnown
                  ? account.fingerprint
                  : 'Not opened on this device yet',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
            trailing: active
                ? Icon(
                    unlocked
                        ? Icons.check_circle_rounded
                        : Icons.lock_outline_rounded,
                    color: unlocked ? Colors.greenAccent : null,
                  )
                : const Icon(Icons.login_rounded),
          ),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onRename, child: const Text('Rename')),
              TextButton(
                  onPressed: onTransfer, child: const Text('Transfer')),
              TextButton(
                onPressed: unlocked ? onRecovery : onForgotPassword,
                child: Text(unlocked ? 'Recovery code' : 'Forgot password'),
              ),
              if (onDelete != null)
                TextButton(
                  onPressed: onDelete,
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.redAccent),
                  child: const Text('Remove'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Creates an extra identity alongside the ones already on the device.
class NewIdentityPage extends StatefulWidget {
  const NewIdentityPage({super.key});

  @override
  State<NewIdentityPage> createState() => _NewIdentityPageState();
}

class _NewIdentityPageState extends State<NewIdentityPage> {
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Choose a name.');
      return;
    }
    if (_passwordController.text.length < 8) {
      setState(() => _error = 'Use at least 8 characters.');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    await IdentityService.instance.create(name, _passwordController.text);
    final code = IdentityService.instance.pendingRecoveryCode;
    ChatService.instance.reset();
    await PasswordVault.instance.remember(_passwordController.text);
    await startRevampServices();
    if (!mounted) return;
    if (code != null) {
      IdentityService.instance.pendingRecoveryCode = null;
      await Navigator.push(
        context,
        GlassPageRoute(page: RecoveryCodePage(code: code)),
      );
    }
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      GlassPageRoute(page: const HomeShell()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('New identity')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'A second identity has its own key, its own chats and its '
                'own contacts. Nobody can tell from the outside that the two '
                'belong to the same person.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 20),
              LiquidGlass(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _nameController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                        helperText: 'What people on the network see.',
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        helperText: 'At least 8 characters.',
                      ),
                      onSubmitted: (_) => _create(),
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                onPressed: _working ? null : _create,
                child: _working
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create identity'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
