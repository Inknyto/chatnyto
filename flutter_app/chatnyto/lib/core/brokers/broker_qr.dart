import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../widgets/liquid_glass.dart';
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
        name: uri.queryParameters['name']?.trim().isNotEmpty == true
            ? uri.queryParameters['name']!.trim()
            : 'Network at $host',
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
class BrokerQrPage extends StatelessWidget {
  const BrokerQrPage({super.key, required this.broker});

  final Broker broker;

  @override
  Widget build(BuildContext context) {
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
                  Text(
                    broker.password.isEmpty
                        ? 'Anyone who scans this joins the same network.'
                        : 'This code carries the password too — only show it '
                            'to people you want on the network.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
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
