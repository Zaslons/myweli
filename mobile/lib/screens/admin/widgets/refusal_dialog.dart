import 'package:flutter/material.dart';

import '../../../core/forms/field_errors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/utils/validation_labels.dart';
import '../../../models/salon_validation.dart';
import '../../../services/admin/admin_service.dart';
import '../../../widgets/common/app_text_field.dart';
import '../../../widgets/common/form_dialog.dart';
import '../../../widgets/common/inline_feedback.dart';

/// What the refusal dialog's caller hears back.
enum RefusalDialogResult {
  /// The salon's request was refused.
  refused,

  /// The server answered that the request is no longer the one the screen
  /// read (409 `validation_not_pending`, a salon gone, a server from before
  /// B0.18): the dialog closed, and the screen's bar now says why.
  conflict,

  /// Cancelled, dismissed, or closed with nothing decided.
  cancelled,
}

/// One answer of the refusal call: whether it took, and if not, the server's
/// code and its French sentence (`AdminService.sentenceFor`).
typedef RefusalAnswer = ({bool ok, String? code, String? message});

/// Sends a refusal — `code` from §4.3's list, `note` trimmed or null.
typedef RefuseCall = Future<RefusalAnswer> Function(String code, String? note);

/// « Refuser » a salon's request to go live (B0.18 —
/// docs/design/salon-go-live-approval.md §4.3, « Refusing (Q1) »): a list of
/// codes, then a note.
///
/// - **A code is required**; each says, under its name, the sentence the
///   salon will read (the owner's approved words, decision 132). The two
///   final ones say so in words, not by colour.
/// - **The note** is required for « Autre » and capped at 500 characters
///   counted as the server counts them — code points of the trimmed text
///   ([refusalNoteLength]), not the grapheme clusters a `maxLength` counts.
///   Its live counter uses the same count. Its rules — no personal data,
///   never an instruction to pay (pro-companion-path §2.1) — are printed
///   under it and stay there, error or not.
/// - **Errors belong to their field** (SYSTEM.md §14): validated on submit,
///   re-validated as the admin fixes them; the server's own refusal of the
///   note lands under the note, with the dialog still open and the note
///   still typed — the reason this is a [FormDialog].
/// - **A failure that is not a field's** (offline, a server error) is said
///   inside the dialog ([InlineFeedback]: a snackbar under a modal barrier is
///   neither seen nor heard, §15). A conflict closes it: the request was
///   decided elsewhere, and the screen says so in its bar.
///
/// The submit is drawn as destructive; cancel is « Annuler ». The first code
/// takes focus on open; the codes are one radio group (Tab in, arrows
/// between, Space to choose), and a failed submit takes focus to the first
/// field at fault (§13.5, §14).
Future<RefusalDialogResult> showRefusalDialog(
  BuildContext context, {
  required RefuseCall refuse,
}) async {
  final key = GlobalKey<_RefusalFieldsState>();
  var result = RefusalDialogResult.cancelled;
  await showFormDialog(
    context: context,
    title: kRefusalDialogTitle,
    submitLabel: 'Refuser',
    isDestructive: true,
    child: _RefusalFields(key: key, refuse: refuse),
    onSubmit: () async {
      final outcome = await key.currentState?.submit();
      switch (outcome) {
        case null || _Submit.stay:
          return false;
        case _Submit.refused:
          result = RefusalDialogResult.refused;
          return true;
        case _Submit.conflict:
          result = RefusalDialogResult.conflict;
          return true;
      }
    },
  );
  return result;
}

/// The dialog's title.
const kRefusalDialogTitle = 'Refuser la mise en ligne';

/// Under the codes, when none was chosen.
const kRefusalCodeRequired = 'Choisissez un motif.';

/// The note's rules, printed under it (§4.3).
const kRefusalNoteRules =
    'Le salon lira cette note : aucune donnée personnelle, et jamais '
    'd’instruction de paiement.';

/// The counter under the note — « 12 / 500 ».
String refusalNoteCounter(int used) => '$used / $kRefusalNoteMaxCodePoints';

enum _Submit { stay, refused, conflict }

/// Codes after which the request is no longer the one on screen: the dialog
/// closes and the screen's bar carries the sentence.
const _conflictCodes = {'validation_not_pending', 'not_found', 'route_missing'};

class _RefusalFields extends StatefulWidget {
  const _RefusalFields({super.key, required this.refuse});

  final RefuseCall refuse;

  @override
  State<_RefusalFields> createState() => _RefusalFieldsState();
}

class _RefusalFieldsState extends State<_RefusalFields> {
  String? _code;
  final _note = TextEditingController();
  final _codeFocus = FocusNode();
  final _noteFocus = FocusNode();

  /// A failure that is not a field's — said inside the dialog.
  String? _formError;

  late final _errors = FieldErrors({
    'code': (v) => v.isEmpty ? kRefusalCodeRequired : null,
    'note': _noteFault,
  });

