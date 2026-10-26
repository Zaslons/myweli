/// What the app says when something fails (docs/design/app-failure-messages.md
/// §8, the owner's words of 2026-10-21). Two sentences, the same on the web
/// (`NO_CONNECTION_MESSAGE` and `GENERIC_ERROR_MESSAGE` in
/// `web/lib/api/network.ts`).
library;

/// Nothing answered — no network, the connection dropped. The ONLY sentence
/// for it: « Connexion au serveur impossible » is retired.
const kNoConnectionMessage = 'Pas de connexion. Réessayez.';

/// Something answered that the app cannot use, a refusal whose code has no
/// sentence of its own, or an exception. Never « Erreur » alone, never an
/// exception's text, never the server's own `message`.
const kGenericErrorMessage = 'Une erreur est survenue. Réessayez.';

/// A sign-in with no Pro account (`provider_not_found`) — the API mapping,
/// the mock and [ProAuthProvider] after the last invitation is declined say
/// the same sentence. It never points to a sign-up: the app does not sign a
/// business up (App Store 3.1.1); the login screen's « S’inscrire sur
/// myweli.com » does that, once, for everyone. The hint serves an invited
/// employee who signed in with another address.
/// docs/design/pro-app-login-only.md §4.2.
const kNoProAccountMessage =
    'Aucun compte MyWeli Pro n’est associé à cette adresse. Si votre salon '
    'vous a invité, connectez-vous avec l’adresse qui a reçu l’invitation.';
