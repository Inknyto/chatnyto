import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/crypto/crypto_service.dart';
import '../core/crypto/password_vault.dart';
import '../core/widgets/liquid_glass.dart';

/// Shows a recovery code once, and makes it awkward to skip past.
///
/// There is no way to reset a ChatNyto password: the account's keys exist
/// only under the password and under this code, and nobody else holds a
/// copy. So the code is worth a whole screen, and the way out is a
/// deliberate confirmation rather than a back button.
class RecoveryCodePage extends StatefulWidget {
  const RecoveryCodePage({
    super.key,
    required this.code,
    this.isNew = true,
  });

  final String code;

  /// True right after the account was made, when there is nothing to go
  /// back to and the screen should read as part of the setup.
  final bool isNew;

  @override
  State<RecoveryCodePage> createState() => _RecoveryCodePageState();
}

class _RecoveryCodePageState extends State<RecoveryCodePage> {
  bool _acknowledged = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      // Leaving without reading it is exactly the mistake to prevent.
      canPop: !widget.isNew,
      child: GlassBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('Your recovery code'),
            automaticallyImplyLeading: !widget.isNew,
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Icon(Icons.vpn_key_rounded, size: 56, color: scheme.primary),
                const SizedBox(height: 20),
                const Text(
                  'Write this down and keep it somewhere safe.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'It is the only way back into this account if you forget '
                  'your password. Your keys never leave this device, so '
                  'nobody — including us — can let you back in without it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurface.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 24),
                LiquidGlass(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 22),
                  child: SelectableText(
                    widget.code,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 20,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: widget.code));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Recovery code copied.')),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Copy'),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => SharePlus.instance.share(
                        ShareParams(
                          text: 'ChatNyto recovery code: ${widget.code}',
                        ),
                      ),
                      icon: const Icon(Icons.ios_share_rounded, size: 18),
                      label: const Text('Save elsewhere'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  value: _acknowledged,
                  onChanged: (value) =>
                      setState(() => _acknowledged = value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('I have written it down'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  onPressed: _acknowledged
                      ? () => Navigator.pop(context, true)
                      : null,
                  child: const Text('Continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The way back in: recovery code, then a new password.
class RecoverAccountPage extends StatefulWidget {
  const RecoverAccountPage({super.key, this.accountId});

  /// Which account to recover; the active one when null.
  final String? accountId;

  @override
  State<RecoverAccountPage> createState() => _RecoverAccountPageState();
}

class _RecoverAccountPageState extends State<RecoverAccountPage> {
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _unlocked = false;
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _working = true;
      _error = null;
    });
    final ok = await IdentityService.instance.unlockWithRecoveryCode(
      _codeController.text,
      accountId: widget.accountId,
    );
    if (!mounted) return;
    setState(() {
      _working = false;
      _unlocked = ok;
      _error = ok ? null : 'That code does not open this account.';
    });
  }

  Future<void> _setPassword() async {
    if (_passwordController.text.length < 8) {
      setState(() => _error = 'Use at least 8 characters.');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    await IdentityService.instance.changePassword(_passwordController.text);
    await PasswordVault.instance.remember(_passwordController.text);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Recover your account')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.vpn_key_rounded, size: 56),
              const SizedBox(height: 20),
              Text(
                _unlocked
                    ? 'Choose a new password for this account.'
                    : 'Enter the recovery code you saved when you created '
                        'this account.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 20),
              LiquidGlass(
                padding: const EdgeInsets.all(16),
                child: _unlocked
                    ? TextField(
                        controller: _passwordController,
                        obscureText: true,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'New password',
                          helperText: 'At least 8 characters.',
                        ),
                        onSubmitted: (_) => _setPassword(),
                      )
                    : TextField(
                        controller: _codeController,
                        autofocus: true,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(
                            fontFamily: 'monospace', letterSpacing: 1.2),
                        decoration: const InputDecoration(
                          labelText: 'Recovery code',
                          hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
                        ),
                        onSubmitted: (_) => _check(),
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
                onPressed: _working
                    ? null
                    : (_unlocked ? _setPassword : _check),
                child: _working
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_unlocked ? 'Set password' : 'Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
