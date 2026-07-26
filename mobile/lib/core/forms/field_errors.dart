// Design: docs/design/mobile-a7-forms.md · SYSTEM.md §14.

/// A single field's rule. Returns the message to show, or `null` when it passes.
///
/// Messages say what to DO, not what happened (§14 rule 4) — « Le code comporte
/// 6 chiffres. », never « Format invalide ».
typedef FieldValidator = String? Function(String value);

/// §14 rule 2, as a controller: **validate on submit; re-validate on change
/// once a field has already errored.** Never validate a field the user hasn't
/// finished typing into — the form that yells « e-mail invalide » at `s@` is
/// hostile.
///
/// The port of web's `lib/forms/useFieldErrors.ts`
/// ([web-b4-controls.md](../../../../docs/design/web-b4-controls.md)), because
/// **nothing in Flutter expresses rule 2**: `AutovalidateMode.onUserInteraction`
/// validates on *every* change once touched, which is precisely the behaviour
/// the rule forbids; `AutovalidateMode.onUnfocus` is blur-based, also not it;
/// and `FormState.validate()` returns a bare `bool` with no per-field map, no
/// subset scoping, and no way to attach a server fault to a field.
///
/// **Deliberately not a `ChangeNotifier`.** Form-error state is ephemeral and
/// screen-local: a notifier would buy nothing and cost a `dispose()` obligation
/// on every form in the app — and A6 found three leaked controllers in a
/// codebase that only had a handful. Callers mutate inside `setState`, which is
/// the idiom the OTP screen already used before this existed.
///
/// Usage — the auth funnels are the reference implementation:
///
/// ```dart
/// late final _errors = FieldErrors({
///   'email': Validators.email,
///   'code': Validators.otp,
/// });
///
/// // onChanged: setState(() => _errors.revalidate('email', v));  ← silent until errored
/// // onSubmit:  if (!_errors.validate({'email': _email.text})) { … }
/// // server:    setState(() => _errors.set('code', 'Code incorrect ou expiré.'));
/// ```
class FieldErrors {
  FieldErrors(this._validators);

  final Map<String, FieldValidator> _validators;
  final Map<String, String> _errors = <String, String>{};

  /// The message currently under [key], or `null` — pass straight to
  /// `AppTextField.errorText`.
  String? operator [](String key) => _errors[key];

  bool get isEmpty => _errors.isEmpty;
  bool get isNotEmpty => _errors.isNotEmpty;

  /// The first errored field **in the order the validators were declared**, so
  /// the focus move follows the form's reading order rather than hash order
  /// (§13.5, and §14's focus amendment).
  String? get firstErroredKey {
    for (final key in _validators.keys) {
      if (_errors.containsKey(key)) return key;
    }
    return null;
  }

  /// Submit. Validates **only the keys passed** and returns `true` when that
  /// subset is clean.
  ///
  /// Subset-scoped on purpose: a multi-step form submits one step at a time,
  /// and validating the phone on the e-mail step would fail a field the user
  /// has never seen.
  ///
  /// **It MERGES — it does not replace.** §14 says an error persists until it
  /// is fixed, so a submit that validates `{code}` must not wipe a still-unfixed
  /// error two fields up. Web shipped the replacing version and its adversarial
  /// review reproduced exactly that: a step-2 submit cleared a step-1 error
  /// **and the submit then fired with the empty value**.
  bool validate(Map<String, String> values) {
    var ok = true;
    values.forEach((key, value) {
      assert(
        _validators.containsKey(key),
        'FieldErrors: no validator declared for "$key"',
      );
      final fault = _validators[key]?.call(value);
      if (fault == null) {
        _errors.remove(key);
      } else {
        _errors[key] = fault;
        ok = false;
      }
    });
    return ok;
  }

  /// Rule 2's other half: re-run ONE validator, and **only if that field is
  /// already showing an error**. Before the first failed submit this is a no-op,
  /// which is the whole point — silence while the user is still typing.
  void revalidate(String key, String value) {
    if (!_errors.containsKey(key)) return;
    final fault = _validators[key]?.call(value);
    if (fault == null) {
      _errors.remove(key);
    } else {
      _errors[key] = fault;
    }
  }

  /// Attach a **server-side** fault to its field — rule 1 applies to those too:
  /// « Code incorrect ou expiré. » belongs under the code field, not in a bar
  /// that vanishes on a timer. Pass `null` to clear.
  ///
  /// Rule 2 then clears it as soon as a changed value passes the client check.
  void set(String key, String? message) {
    if (message == null) {
      _errors.remove(key);
    } else {
      _errors[key] = message;
    }
  }

  /// Wipe everything — a step change, or « Changer d'e-mail ».
  void clear() => _errors.clear();
}
