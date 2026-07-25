import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';

/// Design: docs/design/mobile-a6-feedback.md · SYSTEM.md §15.

/// The optional input row — the admin's reason field, the before/after caption.
@immutable
class ConfirmField {
  const ConfirmField({
    this.hint = '',
    this.isRequired = true,
    this.maxLength,
    this.maxLines = 3,
    this.textCapitalization = TextCapitalization.sentences,
  });

  final String hint;

  /// Gates the confirm button until the field is non-empty.
  final bool isRequired;
  final int? maxLength;
  final int maxLines;
  final TextCapitalization textCapitalization;
}

/// The single destructive-confirm (SYSTEM.md §15, §11.3) — it replaced 13
/// hand-built `AlertDialog`s.
///
/// §15's ladder is expressed by WHICH fields you pass, so the friction is
/// proportional to the damage:
///
///   reversible          → don't use this at all. Act, and offer Undo in the
///                         snackbar (`AppSnackBar` + `SnackAction`).
///   hard to undo        → title + message + a VERB [confirmLabel]
///   irreversible/high   → …and [confirmWord] (type-to-confirm)
///
/// The confirm button is `error` when [isDestructive]; the **cancel path is the
/// safe default and takes focus** (§15, §13.5) — via `autofocus` on the cancel
/// button, which the `DialogRoute`'s own `FocusScope` resolves on the first
/// frame. A dialog with a [field] focuses the field instead: you cannot proceed
/// without typing, which is the same doctrine expressed by the friction itself.
class ConfirmDialog extends StatefulWidget {
  const ConfirmDialog({
    super.key,
    required this.title,
    required this.confirmLabel,
    this.message,
    this.content,
    this.icon,
    this.cancelLabel = 'Annuler',
    this.isDestructive = true,
    this.field,
    this.confirmWord,
  })  : assert(
          message == null || content == null,
          'pass a plain message OR a rich content, not both',
        ),
        assert(
          field == null || confirmWord == null,
          'type-to-confirm IS the field',
        );

  final String title;

  /// The plain-string body — "state the consequence" (§15).
  final String? message;

  /// The rich body, when the consequence is computed (a deposit forfeit).
  final Widget? content;

  /// An icon beside the title, for the highest rung.
  final IconData? icon;

  /// A VERB naming the outcome — « Supprimer la photo », never « OK » (§15).
  final String confirmLabel;
  final String cancelLabel;

  /// `true` → the confirm renders `error`. Set `false` for actions that are not
  /// destructive (logout, reporting a review, marking a no-show): red on a
  /// non-destructive action dilutes the signal.
  final bool isDestructive;

  final ConfirmField? field;

  /// Type-to-confirm, e.g. « SUPPRIMER » — the irreversible + high-value rung.
  final String? confirmWord;

  @override
  State<ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<ConfirmDialog> {
  // The dialog OWNS the controller — three hand-rolled dialogs leaked theirs.
  late final TextEditingController _controller = TextEditingController();

  bool get _hasInput => widget.field != null || widget.confirmWord != null;

  bool get _canConfirm {
    if (widget.confirmWord != null) {
      return _controller.text.trim().toUpperCase() ==
          widget.confirmWord!.toUpperCase();
    }
    if (widget.field?.isRequired ?? false) {
      return _controller.text.trim().isNotEmpty;
    }
    return true;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    return AlertDialog(
      // §13.1 (200 % text) — measured, not assumed: a consequence sentence plus
      // type-to-confirm overflowed its own Column by 4px at 2.0 on a 400×700
      // surface, painting the message over the buttons. The keyboard rising
      // under a field does the same. Gated by confirm_dialog_test.
      scrollable: true,
      title: widget.icon == null
          ? Text(widget.title)
          : Row(
              children: [
                Icon(
                  widget.icon,
                  color: widget.isDestructive
                      ? AppColors.error
                      : AppColors.textPrimary,
                  size: AppTheme.iconM,
                ),
                const SizedBox(width: AppTheme.spacingS),
                Expanded(child: Text(widget.title)),
              ],
            ),
      content: _buildContent(field),
      actions: [
        TextButton(
          // §15: "the cancel path is the safe default and gets focus." When
          // there is an input, the field takes it instead (see below).
          autofocus: !_hasInput,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        TextButton(
          style: widget.isDestructive
              ? TextButton.styleFrom(foregroundColor: AppColors.error)
              : null,
          onPressed: _canConfirm
              ? () => Navigator.of(context)
                  .pop(ConfirmResult(_controller.text.trim()))
              : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }

  Widget? _buildContent(ConfirmField? field) {
    final body = widget.content ??
        (widget.message == null ? null : Text(widget.message!));
    if (!_hasInput) return body;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (body != null) ...[
          body,
          const SizedBox(height: AppTheme.spacingM),
        ],
        if (widget.confirmWord != null) ...[
          Text(
            'Tapez ${widget.confirmWord} pour confirmer',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: AppTheme.spacingS),
        ],
        TextField(
          controller: _controller,
          // The field is the friction: it takes focus so the keyboard is
          // already up and the user must act deliberately.
          autofocus: true,
          maxLength: field?.maxLength,
          maxLines: widget.confirmWord != null ? 1 : (field?.maxLines ?? 3),
          textCapitalization: widget.confirmWord != null
              ? TextCapitalization.characters
              : (field?.textCapitalization ?? TextCapitalization.sentences),
          inputFormatters: widget.confirmWord == null
              ? null
              : [LengthLimitingTextInputFormatter(widget.confirmWord!.length)],
          decoration: InputDecoration(hintText: field?.hint ?? ''),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }
}

/// What a confirmed dialog pops. `null` from the show functions means
/// cancelled, barrier-dismissed or backed out — **the safe path, always**.
/// [text] is `''` when the dialog has no field.
@immutable
class ConfirmResult {
  const ConfirmResult(this.text);
  final String text;
}

/// A plain confirm. Returns `false` on cancel/dismiss — so a call site loses
/// the `confirmed != true` dance that four hand-rolled sites got wrong.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? message,
  Widget? content,
  IconData? icon,
  String cancelLabel = 'Annuler',
  bool isDestructive = true,
  String? confirmWord,
}) async =>
    await showDialog<ConfirmResult>(
      context: context,
      builder: (_) => ConfirmDialog(
        title: title,
        confirmLabel: confirmLabel,
        message: message,
        content: content,
        icon: icon,
        cancelLabel: cancelLabel,
        isDestructive: isDestructive,
        confirmWord: confirmWord,
      ),
    ) !=
    null;

/// A confirm that collects text (a reason, a caption). Returns `null` on
/// cancel; `''` is a legal confirmed value when the field is optional.
Future<String?> showInputDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  required ConfirmField field,
  String? message,
  String cancelLabel = 'Annuler',
  bool isDestructive = false,
}) async =>
    (await showDialog<ConfirmResult>(
      context: context,
      builder: (_) => ConfirmDialog(
        title: title,
        confirmLabel: confirmLabel,
        message: message,
        cancelLabel: cancelLabel,
        isDestructive: isDestructive,
        field: field,
      ),
    ))
        ?.text;
