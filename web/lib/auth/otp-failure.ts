import { GENERIC_ERROR_MESSAGE, NO_CONNECTION_MESSAGE } from '../api/network';

/// What a refused e-mail sign-in step says, and where — the client sign-in,
/// the salon sign-in and the salon sign-up share it
/// (docs/design/web-client-polish.md §2.1, owner decision Q1). Each code the
/// server names keeps the app's own sentence (`api_auth_service.dart`
/// `_messageFor`); a refusal that is the code's goes UNDER the code field, the
/// e-mail's under the e-mail (SYSTEM §14 rule 1); what is nobody's fault —
/// a rate limit, an outage, no answer — under the form. An unknown code is
/// never blamed on a field.
///
/// The surfaces keep their own account states before this table: « Compte
/// suspendu. » is here (the client's), « aucun compte » and « compte
/// existant » stay with the salon's screens.
export type SignInRefusal = { field: 'code' | 'email' | null; message: string };

const TOO_MANY = 'Trop de tentatives. Réessayez plus tard.';

const form = (message: string): SignInRefusal => ({ field: null, message });

/// « Se connecter » / « S'inscrire »: the code was judged — or not.
export function codeRefusal(r: { status: number; error?: string }): SignInRefusal {
  // Status 0 = no answer: the code was never judged.
  if (r.status === 0) return form(NO_CONNECTION_MESSAGE);
  switch (r.error) {
    case 'otp_invalid':
    // 4 to 8 digits, server-side: anything else typed is a wrong code.
    case 'invalid_input':
      return { field: 'code', message: 'Code incorrect.' };
    case 'otp_expired':
      return { field: 'code', message: 'Code expiré. Demandez un nouveau code.' };
    case 'otp_none':
      return { field: 'code', message: 'Aucun code actif. Demandez un nouveau code.' };
    case 'otp_locked':
      return {
        field: 'code',
        message: 'Trop de tentatives. Demandez un nouveau code.',
      };
    case 'account_suspended':
      return form('Compte suspendu.');
  }
  if (r.status === 429) return form(TOO_MANY);
  return form(GENERIC_ERROR_MESSAGE);
}

/// « Continuer avec e-mail » / « Renvoyer le code » / « Recevoir un code ».
export function sendRefusal(r: { status: number; error?: string }): SignInRefusal {
  if (r.status === 0) return form(NO_CONNECTION_MESSAGE);
  // The local check's own sentence: the server agreeing with it says the same.
  if (r.error === 'invalid_email') {
    return { field: 'email', message: 'Saisissez une adresse e-mail valide.' };
  }
  if (r.error === 'otp_resend_limit') {
    return form('Trop de demandes de code. Réessayez plus tard.');
  }
  if (r.status === 429) return form(TOO_MANY);
  return form(GENERIC_ERROR_MESSAGE);
}
