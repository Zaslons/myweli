# Apple's second rejection of MyWeli Pro 0.0.1 — round 2 (2.3.4, 3.1.1)

| | |
|---|---|
| **Status** | Approved 2026-11-03 (owner: §3, five decisions) · build, upload and resubmission are the owner's go (§12). **The app's half (§4, §10), the web's half (§5), the texts for Apple (§6, §7), the film's storyboard (§8) and the record are done** on `fix/app-review-round2`: not merged, not in any build, not live, not pasted, not uploaded, not seen on a device. The notes' wording waits for the owner's approval |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-03 |
| **PRD ref / phase** | FR-PRO-AUTH-001 (registration on the web only) · V1 |
| **BACKLOG** | B0.1, B0.2, B0.3, B0.11 (batch 0, the release track) |
| **Related** | [pro-app-login-only.md](pro-app-login-only.md) (round 1; its §8 and Q1 pre-agreed this removal) · [app-store-forms.md](app-store-forms.md) (§8 notes, §11.3 IPA check, §11.6 device checks, §13.2 reply) · [pro-app-preview.md](pro-app-preview.md) (the film) · [web-pro-access.md](web-pro-access.md) (P1 header door, P2 footer group, the two things §5 narrows) · [pro-companion-path.md](pro-companion-path.md) |
| **Skills checked** | myweli-dev-guardrails · myweli-web-guardrails · myweli-verification-guardrails |

## 1. Why — Apple's message

App Review, 3 November 2026, **build 698**, iPad Air 11-inch (M3), submission
`45ed9726-1418-435b-b3e2-76726422c5d3`. Two guidelines:

- **2.3.4.** « Includes framing around the video screen capture of the app. »
  Next step: only video screen captures, with narration and video or textual
  overlays. « some app previews may only be viewed and updated by selecting
  "View All Sizes in Media Manager" ».
- **3.1.1.** The login page's call to action « S'inscrire sur myweli.com ». Next
  step: « remove features, account registration links, and any other links to
  your site that could indirectly provide access to external purchase
  mechanisms. »

The second one is wider than the first rejection (build 587, 19 October, the
in-app registration form). « any other links to your site » is what makes the
required support and legal pages part of this round (§5), even though Apple did
not cite them.

## 2. What the audit found

A read-only audit on `main` at `acd6d73f` (2026-11-03): Apple's pages, every
link and sentence in the Pro app, the store metadata, the preview, the release
route, then an adversarial pass. Line numbers are from that commit.

**Pro** means the import closure of `lib/main_pro.dart`, computed by script: 264
of 353 Dart files, read against the 33 routes of `pro_router.dart`.

| # | Finding | Where | Rated |
|---|---|---|---|
| 1 | The only in-app call to action towards sign-up. It sits after the step branches, so it renders on options, code **and** invitations: the demo path shows it. Round 1's §4.1 said « options step » only | `pro_login_screen.dart:463-472` | Cited |
| 2 | The framed film (capture in a rounded card on paper, mark and headline above) sits in both iPhone slots | `build/app-store/pro/preview/v2/final/preview.mp4`, BACKLOG:489 | Cited |
| 3 | All five pages the app opens lead to sign-up in one tap: header « Espace pro », footer « Inscrire mon salon ». Then `/pro/abonnement` shows the offers behind sign-up. The header link only hides below `sm`, so a reviewer's iPad sees it | `web/components/Header.tsx:29-34`, `SiteFooter.tsx:10-14` | Medium |
| 4 | `/support` is the one in-app destination whose body names billing | `web/app/support/page.tsx:65` | Low |
| 5 | The notes describe the cited link and send the reviewer to register on myweli.com for the deletion test | `app-store-forms.md:640`, `:643` | Must change |
| 6 | The notes cite 3.1.3(f). Apple's text is a closed list (VoIP, cloud storage, email, web hosting); a salon tool is none of those. Our docs quote only the tail of the rule | `app-store-forms.md:628`, `:255`, `:1652` | Weak claim |
| 7 | The IPA check for build 698 expected the link and `/pro/inscription` to be **present** | `app-store-forms.md:1194-1196` | Must flip |
| 8 | The next build carries B9.13 and B9.14, which rewrite sign-in, restore, sign-out and the session-end path, and have never run in a signed build | `refreshing_http_client.dart`, BACKLOG:468-469 | Device pass |
| 9 | Both rejections name an iPad Air; Pro is iPhone-only (`TARGETED_DEVICE_FAMILY = 1`, `project.pbxproj:1347`) and its look in iPhone compatibility mode on an iPad is only inferred | `app-store-forms.md:73` | Device pass |
| 10 | Round 1's « one widget, one test line » undercounts: 1 widget, 3 imports, 1 getter, 1 orphan file, 1 false comment, 4 test files, 1 golden | §4.3, §10 | Corrected |

