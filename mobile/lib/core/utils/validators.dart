import '../forms/field_errors.dart';

/// Design: docs/design/mobile-a7-forms.md · SYSTEM.md §14.
///
/// **One rule per concept, product-wide.** Before A7 this file held five
/// statics with two callers, while the screens carried their own copies: the
/// e-mail format existed **five times** (this file's, plus the same loose
/// `^[^@\s]+@[^@\s]+\.[^@\s]+$` pasted into four funnels), so two different
/// definitions of "valid e-mail" shipped in one app; `required` had seven
/// inline duplicates; and `otp`/`phoneNumber` had **zero** callers while three
/// live screens gated a « Code à 6 chiffres » field on `length < 4`.
///
/// Every message says what to DO, not what happened (§14 rule 4).
///
/// The return type is `String?` and the parameter is nullable, so each static
/// is usable both as a bare check and — thanks to Dart's contravariant
/// parameter subtyping — directly as a [FieldValidator] in a [FieldErrors] map.
class Validators {
  // ---- Identity -------------------------------------------------------------

  /// A required e-mail. The **one** definition; the four funnel copies died
  /// with A7.
  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Saisissez une adresse e-mail.';
    }
    return _emailFormat.hasMatch(value.trim())
        ? null
        : 'Saisissez une adresse e-mail valide.';
  }

  /// An e-mail the user may leave blank (the consumer profile). Empty passes;
  /// anything typed must still be a real address.
  static String? optionalEmail(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return _emailFormat.hasMatch(value.trim())
        ? null
        : 'Saisissez une adresse e-mail valide.';
  }

  static final RegExp _emailFormat = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  /// The verification code. **Six digits** — the number the field's own label
  /// (« Code à 6 chiffres »), its `maxLength`, and the golden baseline all
  /// already said, while three live screens gated on four.
  static String? otp(String? value) {
    final code = value?.trim() ?? '';
    if (code.isEmpty) return 'Saisissez le code reçu.';
    return RegExp(r'^\d{6}$').hasMatch(code)
        ? null
        : 'Le code doit comporter 6 chiffres.';
  }

  static String? name(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Saisissez un nom.';
    return text.length < 2
        ? 'Le nom doit comporter au moins 2 caractères.'
        : null;
  }

  // ---- Phone ----------------------------------------------------------------

  /// **E.164** (`+` then 8–15 digits) — what `PhoneNumberField` emits, and what
  /// the backend stores.
  static String? phoneNumber(String? value) {
    final cleaned = (value ?? '').replaceAll(RegExp(r'[\s\-()]'), '');
    if (cleaned.isEmpty) return 'Saisissez un numéro de téléphone.';
    return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(cleaned)
        ? null
        : 'Saisissez un numéro de téléphone valide.';
  }

  /// A number typed as an Ivorian **local** 10-digit one — the Mobile Money
  /// field and anywhere else the user types digits rather than picking a
  /// country. (CI moved to 10 digits in 2021; the hint « Ex : 07 07 12 34 56 »
  /// was already showing ten.)
  static String? localPhoneNumber(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return 'Saisissez un numéro de téléphone.';
    return digits.length == 10
        ? null
        : 'Le numéro doit comporter 10 chiffres (ex : 07 07 12 34 56).';
  }

  // ---- Generic factories ----------------------------------------------------

  /// A required field, naming itself. Replaces the seven inline « … est
  /// requis » closures.
  ///
  /// [what] completes the sentence: `requiredField('le nom du salon')` →
  /// « Indiquez le nom du salon. »
  static FieldValidator requiredField(String what) =>
      (value) => value.trim().isEmpty ? 'Indiquez $what.' : null;

  /// A price or deposit in FCFA — digits only, strictly positive.
  static FieldValidator amount(String what) => (value) {
    final text = value.trim();
    if (text.isEmpty) return 'Indiquez $what.';
    final parsed = int.tryParse(text.replaceAll(RegExp(r'[^\d]'), ''));
    if (parsed == null) return 'Indiquez $what en chiffres.';
    return parsed <= 0 ? 'Indiquez $what supérieur à 0.' : null;
  };

  /// A build number — digits only, **zero allowed**.
  ///
  /// Not [amount], and the difference is the whole reason this exists: `amount`
  /// rejects 0, while 0 is the legal value on a version floor meaning *no
  /// floor* — and the most common one, since every row ships at 0. Reusing
  /// `amount` would make the default state unsavable.
  ///
  /// The ceiling mirrors the server's (`admin_client_version_service.dart`): a
  /// floor above every build that will ever exist locks out everyone, and it is
  /// far more likely to be a typo than an intention.
  static FieldValidator buildNumber(String what) => (value) {
    final text = value.trim();
    if (text.isEmpty) return 'Indiquez $what.';
    final parsed = int.tryParse(text);
    if (parsed == null) return 'Indiquez $what en chiffres.';
    if (parsed < 0) return 'Indiquez $what à partir de 0.';
    return parsed > 1000000 ? 'Indiquez $what en dessous de 1 000 000.' : null;
  };

  /// A duration in whole minutes, strictly positive.
  static FieldValidator minutes(String what) => (value) {
    final text = value.trim();
    if (text.isEmpty) return 'Indiquez $what.';
    final parsed = int.tryParse(text);
    if (parsed == null) return 'Indiquez $what en minutes.';
    return parsed <= 0 ? 'Indiquez $what supérieure à 0.' : null;
  };
}
