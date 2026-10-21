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