Clean, read and left alone: no other Pro string contains `myweli.com`, « le
site », « navigateur » or « inscri… »; no share link and no displayed public URL;
no native resource names the site (`grep` over `ios/Runner` and `android/app/src`,
re-read for this spec). « Mon abonnement » is a statement with no button or price
(`pro_subscription_no_pricing_test.dart`). Phone, `wa.me` and map links lead to
third parties, not to our site.

Not observable by anyone in this round, and stated as such: App Store Connect's
live state, the Resolution Center thread, build 698's binary, the app on an iPad,
production demo data. Whether a reviewer would tap through the web pages is a
judgement; Apple has not cited them.

## 3. The owner's decisions (2026-11-03)

In their own words, from the question they answered. They bind everything below.

| # | Decision | What it means |
|---|---|---|
| 1 | The login link goes, on both platforms: pre-agreed in [pro-app-login-only.md](pro-app-login-only.md) §8 and Q1 (one behaviour) | §4. No iOS-only branch |
| 2 | VIDEO: « Upload the full-screen trial » | §8. The full-bleed cut of the same storyboard and takes, as rendered, end card included. The owner was told it still ends on a paper card, that Revenus says « Total » where the app says « Total réalisé », and that a third rejection is possible. **Accepted risk** (§13). A proper retake is for 0.0.2 |
| 3 | WEB: « Remove the links » | §5. On exactly five pages. The logo and breadcrumb still go home. Every other page unchanged |
| 4 | DESCRIPTION: « Both edits » | §7 |
| 5 | DEVICE CHECK: « Focused pass » | §11. Replaces decision 2's full list for this build |

Also decided: stop citing guideline 3.1.3(f) in anything sent to Apple; rewrite
the review notes; the owner approves the notes' wording and sends the Resolution
Center reply themselves. **No production backend deploy** (decision 47).

## 4. The app — the removal

### 4.1 « Connexion » (`pro_login_screen.dart`), both platforms

| Where | Before | After |
|---|---|---|
| Below every sign-in step | « Pas encore de compte ? » / « S’inscrire sur myweli.com » → the browser at `/pro/inscription` | Nothing |
| `provider_not_found`, and the last invitation declined | The sentence, with the link below it | The sentence, unchanged. Nothing to tap |

**No new copy on the login screen.** No replacement line, no privacy link, no
« contactez-nous ». It is the screen Apple has now cited twice. The widget tests hold
every line of text on it, step by step, on both platforms (§10).

### 4.2 What each step offers

Exactly this, and it is what the widget tests pin (§10):

| Step | Actions |
|---|---|
| Options | « Continuer avec Google », « Continuer avec Apple » (iOS only, `_showApple`), the e-mail field, « Continuer avec e-mail » |
| Code | The code field, « Se connecter », « Renvoyer le code » (disabled during its cooldown, so the tests read no tap on it), « Changer d’e-mail » |
| Invitations | « Rejoindre », « Refuser » on each card, « Retour » |
| No account (any step that reaches it) | The step's own actions. The sentence is a live region with no button |

The no-account sentence stays exactly as it is (`kNoProAccountMessage`,
[pro-app-login-only.md](pro-app-login-only.md) §4.2):

> « Aucun compte MyWeli Pro n’est associé à cette adresse. Si votre salon vous a
> invité, connectez-vous avec l’adresse qui a reçu l’invitation. »

**This is a dead end on purpose.** No guideline asks for a sign-up path, and Apple
has now asked twice for its absence. The store description says who the app is
for (§7). Communication outside the app is not touched: e-mails, the website, a
salesperson.

### 4.3 What leaves the code

Each removal confirmed by `grep` before it goes:

- `pro_login_screen.dart`: the `AuthSwitchPrompt`, the `SizedBox` above it and
  their comment; the imports of `app_config`, `external_link` and
  `auth_switch_prompt` (nothing else in the file uses them); the sentence of the
  class doc that describes the link.
- `core/config/app_config.dart`: `proSignUpUrl` and its doc.
- `widgets/common/auth_switch_prompt.dart`: deleted. The login was its only caller.
- `core/constants/failure_messages.dart:19-20`: the comment said the link « does
  that, once, for everyone ». It now says nothing on the screen points to a sign-up.

