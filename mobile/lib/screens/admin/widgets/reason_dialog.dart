import 'package:flutter/material.dart';

/// A standard confirm dialog with a reason field. Returns the entered reason on
/// confirm, or null on cancel. When [reasonRequired], the confirm button is
/// disabled until non-empty. Design: docs/design/admin-console-ui.md §2.
Future<String?> showReasonDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String hint = '',
  bool reasonRequired = true,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 3,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Annuler'),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, value, __) {
            final text = value.text.trim();
            final enabled = !reasonRequired || text.isNotEmpty;
            return TextButton(
              onPressed: enabled ? () => Navigator.pop(ctx, text) : null,
              child: Text(confirmLabel),
            );
          },
        ),
      ],
    ),
  );
}
