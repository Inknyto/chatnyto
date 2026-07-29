import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Typing or pasting a code instead of pointing a camera at one.
///
/// Every code the app hands out — a network, a contact, an account — is a
/// `chatnyto://…` link, and links get sent to people who are not in the
/// room. Sharing one is no use if the only way to take it in is to
/// photograph it off somebody's screen. This is the other half of that: the
/// same payload, arriving by clipboard or by hand.
///
/// It is also the way in when the camera is not: no permission, no camera at
/// all on a desktop, or a screen too dim to read a code off.
Future<String?> askForCode(
  BuildContext context, {
  required String title,
  required String hint,
}) async {
  final controller = TextEditingController();
  // Anyone who is here has almost certainly just copied the code, so try it
  // for them rather than making them paste it themselves.
  try {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboard?.text?.trim() ?? '';
    if (text.startsWith('chatnyto://')) controller.text = text;
  } catch (_) {
    // No clipboard on this platform, or nothing in it.
  }
  if (!context.mounted) return null;

  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 3,
        minLines: 1,
        decoration: InputDecoration(
          hintText: hint,
          helperText: 'Paste the link somebody sent you.',
          helperMaxLines: 2,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(dialogContext, controller.text.trim()),
          child: const Text('Use it'),
        ),
      ],
    ),
  );
}
