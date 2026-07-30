import 'package:flutter/material.dart';

import '../../../widgets/common/confirm_dialog.dart';

/// A standard confirm dialog with a reason field. Returns the entered reason on
/// confirm, or null on cancel. When [reasonRequired], the confirm button is
/// disabled until non-empty. Design: docs/design/admin-console-ui.md §2.
///
/// A6: this is now a thin caller of [ConfirmDialog] — one dialog implementation
/// product-wide (SYSTEM.md §15), so the admin inherits the cancel-takes-focus
/// rule and a disposed controller for free. The 9 call sites keep this exact
/// signature; it gained [isDestructive] so « Bannir », « Suspendre » and
/// « Rejeter » render the `error` confirm §15 requires instead of a neutral one.
Future<String?> showReasonDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String hint = '',
  bool reasonRequired = true,
  bool isDestructive = false,
}) =>
    showInputDialog(
      context,
      title: title,
      confirmLabel: confirmLabel,
      isDestructive: isDestructive,
      field: ConfirmField(hint: hint, isRequired: reasonRequired),
    );
