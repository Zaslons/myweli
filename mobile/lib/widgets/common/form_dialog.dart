import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'app_button.dart';

/// The one **editing** dialog — a form in a modal, submitted in place.
///
/// ## Why this exists alongside [ConfirmDialog]
///
/// `ConfirmDialog` is a *decision*: it collects at most one field and **pops on
/// confirm**. That is exactly right for « Bannir ce client ? » and exactly
/// wrong for a form, because a form has to survive its own failure — a server
/// fault that names a field must be able to attach to that field with the
/// dialog still open and the values still typed. Popping first and reporting
/// afterwards is how an operator ends up retyping three inputs from a snackbar
/// they can no longer see.
///
/// So the split is by *behaviour*, not by looks: decide → `ConfirmDialog`,
/// edit → this. Both own their `AlertDialog` so no screen builds one (§15); the
/// design-system pin allows exactly these two files.
///
/// [onSubmit] returns whether to close. Returning `false` keeps the dialog open
/// and leaves the caller free to have set field errors in the meantime.
///
/// Inherits from `ConfirmDialog` the two things that were got wrong severally
/// by hand-built copies: `scrollable: true` (a form at 200% text, or with the
/// keyboard up, overflows its own Column and paints over the buttons) and
/// cancel-takes-focus is deliberately NOT applied — a form focuses its first
/// field, which is the same doctrine as §15's "the field takes it instead".
///
/// SYSTEM.md §15.
class FormDialog extends StatefulWidget {
  const FormDialog({
    super.key,
    required this.title,
    required this.submitLabel,
    required this.child,
    required this.onSubmit,
    this.cancelLabel = 'Annuler',
  });

  final String title;

  /// A VERB naming the outcome — « Enregistrer les seuils », never « OK ».
  final String submitLabel;
  final String cancelLabel;

  /// The fields. The caller owns their controllers and their error state.
  final Widget child;

  /// Returns `true` to close. `false` keeps it open — the failure case, where
  /// the caller has just attached a fault to one of its fields.
  final Future<bool> Function() onSubmit;

  @override
  State<FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<FormDialog> {
  bool _submitting = false;

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final close = await widget.onSubmit();
    if (!mounted) return;
    setState(() => _submitting = false);
    if (close) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // Measured on ConfirmDialog and true here for the same reason: a form at
      // 200% text overflows its own Column and paints over the buttons.
      scrollable: true,
      title: Text(widget.title),
      content: SizedBox(width: 420, child: widget.child),
      actions: [
        TextButton(
          // Disabled only WHILE submitting — never as a way of expressing "the
          // form is invalid" (SYSTEM.md §844 rule 5).
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: Text(widget.cancelLabel),
        ),
        Padding(
          padding: const EdgeInsets.only(left: AppTheme.spacingS),
          child: AppButton(
            text: widget.submitLabel,
            isLoading: _submitting,
            onPressed: _submitting ? null : _submit,
          ),
        ),
      ],
    );
  }
}

/// The entry point — screens call this, never `showDialog` directly.
///
/// Same rule as `showConfirmDialog`: the raw `showDialog<bool>` lives in the
/// component so the design-system pin can hold "no screen builds its own
/// dialog" as a grep rather than as a convention.
///
/// Returns `true` when the form was submitted successfully, `false`/`null` when
/// it was cancelled or dismissed.
Future<bool?> showFormDialog({
  required BuildContext context,
  required String title,
  required String submitLabel,
  required Widget child,
  required Future<bool> Function() onSubmit,
  String cancelLabel = 'Annuler',
}) => showDialog<bool>(
  context: context,
  builder: (_) => FormDialog(
    title: title,
    submitLabel: submitLabel,
    cancelLabel: cancelLabel,
    onSubmit: onSubmit,
    child: child,
  ),
);