Stays: `kNoProAccountMessage`, `openExternalUrl` (About, Profil), `web/app/pro/inscription`
(the web's own sign-up), `pro_router.dart:42-44` (still true).

### 4.4 Layout

The scroll view's padding is `AppTheme.spacingL`, and `InlineFeedback(null)` is a
`SizedBox.shrink`. So the `SizedBox(height: spacingL)` that separated the prompt
goes with it: the form ends on its last control plus the scroll padding, the same
distance on all sides, with no stray gap. The one baseline that shows the screen
(`pro_login_w360_x2`) must show this, and is read by eye (§10). A new sentence in
`InlineFeedback` keeps its own `spacingS` above.

### 4.5 States & edge cases

- **Old builds**: 698 and earlier keep the link. They are TestFlight or the closed
  test only; nothing public shows it, and `/pro/inscription` keeps working.
- **Accessibility**: one fewer control on the first screen. Nothing else changes;
  the screen's width and 200 % tests stay, with another proof string, and now run on iOS
  as well as Android (`auth_layout_test.dart`), so that they measure « Continuer avec
  Apple ».
- **Long French, 360 dp, 200 %**: the defect `AuthSwitchPrompt` fixed (149 px past
  a 360 dp screen, `mobile-a11-width.md`) leaves with the widget. Register row 65
  of `SYSTEM.md` §21 is history and stays.

## 5. The web slice (decision 3)

**Exactly these five paths**, the five the app opens, two of which are also App
Store Connect's Support and Privacy URLs: `/support`, `/politique-confidentialite`,
`/cgu`, `/mentions-legales`, `/suppression-compte`.

**Why these five and no others.** They are all the pages of our site the binary
holds (`AppConfig`'s five getters, §10's guard), and they cannot leave it: privacy
(5.1.1(i)) and support (1.5) are required, the deletion page is what the stores ask
for, and CGU and mentions légales are the owner's call (§14). From each of them,
sign-up was one tap away and the offers one screen further (§2 finding 3), which is
what « any other links to your site that could indirectly provide access to external
purchase mechanisms » describes. No other page is in the binary or on the listing, and
those are where salons look for the door, so they keep it.

**What the owner accepted.** A salon reading one of these five pages loses the shortcut
to its Espace pro and to sign-up. It goes through the logo and home's band instead (§13).

| On those five | Before | After |
|---|---|---|
| Header | « Espace pro » → `/professionnels` (from `sm` up) | Gone, at every width. Logo → `/`, the bell and « Mon compte » stay |
| Footer | Group « Professionnels »: « MyWeli Pro pour les salons », « Inscrire mon salon », « Connexion Espace pro » | Gone. The legal and social groups stay |
| Breadcrumb | « Accueil » → `/` | Unchanged |
| `/support` body | « Mise en ligne, équipe, offre et facturation. Indiquez le nom du salon. » | « Mise en ligne et équipe. Indiquez le nom du salon. » |

**Every other page is unchanged**, including `/`, `/professionnels` and `/connexion`.
The `/support` wording changes for everyone, since it is that page's body.

**The bodies, read for this spec, need nothing else.** No link to `/pro/*` or
`/professionnels` and no price in any of the five. Their links go to `/`, to each other,
to `/mon-compte` and `/mon-compte/donnees` (the client's account), and to `mailto:` and
`wa.me`. The sentences about professionals (CGU §7, the privacy policy, the deletion page)
are about data and duties, and name no offer. **No legal wording changes here**: the privacy
policy's text needs the owner's approval before it goes live (D3), and this slice has no
need to touch it.

**Left alone, knowingly:**

- **« Mon compte » in the header.** Signed out it lands on `/connexion`, which keeps its
  footer group, so it is the same distance from sign-up as the logo. Decision 3 keeps both.
- **The install banner.** It shows on the five when a store URL is configured, and leads to
  a store listing, not to our site. Decision 3 does not name it.
- **Home's band** (`ProBand`) only renders on `/`.
- **The layout's script chunk.** A client leaf means `PRO_LINKS` and the header's link are in a
  JavaScript file every page loads. No anchor, no text and no byte of the HTML carries them on
  the five; a reviewer would have to read the bundle.

### 5.1 How

- One list and one predicate, `web/lib/storeLinkedPages.ts`: `isStoreLinkedPage(pathname)`,
  exact match on the five, whatever trailing slash, query or percent-encoding it is handed
  (the server answers `/%63gu` with `/cgu`, and the links came back on hydration). Not a prefix. Its
  comment says why (this spec) and that the mobile half is `AppConfig`'s five getters.
- **Header**: `SiteChrome` is already a client component reading `usePathname`; it passes one
  prop to `Header`, whose default keeps « Espace pro ». Not rendered, rather than hidden by
  CSS: a hidden link is still in the HTML a reviewer's tools read.
- **Footer**: `SiteFooter` stays a server component. Its comment refused a hydration boundary
  « to hide four links »; that reason yields to Apple's sentence, and the comment says so. The
  three groups move to one small client leaf, `FooterGroups`, which reads `usePathname` and
  holds `PRO_LINKS` itself. The legal and social lists arrive as props, rendered on the server,
  the way `FooterMark` takes its wordmark.

**Two traps, both of which the deployed-artifact check must catch:**

1. **The links must not travel to these pages as props.** Passing the rendered group
   as `children` to a client wrapper serializes every `href` into the page's RSC
   payload: no visible link, but `/pro/inscription` in the HTML of the page that
   claims not to have it. The leaf holds the list, so the check reads the raw HTML as
   well as the anchors.
2. **`lg:pt-xxl` belongs to the group.** The legal and social groups drop by the
   height of the salons' title so that all three lists start on one line. With the group
   gone that drop is a stray gap, and the two groups start at the columns' top. It is why
   one leaf holds all three: the drop has to know whether the title is there. They keep
   their columns (`lg:col-span-4`), so they stay on the site's grid, and the third is empty.

The pages stay static: no `headers()`, no `cookies()` in the layout, which would make
every page dynamic to hide four links. `usePathname` renders on the server for a
static page, so the HTML a `curl` reads must already be clean; that is the claim to
check, not an assumption. It also moves on a client navigation, which a server-side check
would not: a visitor who arrives on `/` and follows « Conditions d’utilisation » sees the
links go, and back.

Update `web-pro-access.md` P1 and P2 (the door has five exceptions) and the header's
comment in the same PR. `Header`'s and `SiteFooter`'s tests in
`web/tests/pro-access.test.tsx` keep proving the default.

### 5.2 Web tests, red first

- **Unit**, `web/tests/store-linked-pages.test.tsx`:
  - the predicate: each of the five with a trailing slash, a query and percent-encoding, and
    controls on each side (`/`, `/professionnels`, `/cgu/x`, `/supports`, `/pro/connexion`, a
    malformed `/%zz`). An exact-match bug is the realistic one;
  - **the server's render** (`renderToString`) of the chrome, the page and the footer, for each
    of the five: no link to `/professionnels`, `/pro/inscription`, `/pro/connexion`, the logo and
    breadcrumb go home, the legal and social groups remain. Control: `/` and `/recherche` have
    all three;
  - each of the five, rendered: no « facturation », « offre », « abonnement », « tarif » or
    « FCFA ». « prix » is allowed, because the CGU speak of a salon's own prices;
  - the drop: `lg:pt-xxl` beside the group, none without it;
  - the render table against the module, so that a page added to the list cannot stay unread.
- **The cross-surface test**, in the same file, reads the Dart: every `'$siteBaseUrl/…'` in
  `mobile/lib/core/config/app_config.dart` is in the five and every one of the five is there; any
  other use of `siteBaseUrl`, in that file or anywhere in `mobile/lib`, and any other `myweli.com`
  string but the API's host, in any case and with adjacent literals joined, fails. **So a new app link to the site fails CI until it is classified**,
  on the consumer app as well as Pro. CI's web job has no path filter, so it runs on a mobile-only PR.
- **e2e**, `web/tests/e2e/store-linked-pages.spec.ts`, at an iPad width and a phone width, on the
  built app:
  - on each of the five, **the raw HTML** has none of the three paths or the words of the links
    (trap 1), and **every anchor on the page** has none of the three, so that a sign-up link added to
    a body fails too; no hydration error; the logo and breadcrumb go home; the four legal links and
    the social group remain. Control: `/` and `/recherche`;
  - `/cgu/`, `/cgu?utm_source=x` and `/%63gu` behave as `/cgu`, the last with no hydration error;
  - the file's written-out list against the module;
  - a client navigation from `/` to `/cgu` and back moves the links;
  - at `lg` and on a phone the lists start where the salons' title starts on `/` (trap 2).

*Done, on the local production build against the stub, not on myweli.com:* the five answer 200,
statically, with 0 hits for the three paths, « Espace pro » and « facturation » in the HTML read with
an iPad user agent; `/`, `/recherche`, `/connexion` and `/professionnels` still have them. First Load JS
is unchanged on the five (132 kB). Looked at from 375 to 1920: the header ends on « Mon compte », the two
groups sit under the wordmark, and the third column is empty. Red first and mutations: the commit messages.

## 6. The review notes and the reply

`app-store-forms.md` §8 stays the one paste block, and its weight is recounted
(`app_review_notes_test.dart` fails if the « Poids » sentence lies). **The owner
approves the wording**; nothing is pasted before that.

Three passages change, now in the block. They are still drafts until that approval:

- **SUBSCRIPTION**: « MyWeli Pro is a free app for salons that already have a MyWeli
  account. There is no purchasing in the app and no button, link or instruction to
  buy or register elsewhere: Profil > « Mon abonnement » only shows the salon's current
  plan and its status. A new salon's free trial starts automatically when the salon goes
  live; nothing is chosen or bought in the app. » No guideline number.
- **ACCOUNT DELETION**, last sentence: « Any other account is deleted at that step; if it
  has upcoming appointments, the app first asks to finish or cancel them. » No instruction
  to register anywhere.
- **SALON ACCOUNTS** (the sentence on the pages joins the audit's draft, since §5 removes the links): « The app only signs in to existing salon accounts, with an e-mail
  code, Apple or Google. It has no registration, no registration link and no way to add a
  salon; salon accounts are created outside the app, on the MyWeli website. An identity
  with no account is told « Aucun compte MyWeli Pro n’est associé à cette adresse. » Team
  members invited by their salon join it from the sign-in screen. The app opens our website
  only for its support and legal pages (Profil > « Aide & Support » and « À propos »), and
  those pages carry no registration link. Please use the demo account above to see a
  populated salon. »

**« those pages carry no registration link » is true only once §5 is live and checked**
(§12 step 2). It says what those pages carry. It does not say the site is out of reach,
because the logo still goes home, and the notes must not imply otherwise.

Also out of the notes, the §13.2 reply and every other text sent to Apple: the number
3.1.3(f). **The Resolution Center reply** is a new §13.2 block, drafted for the owner,
sent by the owner, with the real `<BUILD>` and only true sentences (2.3.4: replaced with
full-screen captures, text overlays and an end frame saying an account is required).
**TestFlight's « What to Test »** loses the sign-up wording. **The IPA check** (§11.3)
flips: « S’inscrire sur myweli.com », « Pas encore de compte » and `/pro/inscription` move
to the « gone » list; `kNoProAccountMessage` stays a witness, and the five paths join it; any sixth
`https://myweli.com…` in the binary fails it. *Read on an unsigned build of this branch, with the API's
defines: `OK`; the binary names the five pages and the API, nothing else of ours. Not the signed IPA, which
is still step 4.* Build 698's record stays as history. **The prepared answer about Sign in with Apple** (§13.3) names the
new build's sentence and `<BUILD>`, since B0.14 is on `main` and ships in this build, and it now says
Apple sign-in must be tried on the build first: this focused pass does not cover it. **`app_review_notes_test.dart`**
holds it: no 3.1.3(f) in anything sent, no sign-up link or instruction in the notes, the sign-in steps
in the words of the login screen, the description's counts, the IPA lists, no build number written in
a reply.

## 7. The store listing (decision 4)

Two edits to the description, the owner's text, done in `app-store-forms.md` §4:

1. « votre page publique sur myweli.com se remplit depuis l'app. » becomes « votre page
   publique se remplit depuis l'app. »
2. Add, with no link: « MyWeli Pro s’adresse aux salons qui ont déjà un compte MyWeli et à
   leur équipe. » It follows the first sentence, on the same line: what the app is, then who it
   is for. 1,061 characters, 1,102 bytes, 18 lines.

Counts in `app-store-forms.md` §4 (the table's row and the line under the block) and §13.1 are recounted by script. Name, subtitle,
promotional text, keywords, copyright, support and privacy URLs and the 16 stills do not
change. **The marketing URL stays empty** (recorded empty on 2026-10-13); §5 of the forms
still proposes `https://myweli.com`, and that row is corrected. **The Play listing keeps its text**:
decision 4 is about the App Store, and Play's is saved in its console. It was word for word the same,
and `play_store_forms_test.dart` held that, so the guard now allows exactly these two edits and nothing
else. Whether Play takes them is the owner's call (§16); the login's dead end is the same on Android.

## 8. The film (decision 2)

- **File**: `build/app-store/pro/preview/candidate-full-bleed/preview-full-bleed.mp4`, sha256
  `b34bac542f99579a3d94e0693b3f75437f516202d27666c77f6280d5c286e724` (recomputed for this
  spec), 886×1920, 862 frames, 28.733 s. The same storyboard and takes as the framed cut,
  rendered with `--frame full-bleed`. The tool's 25 file checks pass; they read format and
  masks, not App Review's rules, and the rejected film passed the same 25.
- **Poster**: 00:00:13:00. Set at reservation, read back: Apple ignored the time sent on the
  deprecated route (`app-store-forms.md` §13.1).
- **Both iPhone slots.** The framed file sits in `IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE` and
  `..._LARGE_PROFILE`. A placement cannot be edited: delete, create, read back. **Every size is
  read in « View All Sizes in Media Manager » before « Add for Review »**, as Apple's message
  warns. A framed copy left in any size repeats what Apple just refused, so this is a gate and not a nicety.
- **Media before submission**: Rejected allows media edits, Waiting for Review does not.
- **The storyboard says full-bleed.** First written here as « the storyboard file stays as it is »;
  changed the same day so that the committed tool builds what goes in the slots. `film.frame` is the one
  value changed, with a dated `_frame` note and a self-test, watched red. **The candidate stays the file to
  upload.** Rendered again from the commit, it is frame-identical and not byte-identical: 22 bytes differ,
  every one of the 862 frames decodes the same (`pro-app-preview.md` §0.6, which records the rest).

## 9. Architecture, contract, data, security, performance

- **API, data model, OpenAPI**: nothing. No endpoint or migration. The server's registration
  endpoints stay for the web.
- **Layers**: a screen loses a widget; `AppConfig` loses a getter. No service or provider moves.
- **Security**: nothing new is trusted or exposed. No threat-model row: no trust boundary moves.
- **Performance**: the app sheds a widget. The web gains one small client island on every page
  and a prop; the CWV gate decides, and the pages stay static.
- **V1 scope**: nothing added to any surface.

## 10. Testing — red first

Every new test is seen failing on the old code, and that is recorded in the commit message.
Comments are stripped before any source pin matches (`stripDartComments`). Mutations run on a
COPY of committed work.

**Mobile.**

- **Source pin**, in `test/widget/pro_login_only_test.dart`, over the Pro closure: no « S’inscrire »,
  « Pas encore de compte », `proSignUpUrl` or `/pro/inscription`, in any apostrophe spelling. The
  widget's file is gone.
- **The site-link guard**, `test/infra/pro_site_links_test.dart`, over the closure computed from
  `lib/main_pro.dart`:
  - the `AppConfig` getters built on `siteBaseUrl`, directly or through one another, that Pro uses are
    **exactly** `privacyUrl`, `termsUrl`, `legalNoticeUrl`, `accountDeletionUrl`, `supportUrl`, and each
    points to its path, whose page exists in `web/app`;
  - `app_config.dart` names `siteBaseUrl` exactly six times, itself and the five, so a block body, a
    top-level getter or a helper in that file is one too many, used or not;
  - each of the five is read once in the closure, as the whole argument of
    `openExternalUrl(context, AppConfig.x)`, so a getter re-pointed through `Uri.resolve`, a ternary or a
    local copy fails;
  - `siteBaseUrl` itself is read nowhere else;
  - no string in the closure contains `myweli.com` but the site's base itself, **once** (`siteBaseUrl`'s
    default; `api_constants.dart` is outside the closure, and the API's host is a build define);
  - the pages that sign up, sign in or sell, and `/pro/salons/nouveau`, `/connexion` and `/mon-compte`,
    appear as no path literal, joined literals included;
  - no sentence says « notre site », « site web », « navigateur » and the like: an instruction needs
    no domain;
  - the three functions that leave the app are called from a known list of files, counted; `url_launcher`
    is imported by exactly four files, because its `Link` widget uses none of the three; and there is no
    web view dependency;
  - `ios/Runner` and `android/app/src` name no `myweli.com`.
- **Widget**, `pro_login_only_test.dart`, on iOS and Android: each of the three steps offers exactly
  the actions of §4.2, read from the semantics tree so that a reworded link or an `InkWell` cannot
  pass, and says exactly its lines of text, read from every paragraph, so that a sentence with no tap
  cannot either (§4.1); the no-account path shows its sentence, offers nothing new and opens nothing. **Control**: the
  fake browser does hear a real `openExternalUrl`, or « opened nothing » proves nothing.
- **Updated**: `pro_login_only_test.dart` (the link group goes), `pro_login_invitations_test.dart:130`
  (`findsNothing`), `a11y/auth_layout_test.dart` (another proof, the prompt's own tests go, both platforms),
  `golden/pro_screens_golden_test.dart:582-583`.
- **Golden**: `pro_login_w360_x2` changes, on Linux only (the « Goldens — regenerate » workflow). Every
  changed PNG is looked at; the rest are compared byte for byte and not committed. `consumer_login` must
  not move. *Done: 57 of 58 byte-identical; the one that changed differs only in the prompt's rows, and
  the form now ends at the bottom of its last button.* It is Android: « Continuer avec Apple » is not in it.
  The width test measures iOS, and nothing photographs it.

**What the guard cannot see, by class:**

| Class | Why it is blind | What covers it |
|---|---|---|
| A URL the server sends (`update_url`) | It is data, not source. Seeds: Play URL, NULL for iOS (`migrations.dart:892-899`); the admin service does not check the host | Review; decision 4 of B0 (no `updateUrl` before release); §14 |
| Text the server sends (push, a refusal's `message`) | Same | The app never shows a server's `message` (`app-failure-messages.md`); the subscription pushes carry no link |
| A call that is not one of the five re-pointed elsewhere (`tel:`, `wa.me`, a map, the store) | The inventory counts those calls; it does not read their URLs | Our domain written whole is seen wherever it is. Built from pieces in such a call, only the IPA check reads it (`app-store-forms.md` §11.3), by hand on the IPA. A third party is a judgement for review |
| A new package that opens a page by itself | The importers' pin knows `url_launcher`, the dependency check knows the word « webview » | Review of `pubspec.yaml` |
| A sentence that points at the site past the word list | A word list is a word list (« notre site », « site web », « navigateur », …) | On sign-in, the widget tests hold every line and every action, whatever they say. Elsewhere, review: « depuis un ordinateur » on the subscription screen passes everything, and that limit is accepted |
| What the web pages carry | No mobile test reaches the web | §5.2 and the post-merge `curl` |
| A new link to the site in the **consumer** app | The guard reads Pro's closure only | §5.2's cross-surface test reads `app_config.dart` and all of `mobile/lib` |

**Web**: §5.2.

**The film**: `test_scenes.Storyboard.test_the_film_is_full_bleed_because_apple_refused_the_framed_one`, watched red on the old
storyboard. **The texts**: the last group of `mobile/test/infra/app_review_notes_test.dart` (§6), and `play_store_forms_test.dart`, which
holds Play's description to the App Store's but for §7's two edits. They read documents and source. Whether a sentence is true of the build
is the IPA check's and the device pass's to say.

## 11. The device pass (decision 5)

« Focused pass » — on the build going to review, from TestFlight, on a real iPhone. It replaces
decision 2's full list (`app-store-forms.md` §11.6 and the post-587 list) **for this build**; those
stay on the list for 0.0.2.

1. **The demo sign-in, exactly as the notes say.** « Espace Pro », `revue@myweli.test` in « Votre
   e-mail », « Continuer avec e-mail », the code in « Code à 6 chiffres », « Se connecter ». Lands on
   « Maison Nala ».
2. **No link on Connexion**: options and code. An address with no account **that really receives the code**
   (the sentence only comes after the code is verified), or a Google or Apple identity with none: the sentence,
   nothing to tap.
3. **A session left past 15 minutes** (the access token's life, `backend/lib/src/auth/tokens.dart:16`).
   Comes back, loads, still signed in. What this proves is the silent refresh after expiry, in a signed
   build. `main_pro.dart` mounts no plain `AuthProvider`, so of B9.13 it reaches only the shared code
   (`RefreshingHttpClient`, `AccountScope`).
4. **Restart, then sign-out.** Kill and reopen: restored. Sign out: Connexion. Reopen: still signed out.
5. **One run on an iPad**, simulator if the owner has no iPad, since both rejections name one. Steps 1 and
   2 in iPhone compatibility mode. The IPA and TestFlight do not install on a simulator, so that run is a
   separate debug build against production; the command is in `app-store-forms.md` §11.6, and the owner runs
   it or asks Claude to. A simulator run proves the layout, not the signed build; say which was used.

**It does not see, and this is not the owner's choice:** a session the server refuses (only the widget tests
cover it, and a device cannot cheaply provoke it), and a second account on the same phone.

Reported by the owner, dated in §11.6: nothing in this repo observes a device.

## 12. Rollout

**The web and the app land together, in one PR. The web is live at merge; the build comes after merge.**
Nothing is merged, uploaded, pasted or sent except by the owner's go.

| # | Step | Who |
|---|---|---|
| 1 | The PR: this spec, the app, the web, the notes block, CI green, goldens on Linux | Claude, then the owner's review |
| 2 | Merge. **The web is live.** `curl` the five paths with an iPad user agent and read them: no `/professionnels`, `/pro/inscription`, `/pro/connexion`; control: `/` still has them | Owner merges; Claude checks |
| 3 | Hold other merges (dependabot included) until the build is made. Build from `main`: `./tool/release_build.sh ios pro`, which refuses a dirty tree or a HEAD that is not `origin/main`. Version stays 0.0.1; the build number is `git rev-list --count HEAD`, so `<BUILD>` is read from the IPA, not predicted | Claude, on the owner's go |
| 4 | Read the IPA (§11.3, flipped: §6). Upload, wait for `VALID` | Claude, on the owner's go |
| 5 | The device pass (§11) | Owner |
| 6 | App Store Connect, in this order while the version is editable: the film in both slots, read back in Media Manager (§8); the description (§7); the build; the notes, wording approved (§6) | Owner approves; API or owner |
| 7 | The Resolution Center reply and « Add for Review » | Owner only |
| 8 | While in review: B0.1 applies (no `DEMO_PROVIDER_CODE` rotation, no Cloudflare change, same-day answers) | Both |

**No production backend deploy** (decision 47): no step needs one, and the next one switches the Apple keys
on, whatever its reason. **Web merges are production deploys**, so during review the five pages are not edited.

The stale-doc sweep (BACKLOG, LAUNCH, PRD, `pro-app-login-only.md`'s body) is on this branch too, with §8's notes, the
tests and this spec. So one PR carries it all.

## 13. Accepted risks and the contingency

**Accepted by the owner, knowingly:**

- **The end card.** 2.5 s of paper, mark and disclosure, not a capture, on the same paper the reviewer just objected
  to around the capture. For it: Apple's previews page names the end frame as a place for disclaimer copy, and the
  rejection names only framing on a film that carried this card.
- **« Total ».** The take says « Total » on Revenus; the build says « Total réalisé » and « Rendez-vous terminés ». A
  re-render cannot fix a take. The retake is for 0.0.2.
- **A third rejection is possible**, and the review clock is days. The audit's pick was to ship no film; the owner chose
  this one after hearing that.
- **Salon visitors on the five pages lose the salon links.** The logo still goes home, and home's band still says
  « Vous êtes un salon ? ». So sign-up stays two taps from each of the five (the logo, then « Inscrire mon salon » in
  home's footer) and one from home. Apple may read that too; removing it hurts every web
  visitor and the owner kept it.

**Known, and not acted on:**

- **5.1.1(ix)**, KYC under an individual seller: uncited twice. Fallback decided (B0.6: hide KYC and the deposit switch on
  iOS if cited).
- **5.1.1(v)**, a reviewer cannot see a real deletion: the demo account refuses it by design. A recording taken during the
  device pass can be attached, the owner's choice.
- **The stills** show « Revenus » and « Total » from before those labels changed (stills 3, 8). 2.3.3 asks that they follow
  the UI; they wait for 0.0.2.

**The contingency.** If Apple challenges the model itself (a plan bought outside the app governs the app, and 3.1.3(f) does not
fit): **« Mon abonnement » is hidden, or store billing is opened. A decision for then**, the owner's, and not taken now. Hiding
the row is small; store billing is weeks (`app-store-forms.md` §2.4 (b)). No sentence sent to Apple before that argues the point.

## 14. What is NOT changed, and why

The audit's overkill list. Each was considered and left out on purpose:

- **The logo and breadcrumb home links** on the five pages (decision 3). Home is one tap from sign-up and the five pages two, and removing them hurts every visitor. The direct links are the exposure.
- **Bare `/app/*` copies of the legal pages.** New URLs in the binary and in App Store Connect, for what the path rule covers.
- **The end-card tool change, its self-tests and mutations, and the S4 retake.** For 0.0.2.
- **A staged reshoot** for « Total », dates, chips and blank mask rows. Not approval issues.
- **The 16 stills.** 2.3.3 allows their frame; 2.3.4 concerns previews.
- **Hiding or renaming « Mon abonnement », hiding KYC.** Both harm owners to answer a citation Apple has not made.
- **CGU, Mentions légales and the About deletion row.** Once the pages are clean they cost nothing and they build trust. The native deletion stays unconditionally (5.1.1(v)).
- **A privacy link on the login screen.** The very screen Apple just cited; reachable after sign-in has not been cited.
- **A second disposable reviewer account.** Backend work and a deploy decision 47 forbids.
- **Never-rendered strings (`trial_used`, `reseau_required`) and the dead `openWhatsApp`.** Unreachable.
- **An iOS-only branch.** One behaviour on both platforms; Google did not ask, and the owner chose.

## 15. Definition of done

- [ ] This spec committed before code, indexed in `README.md`, cross-linked from the code it governs.
- [ ] Every new test and guard watched red on the old code, and red under a mutation on a copy of committed work; both in the commit message.
- [ ] `flutter analyze` 0, `dart format` clean, the design-token gates, the full mobile suite once; web lint, typecheck, unit, e2e, build.
- [ ] Goldens on Linux; every changed PNG looked at; the rest byte-compared.
- [ ] Notes wording approved by the owner; weight recounted; no 3.1.3(f) anywhere sent to Apple.
- [ ] After merge: the five pages read live with a control (§12 step 2). The IPA read (§6). The device pass reported (§11).
- [ ] Both iPhone slots read back with the new file and the poster before « Add for Review ».
- [ ] Feature branch and PR. No Claude attribution of any kind. A roadmap entry.

## 16. Open questions

None blocks the build. For the owner, at step 6: the notes' wording, including:

- whether « the separate MyWeli app and myweli.com » stays in the first paragraph. The audit would keep it (consumers booking an
  in-person service, in text that is not public). But the consumer app was not published at the last reading, and production had no
  public salon on 2026-10-28, so a reviewer may find neither;
- « A new salon's free trial starts automatically when the salon goes live », which simplifies decision 68: a first offer chosen on
  the web starts it earlier. It is true of the app;
- whether to attach a recording of a real deletion. « Any other account is deleted at that step » rests on code and tests, and the
  focused pass does not exercise it (§11);
- whether the Play listing takes the description's two edits (§7). It keeps the old text until then.
