/// The strings only Android's sign-up says (docs/design/pro-android-signup.md
/// §2.6 a) — the **absence list**. Two pins read it:
///
/// - `pro_login_only_test` (P2): none is in the iOS app's source, and each is
///   in the Android app's (or the absence would prove nothing);
/// - `app_review_notes_test` (P13): app-store-forms §11.3's
///   `gone_android_signup`, the iOS binary read, is this list plus the two
///   paths below.
///
/// « Pas encore de compte » is not here: it is already on the iOS lists.
const androidSignUpOnlyCopy = [
  // The sign-in's block.
  'Créer le compte de mon salon',
  // The screen, its headings.
  'Créer mon compte',
  'Votre identité de connexion',
  'Elle vous servira à vous connecter à votre espace pro.',
  'Utiliser une autre adresse',
  // The fields and their hints.
  'Nom de l’entreprise',
  'Type d’entreprise',
  'Salon de beauté',
  'Institut de manucure',
  'Téléphone du salon',
  'Commune (optionnel)',
  'Ex : Salon de Beauté Marie',
  'Le numéro que vos clients appellent.',
  'Rue, quartier, repère',
  '120 caractères au plus.',
  'Choisissez le type d’entreprise.',
  // The outcomes.
  'Vous aviez déjà un compte MyWeli Pro',
  'Cette adresse a reçu une invitation.',
  'Créer plutôt mon propre salon',
  'Ce code n’est plus valable.',
  'Vérifiez les informations du salon',
  'Un compte existe déjà pour cette identité.',
  'Choisissez une commune dans la liste.',
  // The consent line's lead.
  'En créant votre compte professionnel',
];

/// On the binary absence list only (§2.6): the first lives in the fenced
/// code; the second is the register call in the shared `ApiAuthService`,
/// which the iOS program's source does hold — only its binary can show the
/// call was dropped.
const androidSignUpOnlyPaths = ['/pro/register', '/auth/provider/register'];
