// Design: docs/design/hygiene-batch9.md §2.6 · SYSTEM.md §14 rule 1.

/// Which field an e-mail sign-in step's refusal belongs to — the app's copy of
/// the web's table (`web/lib/auth/otp-failure.ts`, `codeRefusal` and
/// `sendRefusal`; web-client-polish.md §2.1, owner decision Q1). The client
/// sign-in, the salon sign-in and the salon sign-up share it.
///
/// A refusal that is the code's goes UNDER the code field, the e-mail's under
/// the e-mail; everything else — a rate limit, a suspended account, no
/// answer — stays the form's (`InlineFeedback`). An unknown code is never
/// blamed on a field. The app put every one of them under the form, the web
/// under the field: the same server answer said in two places.
library;

/// « Se connecter » / « S'inscrire »: the code's fault, or null when the
/// refusal is not the code's.
///
/// `invalid_input` is the server's word for a code that is not 4 to 8 digits:
/// a wrong code, not « Numéro ou code invalide. » on a step with no number.
String? codeFieldFault(String? code) => switch (code) {
  'otp_invalid' || 'invalid_input' => 'Code incorrect.',
  'otp_expired' => 'Code expiré. Demandez un nouveau code.',
  'otp_none' => 'Aucun code actif. Demandez un nouveau code.',
  'otp_locked' => 'Trop de tentatives. Demandez un nouveau code.',
  _ => null,
};

/// « Continuer avec e-mail » / « Recevoir un code »: the e-mail's fault, or
/// null. The local check's own sentence — the server agreeing with it says
/// the same thing.
String? emailFieldFault(String? code) =>
    code == 'invalid_email' ? 'Saisissez une adresse e-mail valide.' : null;
