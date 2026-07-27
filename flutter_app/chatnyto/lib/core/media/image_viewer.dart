import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// A picture from a chat, full screen: pinch to zoom, save it to the device,
/// or pass it on to another app.
///
/// Pictures arrive inside the encrypted message rather than as a file, so
/// until the user asks for it there is nothing on disk to open — saving is
/// what writes the first copy out.
class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({
    super.key,
    required this.bytes,
    this.title = '',
    this.subtitle = '',
  });

  final Uint8List bytes;

  /// Who sent it, and when — shown in the bar over the picture.
  final String title;
  final String subtitle;

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  bool _busy = false;

  String get _fileName =>
      'chatnyto-${DateTime.now().millisecondsSinceEpoch}.jpg';

  /// Writes the picture to a real file so it can be handed to another app.
  Future<File> _spill() async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$_fileName');
    await file.writeAsBytes(widget.bytes);
    return file;
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    String message;
    try {
      if (Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isWindows) {
        // Goes into the photo library, which is where people look for it.
        final file = await _spill();
        await Gal.putImage(file.path, album: 'ChatNyto');
        message = 'Saved to your photos.';
      } else {
        // Desktop has no photo library to speak of; the Downloads folder is
        // the equivalent well-known place.
        final downloads =
            await getDownloadsDirectory() ?? await getTemporaryDirectory();
        final file = File('${downloads.path}/$_fileName');
        await file.writeAsBytes(widget.bytes);
        message = 'Saved to ${file.path}';
      }
    } catch (error) {
      debugPrint('Could not save the picture: $error');
      message = 'Could not save the picture: $error';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final file = await _spill();
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: 'image/jpeg')]),
      );
    } catch (error) {
      debugPrint('Could not share the picture: $error');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Deliberately not the glass background: a picture is judged against
      // black, and nothing else should compete with it.
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.4),
        foregroundColor: Colors.white,
        elevation: 0,
        title: widget.title.isEmpty
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title, style: const TextStyle(fontSize: 16)),
                  if (widget.subtitle.isNotEmpty)
                    Text(
                      widget.subtitle,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.normal),
                    ),
                ],
              ),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
              ),
            )
          else ...[
            IconButton(
              tooltip: 'Save',
              icon: const Icon(Icons.download_rounded),
              onPressed: _save,
            ),
            IconButton(
              tooltip: 'Share',
              icon: const Icon(Icons.ios_share_rounded),
              onPressed: _share,
            ),
          ],
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 6,
          child: Image.memory(widget.bytes, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
