# R6 salon-id reads: one resolver, and a sweep pin that does not trust names

| | |
|---|---|
| **Status** | **Built** 2026-10-16 on `fix/r6-salon-id-pin`, stacked on `fix/app-pro-export-completeness` (#622). · **Mergé (#625) le 2026-10-16** — app au prochain build (après la revue Apple de 0.0.1) ; rien côté serveur |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-10-16 |
| **PRD ref / phase** | Team access R6 (multi-salons) · V1 |
| **Module** | `access` |
| **Related** | [team-access-r6-multi-salons.md](team-access-r6-multi-salons.md) §6 (`activeSalonId`, the R6 sweep and its pin) · [app-pro-export-completeness.md](app-pro-export-completeness.md) §1.3 (where the gap was found) · threat **T36**/**T55** ([BACKEND.md](../BACKEND.md)) — the server re-checks every salon id; this is client correctness, not a boundary |
| **Skills checked** | myweli-dev-guardrails · myweli-verification-guardrails |

## 1. The defect class

`ProAuthProvider.activeSalonId` is the only correct salon id for a pro screen:
the salon the user switched to (« Mes salons »), else the account's default
salon, else the membership's salon. Two values look like it and are not:

- **`ProviderUser.providerId`** — the account's *default* salon. R6 never
  rewrites it; after a switch it still names the first salon.
- **`ProviderUser.id`** — an *account* id. It is never a salon id.

R6 swept 15 `provider?.providerId` reads to `activeSalonId` and pinned the
sweep with a test (`multi_salon_test.dart`, « the sweep pin ») that grepped
`lib/screens` for the two strings `provider?.providerId` and
`provider!.providerId`. The salon export read
`account?.providerId ?? account?.id` through a local named `account`: the
grep could not see it, and after a switch the export mixed two salons
(fixed in #622). A pin keyed on a variable's name only catches the names
someone thought of.

## 2. The sweep (2026-10-16, on #622's head `645d460d`)

**Method.** Every `.providerId` read in `mobile/lib` outside `models/` and
`services/` — 65 in 249 files, comments excluded; 48 of them a widget's own
parameter (`this.` / `widget.providerId`, 9 files), the other 17 on something
else — every read of the signed-in account
(`ProAuthProvider.provider`, and the locals and parameters it is held in:
`account`, `pro`, `proUser`, `provider`), and every `.id` of those. Each
site was read in context, not classified from the grep line.

### 2.1 Offenders — fixed (each red first, §5)

| Site | Read | What it did | Fix |
|---|---|---|---|
| `pro_data_export_screen.dart` | `account?.providerId ?? account?.id` | After a switch: the listing and bookings of the new salon, the catalogue, team and clients of the default one. | #622 (this PR is stacked on it) |
| `ProOnboardingProvider.load` (`pro_onboarding_provider.dart`) | `proUser.providerId` | R6's « Ajouter un salon » creates the draft, **switches to it and lands on this checklist** — which counted the *default* salon's services, team, hours and deposit, while the photos and profile (`getMyProvider`, which follows the session) were the new salon's. The checklist of the salon being set up showed another salon's progress. | `load(proUser, salonId: auth.activeSalonId)`; `proUser` stays for what is the account's own (KYC, business type). |
| `TeamScreen.build` (`team_screen.dart:97`) | `account?.providerId == null` | Looked like a presence check; **verified, it is a salon question answered with the wrong salon.** It reads « does this account own *a* salon », the gate needs « may this session manage *this* salon's team » (`members.manage`, owner only). An owner switched to a salon they only manage passed it: roster and « Inviter un membre » for a team the server refuses them (T36). The only entry, the Profil row, is already gated on `members.manage`, so this was reachable only through a stale stack — latent, and wrong. | `activeSalonId == null \|\| !auth.can(ProCap.membersManage)` — the R6 precedent (the subscription screen's gate keys on `subscription.manage`). The pre-membership fallback of `can` keeps a linked owner owner-shaped, so the owner roster is unchanged (the `pro_team` golden). |
| `ServiceFormScreen._handleSave` (`service_form_screen.dart:201`) | `activeSalonId ?? provider!.id` | With no salon resolved — a bare member whose membership read failed at start, nothing cached — the service was created under the **account id**. | No salon → no write: an error snack, « Votre salon n’a pas pu être chargé. Vérifiez votre connexion et réessayez. », and the form keeps what was typed. The guard covers an edit too. |

### 2.2 Legitimate — kept, each in the pin's reviewed list (§3)

| Site | Read | Why it is not the acting-salon question |
|---|---|---|
| `pro_auth_provider.dart` ×2 | `_provider?.providerId` | It *is* the resolver (`activeSalonId`), and `can`'s fallback for a linked owner before a membership has loaded. |
| `home_screen.dart`, `provider_detail_screen.dart`, `appointment_card.dart`, `appointment_provider.dart`, `data_export.dart` | `a.providerId` / `appointment.providerId` | A booking's salon: the consumer's bookings, the latest completed visit a review prompt is for, the booking rows of the consumer « Mes données » export. |
| `reschedule_screen.dart`, `my_bookings_screen.dart`, `appointment_detail_screen.dart` | `(widget.)appointment.providerId` | The salon of the booking being moved, rebooked or reviewed. |
| `pro_journal_provider.dart`, `pro_clients_provider.dart`, `pro_dashboard_provider.dart` | `booking.providerId` | A created booking is applied only to the store of its own salon — a comparison *against* the acting salon. |
| `provider_provider.dart` ×2 | `review.providerId`, `posted.providerId` | The salon a posted review is for. |
| 9 widgets and screens | `this.providerId`, `widget.providerId` | A widget's own parameter. Every pro construction site passes `activeSalonId` (checked: `pro_router.dart` deposit settings, `team_screen.dart` invite sheet, `availability_screen.dart` day editor); the consumer ones pass a public salon id from the route. |

Account ids used **as account ids** (legitimate): `pro_kyc_screen.dart`
`pro.id` ×3 and `ProOnboardingProvider.load` `proUser.id` — KYC is per account
(`/me/kyc`, `admin/kyc/[accountId]`); `data_export.dart` `account.id` — the
export's account section.

## 3. The pin (`mobile/test/unit/multi_salon_test.dart`, « the sweep pin »)

**Scope.** Every Dart file in `mobile/lib` except `models/` (where `providerId`
is declared and (de)serialized) and `services/` (where it is mapped to and
from the wire). That is `screens/`, `providers/`, `widgets/`, `core/` and the
`main_*.dart` roots — every layer that *chooses* a salon id. Comments are
blanked first: a doc line quoting `provider?.providerId` is not a read.

1. **Every `.providerId` read is counted**, keyed by file and *receiver* (the
   expression it is read on: `account`, `widget.appointment`,
   `…provider` for a member of an unnamed expression, `…` for a cast or a
   call), and the whole map must equal the reviewed list — each line with its
   count and its reason. A new read anywhere, **whatever its variable is
   called**, is a new key or a higher count, and goes red with the list of
   every read and its lines. `this.providerId` and `widget.providerId` are
   exempt: they declare and read a widget's parameter, and the site that builds
   the widget is itself caught by rule 1 or rule 2.
2. **No salon-id slot is fed by an `.id`.** A slot is where a salon id is
   put: a fallback (`activeSalonId ?? …`, `providerId ?? …`), a named argument
   or a map entry (`providerId: …`, `'salonId': …`), an assignment
   (`final salonId = …`, `_providerId = …`). The value is read to the end of
   its expression, brackets included, so a call or a generic in it
   (`context.read<ProAuthProvider>().provider!.id`) does not hide the `.id`;
   each `??` operand is checked. Three reviewed sites, each the id of a
   *salon* model (`models.Provider`): `appointment_card.dart`
   (`provider.id`), `provider_provider.dart` and `salon_preview_screen.dart`
   (`salon.id`).
3. **The scanner checks itself** on planted source: an alias, a
   `context.read<…>()` chain, a chain split over lines, a cast, a quoted
   comment, both `.id` slot shapes — and asserts exactly what it names.
4. **The scan covers what it claims**: the four layers are in, `models/` and
   `services/` are out, and the export screen — the read the old pin missed — is
   in the scanned set.

**Why not the analyzer.** A type-resolved check (« no `.providerId` or `.id`
on an expression of static type `ProviderUser` ») would need `package:analyzer`
as a new dev dependency, an explicit SDK path under `flutter_tester`, and a
full resolution of the app per run. The ratchet gives the guarantee that
matters — nothing new gets in unreviewed — at the cost of a text scan; the
price is a reviewed list someone has to update.

**What it does not see (stated, not hidden).**
- An account id passed **positionally** to a salon-scoped call
  (`createService(account.id, …)`) fills no salon-shaped slot. Mutation M10
  below survives the pin; the behaviour test catches the one instance there
  is. **Closed by the type on the Pro side** (B9.9 H1, 2026-10-25 —
  [hygiene-batch9.md](hygiene-batch9.md) §2.8, §18): every Pro salon slot is
  a `SalonId`, so M10 no longer compiles. The consumer side follows in H2.
- A reviewed read re-pointed at a `ProviderUser` *without changing the count*
  (same file, same receiver name) — the reviewed list says what each line is.
- `//` inside a string literal is blanked like a comment, so a read after a URL
  literal on the same line is invisible.
- `lib/services` (out of scope by design — see §4).

## 4. Found here, not fixed here

- **The service layer resolves the salon on its own, two ways, neither
  `activeSalonId`.** `ApiProArtistService._providerId()` reads
  `session.provider.providerId` only: after a switch, editing or deleting an
  employee PATCHes/DELETEs `/providers/<default salon>/artists/<id>`.
  `ApiProService._providerId()` honours the selection, but neither falls back
  to the membership's salon, so a bare member with `catalogue.manage` (a
  manager) would be refused client-side (« Compte non lié à un salon ») on
  service edit/delete/toggle and employee edit/delete. Read in the code, not
  yet proven by a test — a follow-up, red test first.
- **Account fields shown as salon facts after a switch.** The owner header of
  « Profil » (`businessName`, `businessType`, `address`, `phoneNumber`), the
  verification status (Profil, Acompte) and the member-actions sheet's salon
  name (`team_screen.dart`, `provider?.businessName` where `auth.salonName`
  exists) all describe the default salon. Same class, other fields; not salon
  ids, so not this pin's.

## 5. Testing

**Red first** — `mobile/test/widget/salon_id_reads_test.dart`, against the
code before each fix:
- « Configuration » after a switch to `provider2`: services asked for
  `['provider1']` (expected `['provider2']`); after the fix every checklist
  read (services, team, hours, deposit) is for `provider2`.
- « Équipe », Jean (owner of `provider1`) switched to `provider3`, where a
  roster row makes him a manager: « Réservé au propriétaire » not found; after
  the fix, the guard and no « Inviter un membre ».
- « Nouveau service » with no salon resolved: the service was created in
  `member_awa` (an account id); after the fix nothing is created, the sentence
  shows and the input stays.

**The mutation record** (committed tree; each mutation applied alone, the
pin group and the behaviour file run, then `git checkout`):

| # | Mutation | The pin | The behaviour test |
|---|---|---|---|
| M1 | A renamed alias planted in `pro_journal_screen.dart` (`final account = …provider; account?.providerId`) | **red** (rule 1) | — |
| M2 | `main`'s export screen restored (`account?.providerId ?? account?.id`) | **red** (rules 1 and 2) | — |
| M3 | « Équipe » gate back to `account?.providerId == null` | **red** (rule 1) | **red** (« Équipe ») |
| M4 | « Équipe » gate keeps the salon check, drops `members.manage` | green — no salon id is read | **red** (« Équipe ») |
| M5 | `load` reads `proUser.providerId` again | **red** (rule 1) | **red** (« Configuration ») |
| M6 | The screen passes `salonId: pro.providerId` | **red** (rule 1) | **red** (« Configuration ») |
| M7 | Service form: guard kept, `?? authProvider.provider!.id` restored | **red** (rule 2) | green — the guard returns first |
| M8 | Service form: guard removed, `?? authProvider.provider!.id` restored | **red** (rule 2) | **red** (« Nouveau service ») |
| M9 | The router builds `DepositSettingsScreen(providerId: context.read<ProAuthProvider>().provider!.id)` | **red** (rule 2) | — |
| M10 | Service form: guard removed, `createService(authProvider.provider!.id, …)` — positional | green — **the stated limit (§3)** | **red** (« Nouveau service ») |

**10 run, 10 red in at least one test**, each in the test that names the
defect; no mutation broke the build instead (a load failure would have been
reported apart).

**The first run had a survivor.** On `8b416028` M9 was green: rule 2 then
followed plain dotted chains only, and the call and the generic in
`context.read<ProAuthProvider>().provider!.id` broke the chain. Rule 2 now
reads the whole value (`be35e1c9`), the self-test carries that
shape, and the second run above is on that commit.

None of the ten mutations contains either string the old pin grepped
(`provider?.providerId`, `provider!.providerId`), so the old pin was green on
every one of them.

Also run: `pro_onboarding_provider_test` (its `load` calls name the salon
now), `pro_onboarding_screen_test`, `team_screen_test` (the bare-member guard
still holds through `can`'s fallback), `pro_profile_role_test`; `flutter
analyze` 0 issues.

## 6. Rollout

Client only — no endpoint, contract or migration. One new sentence (the
service form's refusal) and one guard shown in a case that used to render the
roster. **Merge order:** #622 first; then this branch is rebased onto `main`
(`git rebase --onto origin/main 645d460d`), and its diff is the two commits
plus this note.
