import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// Picks and shrinks images before they travel over the network.
///
/// Everything ChatNyto sends may end up on a LoRa link, so pictures are
/// downscaled and re-encoded as JPEG until they fit a strict budget; the
/// result is base64 so it can ride inside the same encrypted envelope as
/// text, with no separate transport.
class ImageService {
  ImageService._();

  static final ImageService instance = ImageService._();

  final ImagePicker _picker = ImagePicker();

  /// Long edge, in pixels, of a picture sent in a chat.
  static const messageMaxEdge = 720;

  /// Long edge of a profile picture — it rides on the presence topic, which
  /// is retained, so it stays much smaller.
  static const avatarMaxEdge = 128;

  /// Picks a picture and returns it as base64 JPEG, or null if cancelled.
  Future<String?> pickAsBase64({
    required bool fromCamera,
    int maxEdge = messageMaxEdge,
    int quality = 70,
  }) async {
    try {
      final file = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 90,
      );
      if (file == null) return null;
      final bytes = await file.readAsBytes();
      return encodeShrunk(bytes, maxEdge: maxEdge, quality: quality);
    } catch (error) {
      debugPrint('Could not pick an image: $error');
      return null;
    }
  }

  /// Downscales [bytes] to fit [maxEdge] and encodes it as base64 JPEG.
  String? encodeShrunk(
    Uint8List bytes, {
    int maxEdge = messageMaxEdge,
    int quality = 70,
  }) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final longest =
        decoded.width > decoded.height ? decoded.width : decoded.height;
    final resized = longest <= maxEdge
        ? decoded
        : img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? maxEdge : null,
            height: decoded.height > decoded.width ? maxEdge : null,
            interpolation: img.Interpolation.average,
          );
    var jpeg = img.encodeJpg(resized, quality: quality);
    // Second pass for stubbornly large photos, so one picture can never
    // monopolise a slow link.
    if (jpeg.length > 120 * 1024 && quality > 40) {
      jpeg = img.encodeJpg(resized, quality: 40);
    }
    return base64Encode(jpeg);
  }

  /// Decodes what [pickAsBase64] produced, for display.
  static Uint8List? decode(String? base64Jpeg) {
    if (base64Jpeg == null || base64Jpeg.isEmpty) return null;
    try {
      return base64Decode(base64Jpeg);
    } catch (_) {
      return null;
    }
  }
}
