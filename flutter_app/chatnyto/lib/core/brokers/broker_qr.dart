import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../widgets/liquid_glass.dart';
import 'broker_credentials.dart';
import 'broker_service.dart';

/// Sharing a network by sight: the owner shows a QR code, the other person
/// scans it, and the broker is added with its host, port and credentials —
/// no typing addresses.
///
/// The payload is a `chatnyto://broker?...` URL so the same code can also be
/// opened from a link.
class BrokerQr {
  static String encode(Broker broker) {
    final query = <String, String>{
      'name': broker.name,
      'host': broker.host,
      'port': broker.port.toString(),
      if (broker.username.isNotEmpty) 'user': broker.username,
      if (broker.password.isNotEmpty) 'pass': broker.password,
    };
    return Uri(
      scheme: 'chatnyto',
      host: 'broker',
      queryParameters: query,
    ).toString();
  }

  /// Parses a scanned code. Returns null when it is not a ChatNyto network.
  static Broker? decode(String raw) {
    try {
      final uri = Uri.parse(raw.trim());
      if (uri.scheme != 'chatnyto' || uri.host != 'broker') return null;
      final host = uri.queryParameters['host'];
      if (host == null || host.isEmpty) return null;
      return Broker(
        // Left empty when the code carries no name, so a published network
        // can still introduce itself by its own.
        name: uri.queryParameters['name']?.trim() ?? '',
        host: host,
        port: int.tryParse(uri.queryParameters['port'] ?? '') ?? 1883,
        username: uri.queryParameters['user'] ?? '',
        password: uri.queryParameters['pass'] ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}

/// Shows a broker's QR code, big enough to be scanned off the screen.
///
/// The code carries the address alone by default. A network's sign-in is
/// not the sort of thing to put on a screen someone may be pointing a camera
/// at from across the room, so including it is a deliberate choice, and the
/// password is only read out of the keystore once that choice is made.
class BrokerQrPage extends StatefulWidget {
  const BrokerQrPage({super.key, required this.broker});

  final Broker broker;

  @override
  State<BrokerQrPage> createState() => _BrokerQrPageState();
}

class _BrokerQrPageState extends State<BrokerQrPage> {
  bool _includeSignIn = false;
  bool _hasSignIn = false;
  Broker? _withSignIn;

  @override
  void initState() {
    super.initState();
    BrokerCredentials.instance.has(widget.broker.name).then((has) {
      if (mounted) setState(() => _hasSignIn = has);
    });
  }

  Future<void> _toggleSignIn(bool value) async {
    if (!value) {
      setState(() {
        _includeSignIn = false;
        _withSignIn = null;
      });
      return;
    }
    final stored = await BrokerCredentials.instance.read(widget.broker.name);
    if (!mounted) return;
    setState(() {
      _includeSignIn = true;
      _withSignIn = Broker(
        name: widget.broker.name,
        host: widget.broker.host,
        port: widget.broker.port,
        username: stored.username,
        password: stored.password,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final broker = _includeSignIn ? (_withSignIn ?? widget.broker) : widget.broker;
    final payload = BrokerQr.encode(broker);
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Share this network')),
        body: Center(
          child: SingleChildScrollView(
            child: LiquidGlass(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    broker.name,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Text('${broker.host}:${broker.port}',
                      style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: QrImageView(
                      data: payload,
                      size: 240,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_hasSignIn)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _includeSignIn,
                      onChanged: _toggleSignIn,
                      title: const Text('Include the sign-in',
                          style: TextStyle(fontSize: 14)),
                      subtitle: const Text(
                        'Off, the code shares the address only.',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  Text(
                    _includeSignIn
                        ? 'This code carries the password — only show it to '
                            'people you want on the network.'
                        : 'Anyone who scans this reaches the same network. If '
                            'it needs a sign-in, their app asks the server '
                            'for one, so you never hand a password over.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  // Not everyone is in the room. The same payload is a link,
                  // so it can be sent to somebody who is not.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: () => SharePlus.instance.share(
                          ShareParams(
                            text: payload,
                            subject: 'Join ${broker.name} on ChatNyto',
                          ),
                        ),
                        icon: const Icon(Icons.ios_share_rounded, size: 18),
                        label: const Text('Share link'),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                              ClipboardData(text: payload));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Link copied.')),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('Copy'),
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

/// Camera scanner that returns the scanned [Broker] to the caller.
class BrokerScanPage extends StatefulWidget {
  const BrokerScanPage({super.key});

  @override
  State<BrokerScanPage> createState() => _BrokerScanPageState();
}

class _BrokerScanPageState extends State<BrokerScanPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null) continue;
      final broker = BrokerQr.decode(value);
      if (broker != null) {
        _handled = true;
        Navigator.pop(context, broker);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan a network code')),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Align(
            alignment: Alignment.bottomCenter,
            child: LiquidGlass(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(16),
              child: const Text(
                'Point the camera at a ChatNyto network code.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