  late final Map<String, FocusNode> _nodes = {
    'code': _codeFocus,
    'note': _noteFocus,
  };

  /// The server's two checks on the note, in its words — through
  /// [refusalInputError], the one copy of its rules. Without a code yet, only
  /// the cap applies: the « Autre » rule waits for its code.
  String? _noteFault(String note) {
    final code = refusalInputError(
      code: _code ?? kSalonRefusalCodes.first,
      note: note,
    );
    return switch (code) {
      'note_required' || 'note_too_long' => AdminService.sentenceFor(code),
      _ => null,
    };
  }

  @override
  void dispose() {
    _note.dispose();
    _codeFocus.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  void _choose(String? code) {
    setState(() {
      _code = code;
      _errors.revalidate('code', code ?? '');
      // « Autre » makes the note required, and leaving it lifts that.
      _errors.revalidate('note', _note.text);
    });
  }

  Future<_Submit> submit() async {
    final ok = _errors.validate({'code': _code ?? '', 'note': _note.text});
    setState(() => _formError = null);
    if (!ok) {
      focusFirstError(_errors, _nodes);
      return _Submit.stay;
    }
    final trimmed = _note.text.trim();
    final answer = await widget.refuse(
      _code!,
      trimmed.isEmpty ? null : trimmed,
    );
    if (!mounted) return _Submit.stay;
    if (answer.ok) return _Submit.refused;
    if (_conflictCodes.contains(answer.code)) return _Submit.conflict;
    final field = switch (answer.code) {
      'note_required' || 'note_too_long' => 'note',
      'invalid_input' => 'code',
      _ => null,
    };
    setState(() {
      if (field != null) {
        _errors.set(field, answer.message);
      } else {
        _formError = answer.message ?? AdminService.sentenceFor(null);
      }
    });
    if (field != null) focusFirstError(_errors, _nodes);
    return _Submit.stay;
  }

  @override
  Widget build(BuildContext context) {
    final noteLength = refusalNoteLength(_note.text);
    final over = noteLength > kRefusalNoteMaxCodePoints;
    final noteRequired = _code == 'other';
    final muted = AppTextStyles.bodySmall.copyWith(
      color: AppColors.textTertiary,
    );
    final codeError = _errors['code'];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Le salon recevra le motif choisi et votre note.',
          style: AppTextStyles.bodyMedium,
        ),
        const SizedBox(height: AppTheme.spacingM),
        Semantics(
          header: true,
          headingLevel: 2,
          child: Text('Motif (obligatoire)', style: AppTextStyles.titleSmall),
        ),
        RadioGroup<String>(
          groupValue: _code,
          onChanged: _choose,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, code) in kSalonRefusalCodes.indexed)
                RadioListTile<String>(
                  value: code,
                  autofocus: i == 0,
                  focusNode: i == 0 ? _codeFocus : null,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    ValidationLabels.refusalName(code),
                    style: AppTextStyles.bodyMedium,
                  ),
                  subtitle: _CodeExplanation(code: code),
                ),
            ],
          ),
        ),
        if (codeError != null)
          // The codes' own error, under them — the field it belongs to.
          InlineFeedback(codeError),
        const SizedBox(height: AppTheme.spacingM),
        AppTextField(
          label: noteRequired
              ? 'Note pour le salon (obligatoire)'
              : 'Note pour le salon (facultative)',
          hint: 'Ce que le salon doit savoir ou corriger',
          controller: _note,
          focusNode: _noteFocus,
          maxLines: 4,
          errorText: _errors['note'],
          onChanged: (v) => setState(() => _errors.revalidate('note', v)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: AppTheme.spacingXS),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(kRefusalNoteRules, style: muted)),
              const SizedBox(width: AppTheme.spacingS),
              Text(
                refusalNoteCounter(noteLength),
                semanticsLabel:
                    '$noteLength caractères sur $kRefusalNoteMaxCodePoints',
                style: over
                    ? AppTextStyles.bodySmall.copyWith(color: AppColors.error)
                    : muted,
              ),
            ],
          ),
        ),
        InlineFeedback(_formError),
      ],
    );
  }
}

/// Under a code's name: what the salon will read, and — for the two final
/// codes — that it cannot ask again, in words (§13.6: not colour alone).
class _CodeExplanation extends StatelessWidget {
  const _CodeExplanation({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final sentence = ValidationLabels.salonSentences[code];
    final muted = AppTextStyles.bodySmall.copyWith(
      color: AppColors.textSecondary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          sentence == null
              ? 'Le salon lira votre note seule.'
              : 'Le salon lira : « $sentence »',
          style: muted,
        ),
        if (ValidationLabels.isFinal(code))
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.spacingXS),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.block,
                  size: AppTheme.iconXS,
                  color: AppColors.error,
                ),
                const SizedBox(width: AppTheme.spacingXS),
                Expanded(
                  child: Text(
                    'Définitif : le salon ne pourra pas renvoyer sa demande.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
