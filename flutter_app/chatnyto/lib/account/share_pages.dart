import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../core/crypto/contact_book.dart';
import '../core/crypto/crypto_service.dart';
import '../core/media/image_service.dart';
import '../core/widgets/liquid_glass.dart';
import '../core/widgets/person_avatar.dart';

/// A person as a link: `chatnyto://contact?...`.
///
/// Everything in it is public — a name and two public keys — so it is safe
/// to put on a screen, print, or send over any channel. What it buys the
/// person scanning it is the ability to write to you end-to-end encrypted
/// straight away, and to recognise you later: the key in the code is the
/// one every message of yours is signed with.
class ContactLink {
  /// The picture is left out on purpose: a base64 photograph would push the
  /// code past what a phone camera reads comfortably, and it arrives with
  /// the first presence announcement anyway.
  static String encode(PublicIdentity identity) => Uri(
        scheme: 'chatnyto',
        host: 'contact',
        queryParameters: <String, String>{
          'n': identity.name,
          'x': identity.x25519PublicKey,
          'e': identity.ed25519PublicKey,
          's': identity.signature,
        },
      ).toString();

  static PublicIdentity? decode(String raw) {
    try {
      final uri = Uri.parse(raw.trim());
      if (uri.scheme != 'chatnyto' || uri.host != 'contact') return null;
      final x = uri.queryParameters['x'];
      final e = uri.queryParameters['e'];
      final s = uri.queryParameters['s'];
      if (x == null || e == null || s == null) return null;
      return PublicIdentity(
        name: uri.queryParameters['n'] ?? 'Someone',
        x25519PublicKey: x,
        ed25519PublicKey: e,
        signature: s,
      );
    } catch (_) {
      return null;
    }
  }
}

/// An account as a transfer code: `chatnyto://account?d=...`.
class AccountLink {
  static String encode(String blob) =>
      Uri(scheme: 'chatnyto', host: 'account', queryParameters: {'d': blob})
          .toString();

  static String? decode(String raw) {
    try {
      final uri = Uri.parse(raw.trim());
      if (uri.scheme != 'chatnyto' || uri.host != 'account') return null;
      final blob = uri.queryParameters['d'];
      return (blob == null || blob.isEmpty) ? null : blob;
    } catch (_) {
      return null;
    }
  }
}

/// "This is me": your own QR code and link, to hand to someone in person.
class MyContactPage extends StatefulWidget {
  const MyContactPage({super.key});

  @override
  State<MyContactPage> createState() => _MyContactPageState();
}

class _MyContactPageState extends State<MyContactPage> {
  PublicIdentity? _me;

  @override
  void initState() {
    super.initState();
    if (IdentityService.instance.isUnlocked) {
      IdentityService.instance.publicIdentity().then((identity) {
        if (mounted) setState(() => _me = identity);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    final picture = ImageService.decode(me?.avatar);
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('My contact code')),
        body: me == null
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: SingleChildScrollView(
                  child: LiquidGlass(
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PersonAvatar(
                          name: me.name,
                          avatar: me.avatar,
                          radius: 30,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          me.name,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          me.fingerprint,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 11),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: QrImageView(
                            data: ContactLink.encode(me),
                            size: 240,
                            backgroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Scanning this adds you as a contact, so they can '
                          'write to you even when you are not on the air.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton.icon(
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(
                                    text: ContactLink.encode(me)));
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Link copied.')),
                                );
                              },
                              icon: const Icon(Icons.link_rounded, size: 18),
                              label: const Text('Copy link'),
                            ),
                            TextButton.icon(
                              onPressed: () => SharePlus.instance.share(
                                ShareParams(
                                  text: '${me.name} on ChatNyto: '
                                      '${ContactLink.encode(me)}',
                                ),
                              ),
                              icon: const Icon(Icons.ios_share_rounded,
                                  size: 18),
                              label: const Text('Share'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// The result of scanning: either a contact that was saved, or an account
/// that was taken in.
enum ScanOutcome { contact, account }

/// Camera scanner for contact and account codes.
class ContactScanPage extends StatefulWidget {
  const ContactScanPage({super.key});

  @override
  State<ContactScanPage> createState() => _ContactScanPageState();
}

class _ContactScanPageState extends State<ContactScanPage> {
  bool _handled = false;
  String? _error;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue ?? '')
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    if (raw.isEmpty) return;

    final contact = ContactLink.decode(raw);
    if (contact != null) {
      _handled = true;
      final ok = await ContactBook.instance.add(contact);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _handled = false;
          _error = 'That code does not verify against its own key.';
        });
        return;
      }
      Navigator.pop(context, (ScanOutcome.contact, contact.name));
      return;
    }

    final blob = AccountLink.decode(raw);
    if (blob != null) {
      _handled = true;
      final name = await IdentityService.instance.importAccount(blob);
      if (!mounted) return;
      if (name == null) {
        setState(() {
          _handled = false;
          _error = 'That account code could not be read.';
        });
        return;
      }
      Navigator.pop(context, (ScanOutcome.account, name));
      return;
    }

    setState(() => _error = 'Not a ChatNyto code.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan a code')),
      body: Stack(
        children: [
          MobileScanner(onDetect: _onDetect),
          Positioned(
            left: 0,
            right: 0,
            bottom: 32,
            child: Center(
              child: LiquidGlass(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  _error ??
                      'Point the camera at a contact code or an account '
                          'transfer code.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: _error == null ? null : Colors.redAccent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows the code that carries an account to another device.
class AccountTransferPage extends StatelessWidget {
  const AccountTransferPage({
    super.key,
    required this.blob,
    required this.name,
  });

  final String blob;
  final String name;

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Use this account elsewhere')),
        body: Center(
          child: SingleChildScrollView(
            child: LiquidGlass(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: QrImageView(
                      data: AccountLink.encode(blob),
                      size: 260,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Scan this on the other device to open the same account '
                    'there. It stays encrypted with your password, which the '
                    'code does not contain — you will be asked for it.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 16, color: Colors.orangeAccent),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Anyone who scans it and knows your password holds '
                          'your identity. Show it to nobody else.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.75),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
