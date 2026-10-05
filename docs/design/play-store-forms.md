# Play Console — les formulaires, réponse par réponse

| | |
|---|---|
| **Status** | Prêt à saisir (owner) — rédigé 2026-08-28 ; **corrigé 2026-09-24** (libellés de connexion du §2, adresse + numéro Mobile Money dans la table Pro du §4.2 — audit App Store, [app-store-forms.md](app-store-forms.md)) |
| **Portée** | Les DEUX fiches Play : MyWeli (`com.myweli.app`) et MyWeli Pro (`com.myweli.pro`) |
| **Source de vérité** | La politique de confidentialité publiée (`/politique-confidentialite`) et le binaire — un formulaire qui les contredit est un rejet ET une exposition légale (LAUNCH.md §6.3) |
| **Règle** | Chaque réponse ci-dessous est dérivée du code ou de la politique, jamais inventée. En cas de doute en saisissant : STOP, on vérifie. |

Ordre conseillé dans la console, par app : **Fiche du Play Store → Accès à
l'app → Classification du contenu → Sécurité des données**. Compter ~45 min
pour les deux apps.

---

## 1 · Fiche du Play Store (Store listing)

### MyWeli (consommateur)

- **Nom de l'app** (30 car. max) : `MyWeli — Beauté & rendez-vous`
- **Description courte** (80 car. max) :
  `Réservez coiffure, tresses, onglerie et spa près de chez vous, 24h/24.`
- **Description complète** (4000 car. max) :

> Trouvez et réservez les meilleurs salons de beauté de Côte d'Ivoire —
> coiffure, tresses, locks, barbier, onglerie, massage, spa — en quelques
> secondes, sans appel.
>
> **Réservez quand vous voulez.** Les créneaux affichés sont ceux du salon,
> en temps réel. Choisissez vos prestations, votre horaire, confirmez —
> c'est tout.
>
> **Comparez avant de choisir.** Photos, avant/après, avis clients, tarifs
> en FCFA et localisation sur la carte : chaque salon se présente
> entièrement.
>
> **Suivez vos rendez-vous.** Vos réservations, rappels et l'historique de
> vos visites, au même endroit. Modifiez ou annulez en un geste.
>
> **Payez comme d'habitude.** L'acompte éventuel se règle directement au
> salon par Mobile Money — MyWeli ne détient jamais votre argent.
>
> Sans publicité, sans profilage : nous ne collectons que le nécessaire à
> vos rendez-vous (politique de confidentialité sur myweli.com).
>
> Vous êtes un salon ? Téléchargez MyWeli Pro pour gérer agenda, équipe et
> clientèle.

### MyWeli Pro

- **Nom de l'app** : `MyWeli Pro — Gestion de salon`
- **Description courte** :
  `L'agenda, la clientèle et les réservations de votre salon, en une app.`
- **Description complète** :

> L'outil de gestion des salons de beauté de Côte d'Ivoire : recevez des
> réservations en ligne et pilotez votre activité au quotidien.
>
> **Votre agenda, tenu tout seul.** Les clients réservent sur vos créneaux
> réels ; vous ajoutez les rendez-vous pris au téléphone ou au comptoir en
> quelques gestes. Vue journée, semaine, et par membre d'équipe.
>
> **Votre vitrine en ligne.** Photos, avant/après, logo, prestations et
> tarifs, horaires avec modèles prêts à l'emploi : votre page publique sur
> myweli.com se remplit depuis l'app.
>
> **Votre clientèle, enregistrée d'elle-même.** Chaque réservation crée ou
> retrouve la fiche client — historique de visites, notes, étiquettes.
>
> **Vos acomptes, sans intermédiaire.** Le client paie l'acompte sur VOTRE
> Mobile Money et joint sa preuve ; vous confirmez. MyWeli ne touche jamais
> vos fonds.
>
> **Votre équipe.** Invitez manager, réception et collaborateurs, chacun
> avec les accès de son rôle.
>
> Conçu pour les réalités d'ici : FCFA, communes, à domicile, réseaux
> lents et petits téléphones.

- **Graphismes** (les deux apps) : icône 512×512 (déjà dans le repo),
  bannière « feature graphic » 1024×500 (à produire — me demander), 2 à 8
  captures de téléphone (prendre sur ton téléphone en 535 : accueil,
  recherche/carte, page salon, réservation pour MyWeli ; agenda, réservation
  manuelle, catalogue, disponibilités pour Pro).
- **Catégorie** : MyWeli → « Beauté ». Pro → « Entreprise » (Business).
- **Coordonnées** : e-mail de support + `https://myweli.com/support` ;
  politique de confidentialité :
  `https://myweli.com/politique-confidentialite` (les DEUX apps).

---

## 2 · Accès à l'app (App access)

