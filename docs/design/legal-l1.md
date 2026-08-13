# legal-l1 — the legal surface (L1)

| | |
|---|---|
| **Status** | Built (2026-07-27) |
| **Surface** | `web/` (four documents + the site's first footer) · `mobile/` (both apps) · `backend/` (reserved slugs) |
| **PRD ref / phase** | §18 Compliance & legal · FR-AUTH-005 · **V1 — launch blocker** |
| **Related spec** | [account-deletion-erasure.md](account-deletion-erasure.md) — the cascade that makes this policy true |
| **Design system** | [WEB-SYSTEM.md](WEB-SYSTEM.md) §3 type · §4 landmarks · §13.2 targets · [SYSTEM.md](SYSTEM.md) §10 `contentMaxWidth` · §17 language |
| **Skills checked** | myweli-web-guardrails · myweli-dev-guardrails · myweli-backend-guardrails |

## 1. Goal & scope

Both app stores require a reachable **privacy-policy URL**, and Google Play has
required an **account-deletion URL** since 2023, as submission fields. Measured at
`f92b8dc`: **no legal document exists in any surface.**

### ⚠️ The app already tells users they are accepting documents that do not exist

Three screens render this as **dead plain `Text`** — no link, no route, no
destination:

> « En continuant, vous acceptez nos conditions d'utilisation »

`login_screen.dart:188-198` · `phone_login_screen.dart:109-121` (dormant) ·
`booking_confirmation_screen.dart:418-434`. **Privacy is never mentioned at all**,
on any surface.

And **pro registration has zero consent copy** (`pro_register_screen.dart`,
`pro_login_screen.dart`): a professional creates an account, uploads **KYC identity
documents**, and publishes a business listing without ever being shown a term. That
is the sharpest store-review gap in the product, and it is the one this slice was
not originally scoped to find.

Three design docs (`app-auth-social.md:46`, `auth-social-email.md:313`,
`web-auth-social.md:52`) specify a "CGU line" as though it were implemented. It was
implemented as static text.

### There is also no `<footer>`

`WEB-SYSTEM.md` §4 mandates `<header> <nav> <main> <footer>` as landmarks.
`grep -rn "<footer" web/` returns **nothing**. The conventional home for legal links
does not exist, so this slice builds it — closing a documented violation that
**neither register recorded**.

### In scope

Four French documents · the site footer · both apps linking out · consent copy that
links · the deletion-dialog copy corrected to match the cascade · reserved slugs.

### Out of scope

- **A cookie-consent banner.** All five cookies are `httpOnly` session cookies and
  strictly necessary (`web/lib/session.ts:6-16`); there is no analytics, no
  advertising and no tracking cookie in the product. A banner would ask consent for
  nothing. **The policy says so explicitly** rather than staying silent.
- **String externalisation / an English version.** §21 row 36's V3 deferral stands.
- **A `PrivacyInfo.xcprivacy` manifest and the store data-safety forms.** They are
  submission artefacts, not repo code; the policy is their input. Filed.

## 2. UX & flows

### Entry points

| From | To |
|---|---|
| Site footer, every web page including `/pro` | all four |
| Consumer app → Profil → **À propos** | all four |
| Pro app → Profil → **À propos** | all four |
| Consumer login, booking confirmation, **pro registration** — the consent line | Confidentialité + CGU |
| Store listing (submission field) | Confidentialité + Suppression de compte |
| `sitemap.xml`, `llms.txt` | all four |

### States

A static server-rendered document has no loading, empty or error state of its own;
the four states live at the surrounding chrome, which already exists. What it does
have, and what the gates check:

- **Reachable logged out.** A store reviewer is never signed in. The routes carry no
  auth, and the app's « À propos » sits in the always-visible group — **no
  `returnTo` bounce**.
- **Readable at 375 px** — `type-overflow.spec.ts`, no horizontal scroll.
- **Readable at 200 % text** — inherited from the type tokens.
- **Reachable by keyboard, visibly focused** — `focus.spec.ts`, and every footer
  link is a 48 px target.
- **Offline in the app:** the link opens the system browser; if that fails,
  `openExternalUrl` shows the one canonical failure message rather than failing
  silently.

### Copy — the microcopy, not the documents

| Where | French |
|---|---|
| Footer nav label | « Liens légaux » |
| Footer links | « Politique de confidentialité » · « Conditions d'utilisation » · « Mentions légales » · « Supprimer mon compte » |
| App row | « À propos » |
| Consent, consumer login | « En continuant, vous acceptez nos **conditions d'utilisation** et notre **politique de confidentialité**. » |
| Consent, booking | « En confirmant, … » |
| Consent, **pro registration** | « En créant votre compte professionnel, … » |
| Link failure | « Impossible d'ouvrir le lien. » |
| Last-updated line | « Dernière mise à jour : 27 juillet 2026 » |

## 3. API & contract

No new endpoint. Two contract-shaped changes:

- `docs/api/openapi.yaml` `/me` `delete:` gains the deleted / anonymised / retained
  table — see [account-deletion-erasure.md](account-deletion-erasure.md) §3. That
  text is the source `/suppression-compte` and the app dialog paraphrase.
- `backend/lib/src/slug.dart`'s `reservedPublicSlugs` gains the four legal slugs.
  **Without this a salon can hold `/cgu`**, Next's static route shadows it, and that
  salon's public page becomes unreachable. The set is pinned by
  `backend/test/multi_pays_test.dart:130`. **Check production for an existing
  collision before deploying.**

## 4. Data model

None. The documents are code, not content rows — a CMS for four pages that change
once a year is infrastructure nobody needs.

`web/lib/legal.ts` is the single source of truth: `LEGAL_ROUTES` (slug · h1 · title
· description), **one** `LEGAL_UPDATED_AT` so four pages cannot drift, and a
`COMPANY` block where the RCCM lands as **one edit**.

## 5. Architecture & patterns

### Web

```
web/lib/legal.ts                       ← the only facts
web/components/legal/LegalPage.tsx     ← the only classNames
web/components/SiteFooter.tsx
web/app/{politique-confidentialite,cgu,mentions-legales,suppression-compte}/page.tsx
```

`LegalPage.tsx` exports the shell plus `H2`/`P`/`Ul`/`Li`/`A` primitives and
**carries every `className` in the feature**; the four page files contain **zero**.

That is not tidiness. The closed theme's real hazard is that **Tailwind emits
nothing for an unknown utility** — so a typo ships as an unstyled legal page with
`tsc`, lint and every test green. `tailwindcss/no-custom-classname` then has one
file to police instead of four.

**TSX, not MDX**: no MDX pipeline exists, and adding one would route all this copy
*around* the one lint rule holding the closed theme.

Shell derived from `components/landing/TaxonomyLandingView.tsx` — `<main
className="mx-auto max-w-content px-m py-l">` (720 px, SYSTEM §10: *"a 1000px-wide
line of French body copy is unreadable"*), its inlined `Crumbs`, `h1` at
`text-headlineMedium font-semibold`, `H2` at `text-titleLarge font-semibold`, `P` at
`text-bodyLarge text-textSecondary` (B8: French reading copy is 16).

**The footer renders on `/pro` too**, deliberately not mirroring `SiteChrome`'s
`/pro` null-return: `ProShell` is `min-h-screen lg:flex`, not `h-screen
overflow-hidden`, so a footer scrolls in and breaks no layout — and pros need the
CGU *more* than consumers, being the party contracting and uploading identity
documents. It is a **server** component; gating on pathname would force
`'use client'` on the footer of every page, for nothing.

### Mobile

`AppConfig` gains **one base + four getters**, because the paths are a contract with
`web/lib/legal.ts` and must move together:

```dart
static const String siteBaseUrl =
    String.fromEnvironment('SITE_BASE_URL', defaultValue: 'https://myweli.com');
static String get privacyUrl => '$siteBaseUrl/politique-confidentialite';
```

**The default is inverted from `supportWhatsApp`'s** (`app_config.dart:29`: empty
default, graceful degradation). Here the production URL is the default and the env
var is the *staging* override, because a store submission with a degraded privacy
link is a **rejection**, not a degraded experience.

`lib/core/utils/external_link.dart` — exactly two functions, converting **three**
call sites: the two byte-duplicated `wa.me` blocks (`profile_screen.dart:110-129`,
`pro_subscription_screen.dart:63-70`, including their duplicated failure copy) plus
the new legal links. **Not all eleven**: the other eight are five different
behaviours — a nav-app chooser that probes with `canLaunchUrl`
(`helpers.dart:37-124`), `tel:`↔`wa.me` contact fallbacks, Mobile Money deep links —
and one wrapper swallowing all five erases the differences that matter.

`_SettingsItem` (`profile_screen.dart:231-261`) is promoted to
`lib/widgets/common/settings_tile.dart`. `about_screen.dart` registers **top-level
as `/a-propos` in both routers** — a top-level path carries no auth connotation,
deep-links cleanly for a reviewer, and lets the flat `pro_router.dart` register the
identical route to the identical screen.

`legal_consent_text.dart` is a `Wrap` of a `Text` lead plus two text-style buttons,
**not** a `TextSpan` + `TapGestureRecognizer`: a recognizer span has no semantics
node and no 48 px box, so it would fail both §13.2 and `test/a11y/tap_target_test.dart`.

## 6. Security & authz

Public, unauthenticated, indexable, no personal data rendered. The only security
surface is the reserved-slug collision in §3 — a salon holding `/cgu` would be
shadowed by the static route, which is availability, not confidentiality.

The privacy policy **is** a security artefact in one direction: it describes the
data flows in `BACKEND.md` §7, so a claim in it that the code does not honour is a
defect. §11 records the three doc claims measured false while writing it.

## 7. Performance

Four static SSG documents, no JS beyond the existing chrome. `lighthouserc.json`
gains `/suppression-compte` — the page a reviewer actually opens — where SEO ≥ 0.9
and a11y ≥ 0.95 are *errors*, not warnings.

## 8. Testing plan

| Spec | Assertion |
|---|---|
| `tests/e2e/axe.spec.ts` | four routes into the loop (15 → 19). **Zero exclusions stays zero** |
| `tests/e2e/tap-targets.spec.ts` | a footer block on `/` — one route proves a site-wide footer |
| `tests/e2e/type-overflow.spec.ts` | `/suppression-compte` with a page-specific anchor (the vacuity guard the file's own header demands) |
| `tests/e2e/legal.spec.ts` *(new)* | per route: 200 · exactly one `<h1>` · `<footer>` present · canonical · every JSON-LD block parses with the right `@type` |
| `tests/legal.test.tsx` *(new)* | each page renders its h1 + `LEGAL_UPDATED_AT`; **no page contains « à valider »** — the counsel block lives in this spec and must never ship |
| `tests/seo.test.ts` | `webPageJsonLd` shape; `LEGAL_ROUTES` present in the sitemap head |
| `mobile/test/widget/profile_screen_test.dart` *(new — the screen's first)* | « À propos » present **and tappable**, logged out; version equals `AppConstants.appVersion` |
| `pro_profile_role_test.dart` | « À propos » in **all three** role blocks — legal is not capability-gated |
| `pro_register_form_test.dart` | a consent line naming both documents |

**Run `axe.spec.ts` at the footer commit, before any page exists** — so a footer
regression cannot hide behind a page regression.

### The admitted gap

No mobile test can reach the web, so pointing `AppConfig.privacyUrl` at a 404 goes
red **nowhere**. The only cover is `web/lib/legal.ts` and `AppConfig` being reviewed
as one contract, in one PR. Stated rather than discovered later.

## 9. Rollout & scope discipline

**Deploy order: backend → web → mobile.** The mobile binary hard-codes the URLs, so
shipping mobile first means a store reviewer taps a dead link.

V1 only. Mentions légales ships with a « société en cours d'immatriculation »
notice; the RCCM is one edit to `COMPANY` when registration completes.

## 10. Definition of done

- [ ] Four documents live, footer on every page, both apps linking out
- [ ] The three dead consent sentences are links, and **pro registration has consent
      at all**
- [ ] The deletion dialog says what the cascade actually does
- [ ] `reservedPublicSlugs` updated; production checked for a collision
- [ ] `tsc` · lint · vitest · playwright · axe · lighthouse green; `flutter analyze`
      0; `dart analyze` 0
- [ ] Registers + ROADMAP (French) in the same PR
- [ ] **All four URLs opened in a browser and read end to end** — a page that renders
      is not a page that is correct
- [ ] Feature branch → PR → **the user merges**; no Claude attribution

## 11. ⚠️ Facts measured while writing this, and three docs they contradict

The policy had to be built from the code, not the docs, because the docs are wrong
in three places:

1. **PRD §14 and §17 list Crashlytics/Sentry and ~20 analytics events as V1.**
   None of it exists — grep for sentry · firebase_analytics · posthog · mixpanel ·
   amplitude · crashlytics · gtag returns **two comments** in
   `mobile/lib/core/utils/logger.dart`. The policy describes the *current* state.
2. **BACKEND.md §3.6 and STRIDE T7 claim structured logging with redaction is
   "Enforced".** `grep -rn "print(\|stdout\|stderr" backend/lib backend/routes`
   returns **zero**. There is no request-logging middleware at all. The claim is
   vacuously safe today and wrong in the dangerous direction the moment someone adds
   a `print`.
3. **T27 says public provider reads contain "no PII".** They contain the salon's
   `phoneNumber`, `whatsapp`, `address`, coordinates, staff names and photos, and
   the **`depositMobileMoneyNumber`**. For a salon-as-business that is defensible;
   for a sole trader working à domicile it is personal data, and the policy says so.

Also measured, and load-bearing for the text: **data is hosted in the EU**, not
Côte d'Ivoire — a cross-border transfer that must be disclosed, and PRD **OQ-7**
(ARTCI residency) is still open.

> **Updated 2026-08-13.** This originally read *Frankfurt*, measured from
> `render.yaml`. The backend moved to **Cloud Run + Cloud SQL in
> `europe-west9` (Paris)** on 2026-08-06 and Render is gone
> ([infra-gcp-migration.md](infra-gcp-migration.md)). The legal conclusion is
> unchanged — still the EU, still a transfer out of Côte d'Ivoire — but the
> published texts named the wrong provider and the wrong country, which is a
> statement about where personal data is processed and therefore not a
> cosmetic error. `web/lib/legal.ts` and the privacy policy are corrected.
>
> **Open:** the mentions légales name *"Google Cloud"* by service rather than by
> contracting entity, because which Google entity is the counterparty (Google
> LLC vs Google Cloud EMEA Limited) depends on the billing account and has not
> been verified. Confirm at registration, alongside the other `pendingFacts`.

## 12. Open questions

- **OQ-7 / ARTCI.** Under the 2013 Ivorian data-protection law, processing generally
  requires a prior declaration to ARTCI. There is no evidence one has been filed and
  no reference number to publish. The policy names the obligation without claiming
  compliance.
- **`.com` vs `.ci`.** `render.yaml:41-44` and `DEPLOYMENT.md` use `myweli.com`;
  `PRD.md:506` says `myweli.ci`. This slice uses **`.com`** — what is actually
  deployed — and `SITE_BASE_URL` makes a switch one env var.
- **Support and privacy contact addresses.** `no-reply@myweli.com` is send-only and
  must **not** be the contact of record. `AppConfig.supportWhatsApp` and
  `NEXT_PUBLIC_MYWELI_WHATSAPP` are both unset. The documents need one reachable
  address each; until one exists the WhatsApp support channel is the only honest
  contact, and that is what they name.

---

# Appendix A — the French text

> **⚠️ À VALIDER PAR UN CONSEIL JURIDIQUE avant publication.**
>
> This block is the boundary between two different kinds of claim. **Everything
> below is drafted from the code**, and every factual statement is traceable to the
> inventory in §11 and to [account-deletion-erasure.md](account-deletion-erasure.md)
> §4. What it is *not* is legal advice, and the following need a lawyer's judgement
> rather than an engineer's:
>
> - the **lawful basis** claimed for each processing purpose under Ivorian law;
> - the **retention periods** — there is currently **no retention rule anywhere in
>   the code**, so any period stated is a commitment being made, not a behaviour
>   being described, and it must then be implemented;
> - whether an **ARTCI declaration** is required and what number to publish (OQ-7);
> - the **mentions légales** minima for an unregistered entity trading in CI;
> - the **CGU**'s liability, cancellation and deposit-dispute clauses, which
>   interact with `docs/design/deposit-*.md` and consumer-protection law;
> - whether the **cross-border transfer** to the EU (Paris) needs a stated
>   safeguard.
>
> **This marker string must never appear in shipped copy** — `tests/legal.test.tsx`
> asserts that no page contains « à valider ».

## A.1 Politique de confidentialité

**En une phrase.** Myweli met en relation des clients et des salons de beauté en
Côte d'Ivoire. Nous collectons le minimum nécessaire pour prendre et tenir un
rendez-vous — et **nous ne faisons ni publicité, ni profilage, ni analyse
comportementale.**

**Ce que nous ne faisons pas.** Ceci est vérifiable dans notre code :

- **aucun outil de mesure d'audience** (pas de Google Analytics, pas de PostHog, pas
  de Mixpanel) ;
- **aucun rapport de plantage** tiers (pas de Sentry, pas de Crashlytics) ;
- **aucun SDK publicitaire**, aucun traceur, aucun cookie publicitaire ;
- **aucun journal applicatif** : notre serveur n'enregistre ni votre adresse IP, ni
  votre navigateur, ni le détail de vos requêtes ;
- **aucune donnée bancaire** : Myweli ne détient jamais vos fonds. L'acompte se paie
  directement au salon par Mobile Money.

**Les données que nous traitons.**

| Catégorie | Détail | Pourquoi |
|---|---|---|
| Identité | nom, téléphone, e-mail, photo de profil issue de Google si vous vous connectez ainsi | créer et sécuriser votre compte |
| Connexion | identifiant technique Google ou Apple, codes à usage unique (chiffrés, durée de vie 5 minutes) | vous authentifier |
| Rendez-vous | date, salon, prestations, montants, vos notes éventuelles | tenir la réservation |
| Acompte | **la capture d'écran** que vous transmettez au salon, conservée dans un espace privé | prouver le paiement en cas de litige |
| Avis | votre nom d'affichage, votre note, votre texte, vos photos | informer les autres clients |
| Fiche client du salon | nom, téléphone, historique de visites, étiquettes et notes rédigées par le salon | permettre au salon de vous suivre |
| Notifications | jeton de votre appareil, préférences | vous prévenir d'un rendez-vous |
| Messages | numéro destinataire et contenu des SMS/WhatsApp transactionnels envoyés | preuve d'envoi, support |

Les professionnels transmettent en outre des **pièces d'identité** (KYC) : elles sont
stockées dans un espace **privé et séparé**, jamais publiées, et consultables
uniquement par un administrateur Myweli au moyen d'un lien signé valable 5 minutes.
Chaque consultation est journalisée.

**Ce qui est public.** La fiche d'un salon — nom, adresse, téléphone, WhatsApp,
coordonnées, photos, équipe, et **le numéro Mobile Money** servant à recevoir les
acomptes — est consultable sans compte. Si vous exercez à domicile, ces informations
peuvent vous identifier personnellement : n'y publiez que ce que vous acceptez de
rendre public.

**Où vos données sont hébergées.** Nos serveurs et notre base de données sont
hébergés par **Google Cloud, à Paris (France, Union européenne)** ; le site est
servi par **Vercel** ; les fichiers (photos, captures, pièces KYC) par **Cloudflare
R2**. **Vos données sortent donc de Côte d'Ivoire.**

**Qui d'autre les reçoit.** Uniquement des prestataires techniques, pour exécuter une
fonction précise : **Twilio** (SMS et WhatsApp), **Firebase Cloud Messaging**
(notifications), **Resend** (e-mails), **Google** et **Apple** (connexion),
**CARTO** (fonds de carte — l'affichage d'une carte transmet votre adresse IP à
CARTO). **Nous ne vendons ni ne louons aucune donnée.**

**Cookies.** Le site pose **cinq cookies, tous strictement nécessaires** à votre
session : ils sont `httpOnly` (inaccessibles au JavaScript), `Secure` et
`SameSite=Lax`. Aucun cookie de mesure ni de publicité. **C'est pourquoi il n'y a pas
de bandeau de consentement : il n'y a rien à consentir.** L'application, elle,
conserve votre session dans le coffre-fort du système (Keychain / Android Keystore).

**Vos droits.** Vous pouvez à tout moment consulter, corriger, exporter ou supprimer
vos données depuis **Profil → Mes données** et **Profil → Supprimer mon compte**,
sans nous écrire.

**Ce que la suppression fait exactement** — voir la page
[Supprimer mon compte](/suppression-compte), qui décrit poste par poste ce qui est
effacé, ce qui est anonymisé et ce qui est conservé.

## A.2 Suppression de compte

*(La page que les stores exigent. Elle est publique et lisible sans compte.)*

**Comment supprimer votre compte.** Dans l'application : **Profil → Supprimer mon
compte**, puis saisissez `SUPPRIMER` pour confirmer. Sur le web :
**Mon compte → Supprimer mon compte**. L'opération est immédiate et définitive.

**Ce qui est supprimé** — votre profil et vos identifiants · vos favoris · vos
préférences et votre historique de notifications · **les jetons de vos appareils,
donc vos notifications s'arrêtent** · vos signalements d'avis · vos codes de
connexion et vos sessions · **les captures d'écran d'acompte** que vous aviez
transmises.

**Ce qui est anonymisé** — vos **avis** restent en ligne sans votre nom : la note
appartient à l'évaluation d'un salon, et la retirer modifierait injustement sa
réputation · vos **rendez-vous** perdent votre nom, votre téléphone et vos notes ; le
salon conserve la trace comptable de la prestation · votre **fiche client** chez
chaque salon est délié de votre compte et son nom et son téléphone sont effacés.

**Ce qui est conservé, et pourquoi** — le **journal d'envoi** des SMS et WhatsApp
transactionnels, qui est indexé par numéro de téléphone et non par compte · votre
éventuelle **opposition à être recontacté**, précisément pour qu'elle continue de
vous protéger après la suppression.

**Si vous êtes professionnel**, la suppression exige d'abord de terminer ou d'annuler
vos rendez-vous à venir ; vos salons sont **dépubliés** et vos pièces d'identité
effacées.

**Avant de supprimer**, pensez à **exporter vos données** (Profil → Mes données).

## A.3 Conditions d'utilisation (CGU)

Couvrent : l'objet du service (**Myweli est un intermédiaire de mise en relation** —
la prestation est fournie par le salon, qui en est seul responsable) · l'inscription
et l'âge minimum · les obligations du client et du professionnel · **l'acompte**
(payé directement au salon, Myweli n'encaisse rien, ne rembourse rien, et n'est pas
partie au paiement) · l'annulation et le no-show, renvoyant à la politique affichée
par chaque salon · les avis (sincérité, modération, retrait) · le contenu publié par
les professionnels · la disponibilité du service · la responsabilité · la résiliation
· le droit applicable.

## A.4 Mentions légales

**Éditeur** — Myweli, **société en cours d'immatriculation** au Registre du Commerce
et du Crédit Mobilier de Côte d'Ivoire. Le numéro RCCM, le siège social, le capital
et le représentant légal seront publiés ici dès l'immatriculation effective.

**Directeur de la publication** — *(à compléter)*.
**Contact** — *(l'adresse retenue ; voir §12)*.
**Hébergeurs** — Google Cloud (Paris, France) · Vercel Inc. (États-Unis) ·
Cloudflare Inc. (stockage R2).
**Propriété intellectuelle** — la marque, le logo et le contenu éditorial de Myweli
sont protégés ; le contenu publié par chaque salon reste la propriété de ce salon.
