# Apple's second rejection of MyWeli Pro 0.0.1 — round 2 (2.3.4, 3.1.1)

| | |
|---|---|
| **Status** | Approved 2026-11-03 (owner: §3, five decisions) · build, upload and resubmission are the owner's go (§12). **The app's half (§4, §10), the web's half (§5), the texts for Apple (§6, §7), the film's storyboard (§8) and the record are merged (#731, squash `713114a5`, 2026-11-03). The web is live and read. Build 719 is built, read, uploaded, `VALID` and in TestFlight** (§12). **That night, in App Store Connect: the full-screen film in both slots, the description, 719 attached, the notes; version 0.0.1 moved from `REJECTED` to `PREPARE_FOR_SUBMISSION`, release `MANUAL`, as it stood then. The owner reports that the focused pass passed on their iPhone (§11).** **2026-11-04: resubmitted at 00:02:00 UTC with build 719, in review (`WAITING_FOR_REVIEW`, release `MANUAL`, per the API); B0.1 applies. Still open: Apple's decision; a green scheduled « Production checks » run after `713114a5` and `7a2c7e15` (the last is 13:16 UTC on 2026-11-03, on `4e78e485`); a successful Apple sign-in on an iPad, unobserved; the production backend deploy after Apple's decision, the one that switches on the Apple keys; the release by hand after approval; merging the docs PR that holds this record.** #732, the `%2F` and `%5C` spellings, was merged and deployed before the submission, and its rendered read is done for one address (§5.1). *Owner-reported on 2026-11-04:* the iPad's demo sign-in and no-account address passed, on a simulator and a debug build, not signed 719 (§11); Media Manager checked and the reply sent, with no order stated against the submission (§12). The backend is not deployed. The owner approved the notes, the description and the reply on 2026-11-03 (decision 77), corrected the description the same day (decision 79), and delegated one clause of the notes (decision 81) |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-04 |
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

*Two more the same day, after the independent check:* decision 79 (« Correct both », the description, §7) and
decision 80 (« Accept it », the pricing page, §13). Both are in BACKLOG §2.

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
to `/mon-compte` and `/mon-compte/donnees` (the client's account), and to `mailto:`. *Corrected on
2026-11-03: this also named `wa.me`. `/support`'s code draws a `wa.me` link only when
`NEXT_PUBLIC_MYWELI_WHATSAPP` is set at build (`web/lib/support.ts`), and a raw read of the five, on 2026-11-03 at 23:53 UTC
with an iPad user agent, found none.* The sentences about professionals (CGU §7, the privacy policy, the deletion page)
are about data and duties, and name no offer. **No legal wording changes here**: the privacy
policy's text needs the owner's approval before it goes live (D3), and this slice has no
need to touch it.

**Left alone, knowingly:**

- **« Mon compte » in the header.** Signed out it lands on `/connexion` (« Se connecter ou
  créer un compte », the client's), which keeps its header door and footer group, so it is the
  same distance from salon sign-up as the logo. **Decision 3 names the logo and the breadcrumb,
  not this.** Removing it from the header would not close the route: the privacy and deletion
  pages link to `/mon-compte` in their bodies (legal wording, D3), and the deletion instructions
  need them. So it stays, and what is sent to Apple says only what was verified: no link to salon
  registration (§6). The owner is told with the wording (§16).
- **The install banner.** It shows on the five when a store URL is configured, and leads to
  a store listing, not to our site. Decision 3 does not name it.
- **Home's band** (`ProBand`) only renders on `/`.
- **The layout's script chunk.** A client leaf means `PRO_LINKS` and the header's link are in a
  JavaScript file every page loads. No anchor, no text and no byte of the HTML carries them on
  the five; a reviewer would have to read the bundle.

### 5.1 How

- One list and one predicate, `web/lib/storeLinkedPages.ts`: `isStoreLinkedPage(pathname)`,
  exact match on the five, whatever query, percent-encoding or run of slashes and backslashes at
  either end it is handed, encoded or not. Those are the spellings production answers with the
  page, rendered for the bare path: `/%63gu`, `/cgu%2F`, `/%5Ccgu` and `/%2F/cgu` all answer 200
  with `/cgu`, and a spelling the predicate missed brought the links back on hydration, because
  in the browser `usePathname` reads the address as typed. `/cgu%2Fx`, `/.%2Fcgu`, `/cgu%20` and
  `/cgu%252F` answer a 404, which keeps the links. Not a prefix. **Read on myweli.com on
  2026-11-03: 560 spellings, no disagreement with the predicate.** **Read live after the merge
  on 2026-11-04 (#732, `7a2c7e15`, Chromium; real Safari for one address, below): no salon link and no React error on any
  of the 20 forms, with the controls unchanged.** This follows Vercel: `next start`
  answers the encoded-separator spellings with a 404, so a local build cannot show them. Its
  comment says why (this spec) and that the mobile half is `AppConfig`'s five getters.
- **The `%2F` and `%5C` gap, closed by #732.** *Recorded on 2026-11-04.* The first version went through `decodeURI`, which
  leaves `%2F` encoded and turns `%5C` into a backslash. So `/support%2F`, `/%2Fsupport`, `/support%5C`, `/%5Csupport` and the
  same forms of the other four answered 200 with the canonical page, and the salon links returned after hydration, with React
  errors. Its reach was hand-typing only: the app and App Store Connect use the bare paths. #732 merged at 23:59:03 UTC on
  2026-11-03 as `7a2c7e15`. Its production deployment reported success at 00:01:08 UTC, 52 seconds before the submission's date
  (§12), and the live layout chunk holds the new predicate. A raw read at 00:26 UTC, iPad user agent: the five bare pages,
  `/cgu%2F` and `/%5Csupport` are 200 with 0 hrefs to `/professionnels`, `/pro/inscription` and `/pro/connexion`; the control `/`
  has 3, 1 and 1. **That is raw HTML, which was clean before #732 too, so it does not prove the fix.** Nor does the raw read at
  00:06 UTC, same user agent: the five pages show 0 of `/professionnels`, `/pro/inscription`, `/pro/connexion` and « facturation », the controls `/` 4, 1, 1 and `/connexion` 2, 1, 1, and `/support%2F`, `/%2Fsupport` and `/support%5C` are also 0. (`/` reads 4 occurrences of `/professionnels`, 3 of them hrefs, at 00:40 UTC, which accounts for the 4 here and the 3 at 00:26.) **The hydrated page is what #732 fixes, and its
  rendered read is done for one address:** real Safari on the iPad Air 11-inch (M3) simulator at 00:06 UTC opened `/support%2F` and, after hydration, the header ends on « Mon compte » with no « Espace pro ». The frame shows the header, the body and the top of the footer's wordmark, not the footer's links. Before #732 the same address showed the salon links after hydration, which is the control. The other spellings were read raw in that pass; all 20 forms are read rendered in Chromium, above (#733). A read is allowed
  during review; a web edit is not.
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
  - the predicate: each of the five with a trailing slash, a query, percent-encoding and an
    encoded slash or backslash at either end, and controls on each side (`/`, `/professionnels`,
    `/cgu/x`, `/supports`, `/pro/connexion`, a malformed `/%zz`, and `/cgu%2Fx` and the other
    spellings production answers with a 404). An exact-match bug is the realistic one;
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
  - `/cgu%2F`, answered as production answers it, because `next start` gives a 404: no link and no
    hydration error. `/cgu%2Fx`, `/x%2Fcgu` and `/supports%2F` are 404s and keep the links. Whether
    production still answers `/cgu%2F` that way is only read on the live site;
  - the file's written-out list against the module;
  - a client navigation from `/` to `/cgu` and back moves the links;
  - at `lg` and on a phone the lists start where the salons' title starts on `/` (trap 2).

*Done, on the local production build against the stub, not on myweli.com:* the five answer 200,
statically, with 0 hits for the three paths, « Espace pro » and « facturation » in the HTML read with
an iPad user agent; `/`, `/recherche`, `/connexion` and `/professionnels` still have them. First Load JS
is unchanged on the five (132 kB). Looked at from 375 to 1920: the header ends on « Mon compte », the two
groups sit under the wordmark, and the third column is empty. Red first and mutations: the commit messages.
*Read on myweli.com after the merge, on 2026-11-03: §12, with its limits.*

## 6. The review notes and the reply

`app-store-forms.md` §8 stays the one paste block, and its weight is recounted
(`app_review_notes_test.dart` fails if the « Poids » sentence lies): **3,991 bytes, 3,926 characters, 31 lines**,
counted by script, under the 4,000 limit. *3,937 bytes and 3,872 characters were right for the text decision 77
approved, before decision 81's clause.* **The owner
approves the wording** (done on 2026-11-03, decision 77); nothing is pasted before §12 step 2.
*Step 2 is done. §12 step 6 ran after the owner's reported pass: the notes are in App Store Connect, read back identical
(§12).*

Four passages change, now in the block:

- **SUBSCRIPTION**: « MyWeli Pro is a free app for salons that already have a MyWeli
  account. There is no purchasing in the app and no button, link or instruction to
  buy or register elsewhere: Profil > « Mon abonnement » only shows the salon's current
  plan and its status. A new salon's free trial starts automatically when the salon goes
  live; nothing is chosen or bought in the app. » No guideline number.
- **USER CONTENT**: « …moderated by MyWeli: a salon reports a review with « Signaler » under « Avis » (not visible
  on the demo salon, which has no reviews), customers report reviews from the MyWeli app, administrators can hide a
  review or suspend a salon… ». That path is in this binary (#678, already in 698); the other one needs an
  app the reviewer cannot reach. *2026-11-03: the clause in brackets is decision 81, the only difference from what
  decision 77 approved (§16). The demo salon having no review is owner-reported (§11). Read on 2026-11-04:
  `backend/lib/src/demo` writes no review, so the weekly reset adds none.*
- **ACCOUNT DELETION**, last sentence: « Any other account is deleted at that step; if it
  has upcoming appointments, the app first asks to finish or cancel them. » No instruction
  to register anywhere.
- **SALON ACCOUNTS** (the sentence on the pages joins the audit's draft, since §5 removes the links): « The app only signs in to existing salon accounts, with an e-mail
  code, Apple or Google. It has no registration, no registration link and no way to add a
  salon; salon accounts are created outside the app, on the MyWeli website. An identity
  with no account is told « Aucun compte MyWeli Pro n’est associé à cette adresse. » Team
  members invited by their salon join it from the sign-in screen. The app opens our website
  only for its support and legal pages (Profil > « Aide & Support » and « À propos »), and
  those pages carry no link to salon registration. Please use the demo account above to see a
  populated salon. »

**« those pages carry no link to salon registration » is true only once §5 is live and checked**
(§12 step 2; *checked on 2026-11-03, §12*). It says what those pages carry. It does not say the site is out of reach:
the logo still goes home and « Mon compte » reaches the client's sign-in (§5), and the notes must
not imply otherwise. The review measured that route, which is why the sentence names salon
registration and not « a registration link ».

Also out of the notes, the §13.2 reply and every other text sent to Apple: the number
3.1.3(f). **The Resolution Center reply** is a new §13.2 block, drafted for the owner,
sent by the owner, with the real `<BUILD>` and only true sentences (2.3.4: replaced with
full-screen captures, text and touch overlays, and an end frame saying an account is required;
the notes « describe how accounts work in the app », since they say nothing of the film).
**TestFlight's « What to Test »** loses the sign-up wording. **The IPA check** (§11.3)
flips: « S’inscrire sur myweli.com », « Pas encore de compte » and `/pro/inscription` move
to the « gone » list; `kNoProAccountMessage` stays a witness, and the five paths join it; any sixth
`https://myweli.com…` in the binary fails it. *Read first on an unsigned build of the branch, with the API's
defines: `OK`; the binary names the five pages and the API, nothing else of ours. Then on the signed IPA of
build 719, on 2026-11-03: `OK` on both lists (§12 step 4, `app-store-forms.md` §11.3).* Build 698's record stays as history. **The prepared answer about Sign in with Apple** (§13.3) names the
new build's sentence and `<BUILD>`, since B0.14 is on `main` and ships in this build, and it now says
Apple sign-in must be tried on the build first: this focused pass covers that only if its step 5 runs on the signed
build, on a device signed in to an Apple account (§11). **`app_review_notes_test.dart`**
holds it: no 3.1.3(f) in anything sent, no sign-up link or instruction in the notes, the sign-in steps
in the words of the login screen, the description's counts, the IPA lists, no build number written in
a reply.

## 7. The store listing (decision 4)

Two edits to the description, the owner's text, done in `app-store-forms.md` §4:

1. « votre page publique sur myweli.com se remplit depuis l'app. » becomes « votre page
   publique se remplit depuis l'app. »
2. Add, with no link: « MyWeli Pro s’adresse aux salons qui ont déjà un compte MyWeli et à
   leur équipe. » It follows the first sentence, on the same line: what the app is, then who it
   is for. 1,061 characters, 1,102 bytes, 18 lines at this step.

**2026-11-03, after the independent check: decision 79, « Correct both ».** Two corrections to the same text, the
owner's too. Neither refusal cited them.

3. « Vue journée, semaine, et par membre d'équipe. » becomes « Vue journée et par membre d'équipe. » The journal has
   a strip that picks a day, and no week view.
4. « Conçu pour les réalités d'ici : FCFA, communes, à domicile, réseaux lents et petits téléphones. » loses
   « à domicile, ». The word is at 0 in the binary, and in `mobile/lib` only in a comment.

**1,039 characters, 1,079 bytes, 18 lines**, counted by script from the block. *Written to fr-FR in App Store Connect on
2026-11-03, read back identical; keywords, promotional text, support URL, marketing URL (empty) and locale unchanged.*

Counts in `app-store-forms.md` §4 (the table's row and the line under the block) and §13.1 are recounted by script. Name, subtitle,
promotional text, keywords, copyright, support and privacy URLs and the 16 stills do not
change. **The marketing URL stays empty** (recorded empty on 2026-10-13); §5 of the forms
still proposes `https://myweli.com`, and that row is corrected. **The Play listing keeps its text**:
decision 4 is about the App Store, and Play's is saved in its console. It was word for word the same,
and `play_store_forms_test.dart` held that, so the guard now allows exactly these four edits and nothing
else (two until decision 79), any of them taken being a repair. Whether Play takes them is the owner's call (§16); the
login's dead end is the same on Android.

## 8. The film (decision 2)

- **File**: `build/app-store/pro/preview/candidate-full-bleed/preview-full-bleed.mp4`, sha256
  `b34bac542f99579a3d94e0693b3f75437f516202d27666c77f6280d5c286e724` (recomputed for this
  spec), 886×1920, 862 frames, 28.733 s. The same storyboard and takes as the framed cut,
  rendered with `--frame full-bleed`. The tool's 25 file checks pass; they read format and
  masks, not App Review's rules, and the rejected film passed the same 25.
- **Poster**: 00:00:13:00. *2026-11-03, as it went:* Apple ignored the time sent at reservation and at commit, and set
  00:00:05:01; a PATCH after processing set 00:00:13:00, read back on both slots (`app-store-forms.md` §13.1).
- **Both iPhone slots.** The framed file sat in `IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE` and
  `..._LARGE_PROFILE`. A placement cannot be edited: delete, create, read back. **Every size is
  read in « View All Sizes in Media Manager » before « Add for Review »**, as Apple's message
  warns. It is a site view with no recorded API equivalent, so whoever does it reads it in the site (§12 step 6). A framed copy left in any
  size repeats what Apple just refused, so this is a gate and not a nicety.
- **In App Store Connect, 2026-11-03, 23:49 UTC.** New previews `17000019-5a03-88cb-8118-40e21663fe37` (`IPHONE_67`) and
  `f3000019-5a03-88cb-8114-ec9980fce3b8` (`IPHONE_61`), file `myweli-pro-film-full-bleed.mp4`, 14,309,442 bytes, sha256
  `b34bac54…` checked before upload, `sourceFileChecksum` `543d367a6caf1b1069d0cd62e2246177` read back on both and equal to
  the local file's md5, `assetDeliveryState` and `videoDeliveryState` `COMPLETE`. The framed films
  `eb0e26ae-48f9-4bbf-b8e4-0f9d65c7a041` and `95da9952-95f5-4680-9419-5796e69fc420` were deleted (204) only after both new
  copies were `COMPLETE`. The localization's `/placements` reads 2 `APP_PREVIEW` `ACTIVE` and 16 `APP_SCREENSHOT` `ACTIVE`.
  Route: the deprecated `appPreviews` resources, which worked. **« View All Sizes in Media Manager » was a gate before « Add for Review » and is not observable
  from here. Owner-reported on 2026-11-04: « I checked Media Manager ». The owner did not say whether that came before or after the submission, so no order is stated (§12).**
- **Media before submission**: Rejected allows media edits, Waiting for Review does not. *2026-11-04: the version is
  `WAITING_FOR_REVIEW`, per the API (§12).* *2026-11-03: there was no recorded
  precedent for these edits on a `REJECTED` version with an open submission. Apple accepted them that night (§13).*
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

**The review of 2026-11-03 fooled the guard's first version**, and that is why it reads as above. Five mutants
passed every pin and compiled to a product binary holding the link: a block-body getter, a top-level getter in
`app_config.dart`, a second base literal, a domain built from a const, a getter re-pointed through `Uri.resolve`.
A `Link` widget and a sentence with no tap on the login passed too. Each is red now, and each of the new checks has
a mutation only it catches; the commit that closes that round lists them.

**Web**: §5.2.

**The film**: `test_scenes.Storyboard.test_the_film_is_full_bleed_because_apple_refused_the_framed_one`, watched red on the old
storyboard. **The texts**: the last group of `mobile/test/infra/app_review_notes_test.dart` (§6), and `play_store_forms_test.dart`, which
holds Play's description to the App Store's but for §7's four edits. They read documents and source. Whether a sentence is true of the build
is the IPA check's and the device pass's to say.

**The last two shapes, from the final check on `2b411154`.** Both stayed green on every pin, and both are red now, on a
copy of `8dcf44fa`, analyzer 0, with the baseline green first. A sixth getter built on `termsUrl` in a block body is red on
« the config names each of the five once ». `const SelectableText(…)` on the login is red on all ten scenarios that call
`expectNoPrompt` (five, on both platforms); with the new line taken out of the test, that same mutant passes, so the line is
what catches it.

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
3. **A session left past 15 minutes, cold then warm** (the access token's life, `backend/lib/src/auth/tokens.dart:16`).
   **Two waits, not one:** the token refreshes only on the first refused request (`RefreshingHttpClient.send`), so each run
   uses up the expiry the other needs. **Cold** (decision 78): kill the app, wait past 15 minutes, reopen; « Maison Nala » opens
   signed in and loads, the several requests at once that raced in production on 2026-10-11. **Warm:** leave it in the
   background past 15 minutes, come back, open « Clients » from « Accueil »; the list loads, still signed in. That tap matters:
   coming back alone sends the server nothing, and would prove nothing. What this proves is the silent refresh after expiry, in a signed
   build. `main_pro.dart` mounts no plain `AuthProvider`. Of B9.13 it reaches `RefreshingHttpClient` and `AccountScope`,
   `notifications_provider.dart` and `provider_provider.dart` (both mounted by `main_pro.dart`), `api_auth_service.dart`
   and `session_ended_notice.dart`. *Corrected on 2026-11-03: this said « only the shared code (`RefreshingHttpClient`,
   `AccountScope`) », which was too narrow.*
4. **Restart, sign-out, sign-in.** Kill and reopen: restored. Sign out: Connexion. Reopen: still signed out. Sign in
   again: « Maison Nala » reloads (decision 78: a way back in after a way out, in one process, was not run).
5. **One run on an iPad**, simulator if the owner has no iPad, since both rejections name one. Steps 1 and
   2 in iPhone compatibility mode, and one tap on « Continuer avec Apple » (decision 78, B0.14's path, which a device that was
   almost certainly Apple's hit with error 1000 on 698). Note which comes: a sign-in, « Aucun compte MyWeli Pro… », or B0.14's
   sentence. Cancelling Apple's sheet shows nothing, by design, so go through with it. The IPA and TestFlight do not install on a simulator, so that run is a
   separate debug build against production; the command is in `app-store-forms.md` §11.6, and the owner runs
   it or asks Claude to. A simulator run proves the layout, not the signed build; say which was used. « works on build
   <BUILD> » in the prepared answer (§6) needs the signed build, on a device signed in to an Apple account.

**Two additions for the owner (2026-11-03), and not in TestFlight's « What to Test »**, which is already written in
App Store Connect and read back identical to the block in `app-store-forms.md` §11.5:

- **In step 1, open « Accueil > Avis » on the demo account and report whether a review exists.** The notes mention
  « Signaler », and it only shows on a review. If there is none, **the owner decides whether that sentence stands**; it
  is still true of the app. Decision 77 approved the block as written, so it does not change without them.
- **Read the Instagram profile's bio and report whether it links to salon sign-up.** The five pages keep the link to
  that profile (§5).

**It does not see, and this is not the owner's choice:** a session the server refuses (only the widget tests
cover it, and a device cannot cheaply provoke it), and a second account on the same phone.

Reported by the owner, dated in `app-store-forms.md` §11.6: nothing in this repo observes a device.

**Owner-reported, 2026-11-03:**

- **The pass:** « my results passed », on their iPhone, on signed build 719. It is one report for the whole pass, not
  itemised, so the boxes for steps 1 to 4 in `app-store-forms.md` §11.6 are not ticked one by one.
- **« Continuer avec Apple »** on that iPhone showed « Aucun compte MyWeli Pro… ».
- **The Instagram bio** does not link to salon sign-up.
- **The demo salon's « Avis »** has no review: decision 81 (§16).

**The iPad: step 5 ran on an iPhone, not an iPad.** Observed by Claude at about 23:43 UTC on 2026-11-03, on an iPad Air
11-inch (M3) simulator, Apple's review device: a **debug** build of the pro flavour from `713114a5` (`com.myweli.pro`,
`UIDeviceFamily` [1], so iPhone compatibility mode). The sign-in screen shows no link, including after scrolling to its
end. One tap on « Continuer avec Apple » opened Apple's system dialog « Sign in to your Apple Account »; closing it shows
the full sentence « Connexion Apple impossible sur cet appareil. Vérifiez dans Réglages qu’un compte Apple est connecté,
puis réessayez. » with nothing to tap. (Step 5 says that cancelling Apple's sheet shows nothing; closing this dialog
showed the sentence.) **What it cannot show:** it is not the signed build, so a successful Apple sign-in on an iPad remains
unobserved.

**The iPad's two results, 2026-11-04.** *Owner-reported*, on that simulator and that debug build, not signed 719: « demo sign-in on the iPad passed, Maison Nala loaded, and I received the code on another email and when entered it said aucun compte myweli... ». *Observed by Claude at 00:04 UTC*, on that simulator, the no-account screen: the full sentence « Aucun compte MyWeli Pro n’est associé à cette adresse. Si votre salon vous a invité, connectez-vous avec l’adresse qui a reçu l’invitation. », with only « Se connecter », « Renvoyer le code » and « Changer d’e-mail » beside it: nothing about signing up. **Its limit stands.** A simulator proves the layout, not the signed build. A successful Apple sign-in on an iPad remains unobserved: the signed build ran on the owner's iPhone, where it gave « Aucun compte MyWeli Pro… », and the simulator has no Apple account.

## 12. Rollout

**The web and the app land together, in one PR. The web is live at merge; the build comes after merge.**
Nothing is merged, uploaded, pasted or sent except by the owner's go. *On 2026-11-03 steps 1 to 4 ran as written
below. Step 5 is owner-reported, its iPad part on 2026-11-04, on a simulator and a debug build. Step 6 ran, and its Media Manager read is owner-reported on 2026-11-04. On 2026-11-04 the API reads step 7's « Add for Review » as done, and its reply is owner-reported as sent.*

| # | Step | Who |
|---|---|---|
| 1 | The PR: this spec, the app, the web, the notes block, CI green, goldens on Linux. **Done: #731** | Claude, then the owner's review |
| 2 | Merge. **The web is live.** `curl` the five paths with an iPad user agent and read them: no `/professionnels`, `/pro/inscription`, `/pro/connexion`; control: `/` still has them. **Done 2026-11-03** | Planned: owner merges, Claude checks. Done: Claude merged and checked, on the owner's go (« Merge, build, upload ») |
| 3 | Hold other merges (dependabot included) until the build is made. Build from `main`: `./tool/release_build.sh ios pro`, which refuses a dirty tree or a HEAD that is not `origin/main`. Version stays 0.0.1; the build number is `git rev-list --count HEAD`, so `<BUILD>` is read from the IPA, not predicted. **Done 2026-11-03: 719** | Claude, on the owner's go |
| 4 | Read the IPA (§11.3, flipped: §6). Upload, wait for `VALID`. **TestFlight:** « Équipe MyWeli » holds this build only, not in « Testeurs externes », and « What to Test » written from `app-store-forms.md` §11.5 and read back. **Sentry:** symbols read back on the server (6 of 6 debug IDs), the release created, with its commits. **All done 2026-11-03** | Read, upload and TestFlight: Claude, on the owner's go. Sentry: by Claude, following the runbook; that go did not name it |
| 5 | The device pass (§11), with the two additions for the owner. **Owner-reported on 2026-11-03: « my results passed », on their iPhone, signed build 719, with both additions. Its step 5 ran on an iPhone. Owner-reported on 2026-11-04: the iPad's demo sign-in and no-account address passed, on an iPad Air 11-inch (M3) simulator, a debug build from `713114a5`, not signed 719 (§11). A successful Apple sign-in on an iPad remains unobserved** | Owner |
| 6 | App Store Connect, in this order while the version is editable: the film in both slots, with the poster read back on both, **and every size read in « View All Sizes in Media Manager »**, a site view with no recorded API equivalent, so whoever does it reads it in the site (§8); the description (§7, with decision 79); the build; the notes, wording approved (§6). **The film goes first, and any refusal stops the sequence before the build, the notes or the reply are touched** (§13). **Done on 2026-11-03 with no refusal. The Media Manager read: owner-reported on 2026-11-04 (« I checked Media Manager »), not observable from here, with no order stated against the submission** | Planned: owner approves; API or owner. Done: Claude, after the owner's « my results passed », having told them it would do exactly that if the results passed. The Media Manager read: in the site, by whoever does it |
| 7 | The Resolution Center reply and « Add for Review ». **« Add for Review »: done per the API, submitted at 00:02:00 UTC on 2026-11-04 by a user account, not an API key; which person is not readable. The reply: owner-reported as sent on 2026-11-04 (« I checked Media Manager and sent the reply »), the `app-store-forms.md` §13.2 block with 719, not observable from here** (the thread has no API) | Planned: owner only |
| 8 | While in review: B0.1 applies (no `DEMO_PROVIDER_CODE` rotation, no Cloudflare change, same-day answers, no edit to the five pages). **In force since 00:02:00 UTC on 2026-11-04, per the API** | Both |

**No production backend deploy** (decision 47): no step needs one, and the next one switches the Apple keys
on, whatever its reason. **Web merges are production deploys**, so during review the five pages are not edited.
*2026-11-04: a merge to `main` deploys even when `web/` does not change. Vercel reads « Deployment has completed » on `4e78e485`,
which touches no `web/` file, and on `7a0f21d6`, docs only. So merging the docs PR that holds this record triggers a production
deployment of an unchanged web tree. The owner chose on 2026-11-04 to merge it after green, in review (§16).*

The stale-doc sweep (BACKLOG, LAUNCH, PRD, `pro-app-login-only.md`'s body) landed in #731 too, with §8's notes, the
tests and this spec, so one PR carried it all. This record of the merge and of build 719 is a separate docs change on
top of it, and touches no page.

**What steps 1 to 4 read, on 2026-11-03.** All observed; what was not observed is under the limits.

- **The go.** The owner's choice « Merge, build, upload » was described to them as: merge, read the five live pages, build,
  check the build for the removed link, upload to TestFlight for the device pass. Sentry's symbols followed the runbook, by
  Claude, and were not named in that go.
- **The merge.** #731, squash-merged by Claude on that go as `713114a5`
  (`713114a56d1a8aeac576a39e423c5a51c1ed3607`) at 22:25:58 UTC, all 13 checks green on head `b45f5cd1`. The first run of
  « Mobile — iOS builds » never got a runner (cancelled after 15 minutes, « not acquired by Runner », 0 steps), and the
  re-run passed at 21:47 UTC. The previous commit's iOS run passed, and nothing under `mobile/` outside `test/` changed
  between them.
- **The live read.** Vercel's production deployment of `713114a5` reported success. Read at 22:37:15 UTC with an iPad
  user agent: on each of the five, `/professionnels`, `/pro/inscription`, `/pro/connexion`, `/pro/salons/nouveau` and
  « facturation » are at 0. Before the merge `/cgu` had 4, 3 and 3 of the first three. Controls after: `/` has 4, 1, 1 and
  `/connexion` has 2, 1, 1. An independent read: identical bytes across iPad, iPhone and desktop user agents, and rendered
  in Chromium at 375, 820 and 1280 with 0 salon links and 0 errors. Real Safari, on an iPad Air 11-inch (M3) simulator at
  about 23:17 UTC: the header of `/support` and of `/cgu` ends on « Mon compte », `/support`'s footer holds only legal
  links and Instagram, and `/` shows « Espace pro », the control.
- **The two taps.** 84 of 84 one-tap landings and 135 of 135 two-tap routes confirmed: salon registration is two taps
  from the five, never one. « Mon compte » lands on `/connexion?returnTo=/mon-compte`, through a client-side gate.
- **The build, the upload, TestFlight, Sentry.** Build 719 from `713114a5` at 22:30 UTC, `altool` validation succeeded,
  the IPA read, delivery `4eb50f72-f6d1-4ca2-ad6a-e5e544fdb25f`, `VALID`, `buildBundles.locales` `["fr"]`; « Équipe
  MyWeli » holds 719 only, `IN_BETA_TESTING`; 6 of 6 debug IDs read back on Sentry: `app-store-forms.md` §11.3, §11.5,
  §12.
- **The limits.** Only `/support` and `/cgu` were looked at in Safari; the other three were read raw and rendered in
  Chromium. Only the `lhr1` edge was reachable. `%2F` and `%5C` typed by hand brought the links back at that read; #732 closed that later the same night (§5.1).
- **As it stood then.** Version 0.0.1 was `REJECTED`, release `MANUAL`, 698 attached. Step 6 changed that later the same
  night, below. The backend is not deployed.

**What step 6 read, on 2026-11-03.** Written and read back by Claude, after the owner's « my results passed », having told
them it would do exactly that if the results passed.

- **The film and its poster,** at 23:49 UTC: §8 holds the IDs and the checksums. Both framed copies are deleted. The
  localization's `/placements` reads 2 `APP_PREVIEW` `ACTIVE` and 16 `APP_SCREENSHOT` `ACTIVE`.
- **The description.** Written to fr-FR, 1,039 characters, read back identical. Keywords, promotional text, support URL,
  marketing URL (empty) and locale unchanged.
- **The build.** 719 attached (204), read back as `4eb50f72-f6d1-4ca2-ad6a-e5e544fdb25f`. The version moved from `REJECTED`
  to `PREPARE_FOR_SUBMISSION`, release `MANUAL`.
- **The notes.** Written, read back identical, 3,991 bytes (decision 81). Demo and contact fields unchanged by fingerprint:
  password set, contact set, demo required, demo user `revue@myweli.test`.
- **The submission.** `45ed9726-1418-435b-b3e2-76726422c5d3` read `UNRESOLVED_ISSUES`, its item `REJECTED`, as it stood then.

**Not done, as of that read, as it stood then:** the iPad's demo sign-in and no-account address (§11); the read of « View All Sizes in Media
Manager »; a same-day demo sign-in on TestFlight beyond what the owner reported; the reply (its text given to the owner with
719); « Add for Review »; the read-back after it. The backend is not deployed. Nothing had been sent or resubmitted at that read.

**What the API read on 2026-11-04.** GET, twice, by Claude's review of this record, the second at 00:18 UTC. The reads above
stay as they stood on 2026-11-03; these replace their present tense.

- **The version.** `ce5cb759-b202-4c15-94cf-3040180a711f`: `appStoreState` and `appVersionState` `WAITING_FOR_REVIEW`, release
  `MANUAL`.
- **The submission.** `45ed9726-1418-435b-b3e2-76726422c5d3`: `WAITING_FOR_REVIEW`, `submittedDate` 2026-11-04T00:02:00.35Z,
  `submittedByActor` of type `USER`, not an API key, `lastUpdatedByActor` `APPLE`, its item `READY_FOR_REVIEW`. So step 7's « Add
  for Review » is done, per the API.
- **The slots.** `IPHONE_67` holds only `17000019-5a03-88cb-8118-40e21663fe37`, `IPHONE_61` holds only
  `f3000019-5a03-88cb-8114-ec9980fce3b8`, and both framed previews answer 404. That does not replace the Media Manager view, which
  §8 keeps as its own gate.
- **Not readable from the API:** whether the Resolution Center reply was sent, and which person submitted.
- **Not recorded from this read:** the attached build, the notes and the description since the submission.
- **Read earlier, at 00:05 UTC, by Claude:** submission `45ed9726-1418-435b-b3e2-76726422c5d3` `WAITING_FOR_REVIEW`, `submittedDate` 2026-11-04T00:02:00.35Z, item `READY_FOR_REVIEW`; version 0.0.1 `WAITING_FOR_REVIEW`, release `MANUAL`, build 719 attached. The film, the description and the notes were still as written.

**The gates before « Add for Review », owner-reported on 2026-11-04.** That point passed at 00:02:00 UTC. The iPad's demo sign-in and
no-account address passed, on a simulator and a debug build, not signed 719 (§11). « I checked Media Manager and sent the reply »: the
reply is the `app-store-forms.md` §13.2 block, with 719. The owner did not say whether the Media Manager read came before or after
the submission, so this record states no order. Neither the read nor the reply is observable from here. A demo sign-in on TestFlight
is known only from the owner's report of 2026-11-03.

**The rendered read owed by #732 is done: one address in real Safari, all 20 forms in Chromium** (§5.1). `/support%2F`, real Safari on the iPad Air 11-inch (M3) simulator,
00:06 UTC, with the same address before #732 as the control. It does not cover the footer's links. The other spellings were read
raw in that pass, and all 20 forms rendered in Chromium afterwards (#733). Reads are allowed during review; a web edit is not.

**The rendered read owed after #730's deploy is done, on 2026-11-04.** #730 (`a41f7db9`, `/professionnels` and the 404, merged on the owner's
word, in review) edits none of the five pages' own files, but their served HTML changed. Read from about 13:46 to 14:40 UTC, by the saved
files' times, signed out, on the build whose full SHA is in the chunks `/support` loads: the five, hydrated, in Chromium 149 and WebKit 26.0, each at
820×1180 and 390×844, so 20 reads, all 200.

- **No link.** No link, button or menu on any of the five leads to `/professionnels`, `/pro/inscription` or `/pro/connexion`, raw or hydrated. Controls: `/`
  has 5 such links and `/connexion` 4. Typed spellings that answer 200 show none; those that answer 404 keep them, as §5.1 says.
- **Two taps.** Each of the three is exactly two taps from each of the five, never one: a crawl in all four browser and size pairs, and 48 of 48 runs with
  real taps. « Mon compte » still reaches the client's sign-in in one tap (§13).
- **Words and links unchanged.** 0 differences against the HTML saved before the deploy, raw and hydrated. `/support` has no WhatsApp row. 0 page errors, CSP
  violations or hydration messages.
- **What did change.** 1,405 more bytes on each page: the 404's fragment in the RSC payload went from 585 to 1,990, with the band's drawing
  ([web-swiss-direction.md](web-swiss-direction.md) §13.2). It is not rendered, and its one link goes to `/`. Forced to show in the reader's own browser, it
  holds no salon link. Without it and with same-length hashes neutralised, old and new are byte-identical.
- **Later deployments.** #735 and #664, no `web/` file, production deployments created at 15:03 and 15:25 UTC. A raw read at 15:29 UTC: the five are the same length and differ only
  in the build ID and chunk hashes. Not read hydrated again.
- **The limits.** Not real Safari and not a device: Playwright's WebKit build, driven by an older Playwright (1.58.2) than the repo's, which cannot drive the
  installed build. Only the `lhr1` edge; Apple's reviewers may reach another. How the app opens these pages was not read. The old stylesheet now answers 404,
  so the look was not compared. Two HEAD requests to `/support` went outside the GET-only rule; everything else was GET.

**Production checks.** The last scheduled run was green at 13:16 UTC on `4e78e485`, before the merge, and issue #549 is
closed. A green run after `713114a5` has not been observed. Read again at 00:24 UTC on 2026-11-04: still that run. Read again at
00:40 UTC: still that run, so no green scheduled run after `713114a5` or `7a2c7e15`.

**Still open on 2026-11-04:** Apple's decision; that green run; a successful Apple sign-in on an iPad; the production backend deploy
after Apple's decision, the one that switches on the Apple keys; the release by hand after approval; merging the docs PR that holds
this record, after green and in review, the owner's choice (§16).

## 13. Accepted risks and the contingency

**Accepted by the owner, knowingly:**

- **The end card.** 2.5 s of paper, mark and disclosure, not a capture, on the same paper the reviewer just objected
  to around the capture. For it: Apple's previews page names the end frame as a place for disclaimer copy, and the
  rejection names only framing on a film that carried this card.
- **« Total ».** The take says « Total » on Revenus; the build says « Total réalisé » and « Rendez-vous terminés ». A
  re-render cannot fix a take. The retake is for 0.0.2.
- **A third rejection is possible**, and the review clock is days. The audit's pick was to ship no film; the owner chose
  this one after hearing that.
- **The pricing page, two taps from the five pages (decision 80, « Accept it », 2026-11-03).** `/professionnels` is two
  taps from them, as sign-up is, and reads « 3 mois offerts — sans carte bancaire », « Combien coûte MyWeli Pro ? » and
  « l’offre Réseau », with no amount and no currency. Apple could still object.
- **Salon visitors on the five pages lose the salon links.** The logo still goes home, and home's band still says
  « Vous êtes un salon ? ». So sign-up stays two taps from each of the five (the logo, then « Inscrire mon salon » in
  home's footer) and one from home. Apple may read that too; removing it hurts every web
  visitor and the owner kept it. *Measured live on 2026-11-03: two taps, never one (§12).*

**Known, and not acted on:**

- **« Mon compte » on the five pages** reaches the client's sign-in in one tap (`/connexion?returnTo=/mon-compte`, through a
  client-side gate), and salon sign-up from there in one more (§5). It is not in decision 3, and the owner hears of it with
  the wording (§16).
- **The Dynamic Island pill on every capture frame of the film.** The simulator recorder draws it; it is not around the
  capture. The refused film had it too, and Apple cited only the framing. To decide at the 0.0.2 retake (B0.8).
- **The limits of the real-WebKit read.** Only `/support` and `/cgu` were looked at in Safari, on an iPad Air 11-inch (M3)
  simulator; the other three were read raw and rendered in Chromium. Only the `lhr1` edge was reachable (§12).
- **Play's description keeps both sentences decision 79 corrected** (« semaine » and « à domicile, »), saved in its
  console: the owner has not decided on Play (§7, §16).
- **5.1.1(ix)**, KYC under an individual seller: uncited twice. Fallback decided (B0.6: hide KYC and the deposit switch on
  iOS if cited).
- **5.1.1(v)**, a reviewer cannot see a real deletion: the demo account refuses it by design. A recording taken during the
  device pass can be attached, the owner's choice.
- **The stills** show « Revenus » and « Total » from before those labels changed (stills 3, 8). 2.3.3 asks that they follow
  the UI; they wait for 0.0.2.

**Settled on 2026-11-03:**

- **No recorded precedent on a `REJECTED` version with an open submission.** Replacing the film, setting the poster and
  editing the description were inferred only, so the plan put the film first, with any refusal stopping the sequence before
  the build, the notes or the reply were touched. **Apple accepted all of them**: the new films reached `COMPLETE` and the
  framed ones were deleted (204), through the deprecated `appPreviews` resources; the description was written and read back
  identical; the poster took, but only from a PATCH after processing, Apple having ignored the time sent at reservation and at
  commit and set 00:00:05:01 (§8). **Not settled by this:** « View All Sizes in Media Manager », not observable from here, owner-reported as checked on 2026-11-04 (§12).

**Closed by #732, recorded on 2026-11-04:**

- **`%2F` and `%5C`, typed by hand, brought the salon links back on the five.** The app and App Store Connect use the bare paths.
  #732 merged at 23:59:03 UTC on 2026-11-03 and its production deployment reported success at 00:01:08 UTC, before the submission.
  **The rendered read, 2026-11-04:** `/support%2F` only, in real Safari on the iPad simulator at 00:06 UTC, its header read and not the footer's links, with the
  same address before #732 as the control. All 20 forms were then read rendered in Chromium (#733, §5.1).

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

*Checked on 2026-11-04 against #731's 20 commits, its 13 checks and its squash.*

- [x] This spec committed before code, indexed in `README.md`, cross-linked from the code it governs. *`29d527b6` before `ea631a55`; the web slice's `d6cb0ba2` before `132a91fc`.*
- [ ] Every new test and guard watched red on the old code, and red under a mutation on a copy of committed work; both in the commit message. *Left open: the record does not say this. `ea631a55` lists guards green on the old code and red only under mutation, as does `b5a2b18b` for one (the labels were right), and `3d20632a` says every test on the two new surfaces was seen red at least once. The last two guards' red is written in §10, not in a commit message: `8dcf44fa` points to `77c4bfd8`, whose body is empty.*
- [x] `flutter analyze` 0, `dart format` clean, the design-token gates, the full mobile suite once; web lint, typecheck, unit, e2e, build. *`3d20632a` (suite, gates), `b09de93e` (full e2e 383), `2b411154` (at `0abc89c1`: analyze 0, format clean, 3,164 tests, 2,455 web unit tests, build); all 13 checks on head `b45f5cd1`.*
- [x] Goldens on Linux; every changed PNG looked at; the rest byte-compared. *`3d20632a`, run 41643819126: 57 of 58 byte-identical, the one changed looked at. `2b411154`: no rendering changed after it.*
- [x] Notes wording approved by the owner; weight recounted; no 3.1.3(f) anywhere sent to Apple. *For #731: decision 77, 3,937 bytes, held by `app_review_notes_test.dart`. Since then, one clause the owner delegated: decision 81, 3,991 bytes.*
- [x] After merge: the five pages read live with a control (§12 step 2). *2026-11-03, with its limits.*
- [x] The IPA read (§6). *Build 719, 2026-11-03.*
- [x] The device pass reported (§11). *Reported for the iPhone on 2026-11-03, on signed build 719. Owner-reported for the iPad on 2026-11-04: the demo sign-in and the no-account address passed, on an iPad Air 11-inch (M3) simulator and a debug build from `713114a5`, not signed 719. A successful Apple sign-in on an iPad remains unobserved (§12).*
- [x] Both iPhone slots read back with the new file and the poster before « Add for Review ». *Read back through the API on 2026-11-03, before the submission (§8); on 2026-11-04 each slot holds only its new preview (§12). Its gate, « View All Sizes in Media Manager »: owner-reported as checked on 2026-11-04, with no order stated against the submission. So « before » here is the API's read, not Media Manager's (§8, §12).*
- [x] Feature branch and PR. No Claude attribution of any kind. A roadmap entry. *`fix/app-review-round2`, #731; no attribution in its 20 commits, its body or its squash; `docs/roadmap/entries/2026-11-03-app-review-round-2.md`.*

## 16. Open questions

**Answered by the owner on 2026-11-03 (decision 77): the notes, the description and the reply are approved as written.** They
were told, before answering:

- « Mon compte » stays on the five pages for the reasons in §5, so the notes and the reply say « no link to salon registration »
  and not « no registration link »;
- that sign-up is two taps from those pages, where this spec had said about three when decision 3 was taken;
- « the separate MyWeli app and myweli.com » stays in the first paragraph. The consumer app was not published at the last reading, and
  production had no public salon on 2026-10-28, so a reviewer may find neither;
- « A new salon's free trial starts automatically when the salon goes live » simplifies decision 68: a first offer chosen on the web
  starts it earlier. It is true of the app;
- no recording of a real deletion is attached unless Apple asks. « Any other account is deleted at that step » rests on code and
  tests, and the focused pass does not exercise it (§11).

**Answered later the same day, after the independent check.** Decision 79, « Correct both »: the description loses « semaine » and
« à domicile, » (§7); the notes and the reply stay as approved. Decision 80, « Accept it »: the pricing page stays two taps from
the five pages (§13).

**Delegated by the owner on 2026-11-03: [decision 81](../BACKLOG.md).** The demo account has no review, owner-reported (§11). This
was open and the owner's: whether the notes' « Signaler » sentence stands. Their words: « there was no review , so do what is
better ». Claude kept the sentence, which is still true of the app, and added one clause, and the owner has been told the exact
clause. Old: « Signaler » under « Avis », customers report. New: « Signaler » under « Avis » (not visible on the demo salon, which
has no reviews), customers report. The notes differ from what decision 77 approved by this clause only (§6).

**Answered by the owner on 2026-11-04, owner-reported (§11, §12):** the iPad's demo sign-in and no-account address, and « I checked
Media Manager and sent the reply ».

**Answered by the owner on 2026-11-04:** the docs PR holding this record merges « After green, in review ». The merge triggers a
production deployment of an unchanged web tree (§12), and B0.1 applies since 00:02:00 UTC.

**Still open, and blocks nothing:** whether the Play listing takes the description's four edits (§7, decisions 74 and 79). It keeps
the old text until Play comes up again.
