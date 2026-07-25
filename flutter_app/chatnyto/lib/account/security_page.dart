import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/brokers/broker_service.dart';
import '../core/crypto/crypto_service.dart';
import '../core/widgets/liquid_glass.dart';

/// Identity management: create the key pair, unlock it with the password,
/// and share the public key with the network.
class SecurityPage extends StatefulWidget {
  const SecurityPage({super.key});

  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  final IdentityService _identity = IdentityService.instance;
  bool? _exists;
  PublicIdentity? _public;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final exists = await _identity.exists();
    PublicIdentity? public;
    if (_identity.isUnlocked) {
      public = await _identity.publicIdentity();
    }
    if (mounted) {
      setState(() {
        _exists = exists;
        _public = public;
      });
    }
  }

  Future<void> _create() async {
    final nameController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create identity'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Display name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                helperText: 'Encrypts your private key on this device',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: confirmController,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Confirm password'),
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
    if (ok != true) return;
    final name = nameController.text.trim();
    final password = passwordController.text;
    if (name.isEmpty || password.length < 8) {
      _snack('Name required and password must be at least 8 characters.');
      return;
    }
    if (password != confirmController.text) {
      _snack('Passwords do not match.');
      return;
    }
    setState(() => _working = true);
    await _identity.create(name, password);
    await BrokerService.instance.advertiseEverywhere();
    setState(() => _working = false);
    _snack('Identity created. Your public key is now advertised.');
    _refresh();
  }

  Future<void> _unlock() async {
    final passwordController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unlock identity'),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _working = true);
    final success = await _identity.unlock(passwordController.text);
    setState(() => _working = false);
    if (success) {
      await BrokerService.instance.advertiseEverywhere();
      _snack('Identity unlocked.');
    } else {
      _snack('Wrong password.');
    }
    _refresh();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete identity?'),
        content: const Text(
            'This permanently removes your key pair from this device. '
            'Messages encrypted to it can no longer be read.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _identity.delete();
      _refresh();
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Security & Identity')),
        body: _exists == null
            ? const GlassShimmer()
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  LiquidGlass(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: ListTile(
                      leading: Icon(
                        _identity.isUnlocked
                            ? Icons.lock_open_rounded
                            : Icons.lock_rounded,
                        color: _identity.isUnlocked
                            ? Colors.greenAccent
                            : null,
                      ),
                      title: Text(_exists!
                          ? (_identity.isUnlocked
                              ? 'Identity unlocked'
                              : 'Identity locked')
                          : 'No identity yet'),
                      subtitle: Text(_exists!
                          ? 'Private keys are stored AES-256-GCM encrypted '
                              'with your password (PBKDF2, 210k rounds).'
                          : 'Create a key pair to advertise yourself on the '
                              'network and chat end-to-end encrypted.'),
                    ),
                  ),
                  if (_working)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (!_exists!)
                    LiquidGlass(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: ListTile(
                        leading: const Icon(Icons.key_rounded),
                        title: const Text('Create identity'),
                        onTap: _working ? null : _create,
                      ),
                    ),
                  if (_exists! && !_identity.isUnlocked)
                    LiquidGlass(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: ListTile(
                        leading: const Icon(Icons.lock_open_rounded),
                        title: const Text('Unlock with password'),
                        onTap: _working ? null : _unlock,
                      ),
                    ),
                  if (_public != null) ...[
                    LiquidGlass(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: ListTile(
                        leading: const Icon(Icons.badge_rounded),
                        title: Text(_public!.name),
                        subtitle: Text('Fingerprint: ${_public!.fingerprint}'),
                      ),
                    ),
                    LiquidGlass(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: ListTile(
                        leading: const Icon(Icons.public_rounded),
                        title: const Text('Public key (X25519)'),
                        subtitle: Text(
                          _public!.x25519PublicKey,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy_rounded),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(
                                text: _public!.x25519PublicKey));
                            _snack('Public key copied.');
                          },
                        ),
                      ),
                    ),
                    LiquidGlass(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: ListTile(
                        leading: const Icon(Icons.lock_rounded),
                        title: const Text('Lock now'),
                        onTap: () {
                          _identity.lock();
                          _refresh();
                        },
                      ),
                    ),
                  ],
                  if (_exists!)
                    LiquidGlass(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: ListTile(
                        leading:
                            const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
                        title: const Text('Delete identity'),
                        onTap: _delete,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