### MyWeli Pro — identifiants de démonstration

Choisir « **Tout ou partie des fonctionnalités sont restreintes** » puis
« Ajouter des instructions » :

- **Nom d'utilisateur** : `revue@myweli.test`
- **Mot de passe** : le code à 6 chiffres — il est dans Secret Manager,
  **jamais dans ce repo ni dans le chat**. Le lire sur ton poste au moment
  de remplir :

  ```bash
  gcloud secrets versions access latest --secret=DEMO_PROVIDER_CODE --project=myweli
  ```

- **Instructions supplémentaires** (coller tel quel) :

> Sur l'écran « Espace Pro », saisir revue@myweli.test dans le champ
> « Votre e-mail », toucher « Continuer avec e-mail », puis saisir le code à
> 6 chiffres fourni ci-dessus dans « Code à 6 chiffres » et toucher « Se
> connecter » (l'e-mail n'existe pas : aucun message n'est envoyé, le code
> fourni remplace celui normalement envoyé). Vous
> arrivez sur un salon de démonstration complet : agenda rempli,
> réservations manuelles, clients, catalogue, photos, disponibilités,
> exports — tout fonctionne. Deux actions sont volontairement désactivées
> sur ce compte de démonstration (mise en ligne publique du salon et
> invitations d'équipe) et l'affichent clairement : « Compte de
> démonstration — cette action est désactivée. »

*Corrigé le 2026-09-24 (audit App Store,
[app-store-forms.md](app-store-forms.md) §8) : ce texte disait « Ouvrir « Se
connecter par e-mail » », un libellé qui n'existe pas dans l'app — l'écran de
connexion montre directement « Votre e-mail » puis « Continuer avec e-mail »,
et l'étape du code « Code à 6 chiffres » puis « Se connecter »
(`pro_login_screen.dart`). **Si l'ancien texte a déjà été saisi dans la Play
Console, le remplacer (owner).***

### MyWeli (consommateur)

Choisir aussi « restreintes » (la réservation demande un compte) avec ces
instructions — pas d'identifiants à fournir, l'inscription est libre :

> La navigation (recherche, pages salons, carte) est libre sans compte.
> Pour réserver, créez un compte en 30 secondes : « Continuer avec
> e-mail », saisissez n'importe quelle adresse e-mail que vous contrôlez —
> le code de connexion y est envoyé. Aucune validation manuelle, aucun
> paiement dans l'app.

---

## 3 · Classification du contenu (questionnaire IARC)

Identique pour les deux apps, catégorie **« Utilitaire, productivité,
communication ou autre »** :

| Question | Réponse |
|---|---|
| Violence, contenu sexuel, langage grossier, substances, jeux d'argent | **Non** partout |
| L'app permet-elle aux utilisateurs d'interagir ou d'échanger du contenu ? | **Oui** — les avis (note, texte, photos) sont publiés sur les pages salons ; pas de messagerie entre utilisateurs |
| Partage-t-elle la position actuelle de l'utilisateur avec d'autres ? | **Non** — côté client la position ne quitte jamais l'appareil ; le point affiché d'un salon est une adresse d'établissement saisie volontairement, pas la position en temps réel d'une personne |
| Achats numériques dans l'app ? | **Non** — aucun paiement dans l'app (l'acompte se règle hors app, au salon, par Mobile Money) |
| Contenu généré par les utilisateurs sans modération préalable ? | Les avis exigent une visite terminée ; photos et fiches salons passent par les comptes vérifiés — répondre selon le libellé exact à l'écran, dans cet esprit |

Résultat attendu : **Tout public / PEGI 3** avec la mention « Interaction
entre utilisateurs ».

---

## 4 · Sécurité des données (Data safety) — le formulaire qui compte

Principes transversaux, valables pour chaque ligne :

- **Chiffrement en transit** : **Oui** (tout passe en HTTPS).
- **Suppression demandable** : **Oui** — URL de suppression de compte :
  `https://myweli.com/suppression-compte` (in-app aussi : Profil →
  Supprimer mon compte).
- **« Partagées » au sens de Play** (transférées à un tiers pour SES
  fins) : **Non pour tout** — nos prestataires (Google Cloud, Firebase,
  Sentry, Resend, Cloudflare) sont des sous-traitants pour notre compte,
  ce que Play classe en « collecte », pas en « partage ». Nous ne vendons
  ni ne louons rien (politique, mot pour mot).
- **Pas de publicité ni marketing** : aucune donnée n'a la finalité
  « Publicité ou marketing » ni « Analyses » — les finalités sont
  « Fonctionnement de l'app », « Gestion du compte », et « Prévention de
  la fraude/sécurité » pour les journaux.

### 4.1 MyWeli (consommateur) — données collectées

| Type Play | Collecté ? | Facultatif ? | Finalité |
|---|---|---|---|
| Infos perso → **Nom** | Oui | Non (compte) | Gestion du compte |
| Infos perso → **E-mail** | Oui | Non | Gestion du compte |
| Infos perso → **N° de téléphone** | Oui | Non (contact réservation) | Fonctionnement |
| **Position** (approximative ET précise) | **Non collectée** — utilisée uniquement SUR l'appareil pour centrer la carte ; aucune coordonnée transmise (politique : « Elle ne quitte jamais votre appareil ») | — | — |
| **Photos** | Oui — photos d'avis et capture d'écran de preuve d'acompte, à l'initiative de l'utilisateur | Oui | Fonctionnement |
| Activité → **Contenu généré par l'utilisateur** | Oui — avis, notes de réservation | Oui | Fonctionnement |
| Infos app et performances → **Journaux de plantage** | Oui (Sentry, identité retirée avant envoi) | Non | Sécurité/diagnostic |
| Infos app et performances → **Diagnostics** | Oui (idem) | Non | Sécurité/diagnostic |
| Identifiants → **Identifiants d'appareil** | Oui — jeton de notification (FCM) | Oui (notifications refusables) | Fonctionnement |
| Infos financières | **Non** — aucune donnée bancaire ; la preuve d'acompte est une image fournie par l'utilisateur (déclarée en « Photos ») |
| Messages, contacts, calendrier, historique web, santé, identifiant publicitaire | **Non** partout |

### 4.2 MyWeli Pro — pareil, PLUS

| Type Play | Collecté ? | Note |
|---|---|---|
| **Position précise** | **Oui** | Le pro place le point de son salon — transmis et **public** (il sert à guider les clients ; la politique le dit explicitement) |
| **Photos** | Oui | Galerie, logo, avant/après — publics ; ET pièces KYC — privées |
| Infos perso → **Autres informations** | **Oui** | Pièces d'identité et d'immatriculation (KYC) : stockage privé séparé, jamais publiées, consultation admin par lien signé 5 min, journalisée |
| Activité → Contenu utilisateur | Oui | Fiches clients (nom, téléphone, notes du salon), catalogue, horaires |
| Infos perso → **Adresse** | **Oui** | « Adresse » à l'inscription et adresse du salon — publiée sur la page du salon *(ajouté 2026-09-24)* |
| Infos financières → **Autres infos financières** | **Oui** | Le **numéro Mobile Money de réception** des acomptes (« Numéro Mobile Money », paramètres d'acompte) — stocké et publié sur la page du salon. **Remplace, pour Pro, le « Non » hérité de la ligne consommateur.** *(ajouté 2026-09-24)* |

> **Ajouté le 2026-09-24 — le formulaire Play Pro doit être mis à jour
> (owner).** L'audit App Store de l'app Pro
> ([app-store-forms.md](app-store-forms.md) §7) a relu le code : l'app Pro
> envoie et stocke une **adresse** (`pro_register_screen.dart`, colonne
> `provider_users.address`) et le **numéro Mobile Money de réception**
> (`deposit_settings_screen.dart` → `depositMobileMoneyNumber`), qu'aucune
> ligne de cette table ne déclarait — et « pareil, PLUS » faisait hériter à
> Pro le « Infos financières : Non » du consommateur, activement faux. Les
> deux lignes ci-dessus sont ajoutées ; si la section Sécurité des données
> Pro a déjà été saisie, **la rouvrir dans la Play Console et les ajouter**,
> pour que Play, l'App Store et la politique racontent la même histoire.

> Sur l'écran de synthèse, Play affiche un aperçu de la section — la
> relire en la comparant à `/politique-confidentialite` avant de valider :
> les deux doivent raconter la même histoire.

---

## 5 · Divers à cocher en passant

- **Public cible** : 18 ans et plus (simple et vrai — des rendez-vous
  s'achètent). Pas d'app « famille ».
- **App d'actualités** : Non. **App de suivi contacts/COVID** : Non.
- **Fonctionnalité financière** : Non (aucun paiement traité par l'app).
- **Applis gouvernementales** : Non.
- **Publicité** : « Cette app ne contient pas de publicités » — les deux.

---

## 6 · Après la saisie

1. Me dire que c'est fait → je vérifie la cohérence forms ↔ politique une
   dernière fois et on coche LAUNCH.md §6.3.
2. La bannière 1024×500 : me demander quand tu veux — je la produis aux
   couleurs de la marque.
3. iOS reprendra les MÊMES réponses (App Privacy) — cette page est écrite
   pour servir deux fois. *(2026-09-24 : pour l'app Pro, le dossier iOS
   existe — [app-store-forms.md](app-store-forms.md) ; Apple demande en plus
   « lié à l'identité » par type, et ses catégories ne recoupent pas celles de
   Play une pour une.)*
