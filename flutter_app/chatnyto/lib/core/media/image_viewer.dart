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

class _ImageViewerPageState extends State<ImageViewerPage>
    with SingleTickerProviderStateMixin {
  bool _busy = false;

  /// Driven by both the pinch gesture and the double tap, so the two agree
  /// on where the picture is.
  final TransformationController _view = TransformationController();
  late final AnimationController _zoomer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  Animation<Matrix4>? _zoom;

  /// How far a double tap zooms in. Enough to read a screenshot, not so far
  /// that the picture is lost off the edges.
  static const _doubleTapScale = 3.0;

  @override
  void initState() {
    super.initState();
    _zoomer.addListener(() {
      final zoom = _zoom;
      if (zoom != null) _view.value = zoom.value;
    });
  }

  @override
  void dispose() {
    _zoomer.dispose();
    _view.dispose();
    super.dispose();
  }

  /// Double tap zooms in on the point that was tapped, and a second one
  /// goes back — the gesture people already use on every other photo they
  /// have ever opened.
  void _onDoubleTap(TapDownDetails details) {
    final zoomedIn = _view.value.getMaxScaleOnAxis() > 1.01;
    final Matrix4 target;
    if (zoomedIn) {
      target = Matrix4.identity();
    } else {
      // Scale about the tapped point, so what you aimed at is what fills
      // the screen rather than the middle of the picture.
      final point = details.localPosition;
      target = Matrix4.identity()
        ..translate(-point.dx * (_doubleTapScale - 1),
            -point.dy * (_doubleTapScale - 1))
        ..scale(_doubleTapScale);
    }
    _zoom = Matrix4Tween(begin: _view.value, end: target).animate(
      CurvedAnimation(parent: _zoomer, curve: Curves.easeOutCubic),
    );
    _zoomer.forward(from: 0);
  }

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
        child: GestureDetector(
          // onDoubleTapDown is what carries the position; onDoubleTap has to
          // be present as well or the recogniser never claims the gesture.
          onDoubleTapDown: _onDoubleTap,
          onDoubleTap: () {},
          child: InteractiveViewer(
            transformationController: _view,
            minScale: 1,
            maxScale: 6,
            child: Image.memory(widget.bytes, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
