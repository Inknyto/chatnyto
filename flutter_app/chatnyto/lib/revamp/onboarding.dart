import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/brokers/broker_service.dart';
import '../core/crypto/crypto_service.dart';
import '../core/crypto/password_vault.dart';
import '../core/notifications/notification_service.dart';
import '../core/widgets/liquid_glass.dart';
import 'chat_service.dart';
import 'home_shell.dart';

/// First-run flow modeled on the whatsapp-clone onboarding: a welcome
/// screen, then one simple setup step (name + password) that silently
/// creates the encryption identity and connects the default brokers.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              LiquidGlass(
                radius: 120,
                padding: const EdgeInsets.all(48),
                child: Icon(
                  Icons.forum_rounded,
                  size: 120,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 40),
              const Text(
                'Welcome to ChatNyto',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Easy, secure connections between people, AI agents and '
                  'IoT devices — with or without internet. Everything is '
                  'end-to-end encrypted.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: SizedBox(
                  width: MediaQuery.of(context).size.width * .8,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    onPressed: () => Navigator.pushReplacement(
                      context,
                      GlassPageRoute(page: const SetupScreen()),
                    ),
                    child: const Text('Agree and continue'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One-step profile setup: pick a name and a password. The password only
/// protects the keys on this device — nothing to configure beyond that.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
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

  Future<void> _finish() async {
    final name = _nameController.text.trim();
    final password = _passwordController.text;
    if (name.isEmpty) {
      setState(() => _error = 'Please enter your name.');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    await IdentityService.instance.create(name, password);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile.name', name);
    // Remembered by default so the app opens straight into the chats; the
    // user can switch to being asked every time in the settings.
    await PasswordVault.instance.remember(password);
    await _startServices();
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
        appBar: AppBar(title: const Text('Set up your profile')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Center(
                child: CircleAvatar(
                  radius: 48,
                  child: Icon(Icons.person_rounded, size: 48),
                ),
              ),
              const SizedBox(height: 24),
              LiquidGlass(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Your name',
                        helperText: 'Visible to people you chat with',
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        helperText:
                            'Protects your encryption keys on this device',
                      ),
                      onSubmitted: (_) => _finish(),
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
              const SizedBox(height: 24),
              FilledButton(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                onPressed: _working ? null : _finish,
                child: _working
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Start chatting'),
              ),
              const SizedBox(height: 12),
              const Text(
                'A secure identity (encryption keys) is created for you '
                'automatically. No account, no phone number, no servers to '
                'configure.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Unlock screen for returning users.
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _passwordController = TextEditingController();
  bool _working = false;
  bool _rememberMe = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    PasswordVault.instance.askEveryOpen().then((ask) {
      if (mounted) setState(() => _rememberMe = !ask);
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() {
      _working = true;
      _error = null;
    });
    final ok =
        await IdentityService.instance.unlock(_passwordController.text);
    if (!ok) {
      setState(() {
        _working = false;
        _error = 'Wrong password, try again.';
      });
      return;
    }
    await PasswordVault.instance.setAskEveryOpen(!_rememberMe);
    if (_rememberMe) {
      await PasswordVault.instance.remember(_passwordController.text);
    }
    await _startServices();
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
        body: SafeArea(
          child: Center(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(32),
              children: [
                const Icon(Icons.lock_rounded, size: 64),
                const SizedBox(height: 16),
                const Text(
                  'Welcome back',
                  style:
                      TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                LiquidGlass(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _passwordController,
                    obscureText: true,
                    autofocus: true,
                    decoration:
                        const InputDecoration(labelText: 'Password'),
                    onSubmitted: (_) => _unlock(),
                  ),
                ),
                CheckboxListTile(
                  value: _rememberMe,
                  onChanged: (value) =>
                      setState(() => _rememberMe = value ?? true),
                  title: const Text('Remember me'),
                  subtitle: const Text(
                      'Keeps your password in this device\'s keystore so '
                      'ChatNyto opens straight into your chats.',
                      style: TextStyle(fontSize: 12)),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
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
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _working ? null : _unlock,
                  child: _working
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Unlock'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Connects brokers, advertises the identity and starts the chat service —
/// everything the app needs, with zero user configuration.
Future<void> _startServices() async {
  await NotificationService.instance.init();
  await BrokerService.instance.ensureDefaults();
  await ChatService.instance.init();
  // Fire and forget: connect whatever network is reachable.
  BrokerService.instance.autoConnectAll().then(
        (_) => BrokerService.instance.advertiseEverywhere(),
      );
}

/// Public wrapper used at app start for the already-onboarded path.
Future<void> startRevampServices() => _startServices();
