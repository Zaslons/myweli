# The services' own salon resolvers: one rule with `activeSalonId`

| | |
|---|---|
| **Status** | **Built** 2026-10-16 on `fix/services-acting-salon`. · **Mergé (#627) le 2026-10-16** — app au prochain build (après la revue Apple de 0.0.1) ; rien côté serveur |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-10-16 |
| **PRD ref / phase** | Team access R6 (multi-salons) · V1 |
| **Module** | `access` |
| **Related** | [team-access-r6-multi-salons.md](team-access-r6-multi-salons.md) §6 (`activeSalonId`) · `r6-salon-id-pin.md` §4, added by Zaslons/myweli#625 (where these resolvers were found: that PR fixed the screen and provider layer and left `lib/services` out of scope) · [pro-artists.md](pro-artists.md) · [pro-catalogue-app-wiring.md](pro-catalogue-app-wiring.md) · threats **T36**/**T55** ([BACKEND.md](../BACKEND.md)): the server re-checks every salon id, so this is about client correctness, not a security boundary |
| **Skills checked** | myweli-dev-guardrails · myweli-verification-guardrails |

## 1. The defects (each proven red first, §4)

`ProAuthProvider.activeSalonId` is the salon the pro app acts in: the salon
the user switched to, else the account's own salon, else the membership's
salon. Some service methods take only a `serviceId` or `artistId`, so they
read the salon from the persisted `ProviderSession` instead. Their resolvers
applied a different rule.

| Site | Read | What it did |
|---|---|---|
| `ApiProArtistService._providerId` | `session.provider.providerId` only | **Ignored the R6 selection.** After a switch, `updateArtist`/`deleteArtist` sent PATCH/DELETE to `/providers/<default salon>/artists/<id>`. Artist ids are `artist_<µs>`, so the default salon has no such artist and the server answers 404 `not_found`: the owner could not edit or remove a single staff member of their second salon. |
| `ApiProArtistService._providerId` and `ApiProService._providerId` | no membership fallback | **A bare member account has no `providerId`** (that field means the account owns a salon). The resolver returned null and the method refused client-side with « Compte non lié à un salon », before any request. A Gérant has `catalogue.manage`, and the server accepts their edits (`provider_catalog_service.dart` checks `_can(…, Cap.catalogueManage)`). So against the real API, a manager could not edit, toggle or delete a service, or edit or delete a staff member. |
| `MockProTeamService._providerId` | selection → `account.providerId` → `'provider1'` | No membership step, so a bare member of any salon got **provider1's** roster. It can't be reached from today's UI: the roster needs `members.manage`, which is owner-only in the preset matrix, and every mock owner has a salon of their own. That makes it a mock-fidelity gap, but a real disagreement with `activeSalonId`. |

`ApiProService._providerId` already read the selection first. Its
switched-owner case was correct before this change and is kept as a guard (§4).

## 2. The rule — one function, every caller

`resolveActingSalonId({selected, linked, membership})` in
`lib/models/provider_session.dart`: the first id that is non-null **and
non-empty**, in that order, else null.

| Caller | Fed from |
|---|---|
| `ProAuthProvider.activeSalonId` | `_selectedSalonId`, `_provider?.providerId`, `_membership?.salonId` |
| `ProviderSession.actingSalonId` → `ApiProService._providerId`, `ApiProArtistService._providerId` | the persisted session's `selectedSalonId`, `provider.providerId`, `membership?.salonId` |
| `MockProTeamService._providerId` | the auth service's selection, current account and cached membership; `'provider1'` only when the locator isn't wired (isolated tests) |

**The one behaviour change in `activeSalonId`: an empty id.** Before,
`'' ?? …` returned `''`, and `ProMembership.fromJson` reads a missing
`salonId` as `''`. Now an empty id falls through to the next source, then
to null. Screens that use `activeSalonId ?? ''` are unchanged. A service no
longer builds `/providers//services/…`.

**Why in `models/`:** the rule is a fact about the session, and both layers
already import the model. It also stays out of #625's sweep pin, which scans
`lib/` minus `models/` and `services/`, and it leaves
`pro_auth_provider.dart`'s count of `_provider` reads at 2, so that PR's
reviewed list doesn't change.

## 3. Deliberately not this rule

- **The `?salonId=` appenders send the selection only:**
  `ApiProService._selectedSalonId` / `_salonScopedUri` (and the appointments
  list and `getMyProvider`), `ApiProTeamService._membersUri`, and
  `ApiImageUploadService._signUri`. With no selection, the parameter is
  absent and the server resolves the token's default salon; a selection is
  revalidated per request (T55). Their question is "did the user switch?",
  not "which salon?", so they keep reading the selection alone.
- **Methods that take the salon as an argument** (`getArtists`,
  `createService`, the clients, subscription and dashboard calls…): their
  callers pass `activeSalonId`. #625's pin covers those call sites.
- **`MockProService`** resolves the way the server does (`getMyProvider`:
  selection → owned salon → active roster row). It plays the server, not a
  client-side resolver.

## 4. Tests

Each one was seen red before the fix.

- `api_pro_artist_service_test.dart` — **switched owner** (red: PATCH
  `/providers/provider1/artists/artist1`); **bare member with a cached
  membership** (red: « Compte non lié à un salon »); control: no salon
  anywhere → refused with no request.
- `api_pro_service_test.dart` — **bare member** on
  `updateService`/`setServiceActive`/`deleteService` (red: refused);
  switched owner as a guard (already held).
- `services_acting_salon_test.dart`:
  - the rule's order and its empty-id rule;
  - **agreement**: `activeSalonId` equals `ProviderSession.actingSalonId`,
    including through the JSON the session store keeps, for an owner, a
    switched owner and a bare member (Ancien, after `activateMember`);
  - **the mock roster** for a bare Réception member of Beauté Divine (red:
    provider1's roster), with the switched owner as a guard;
  - **a pin**: no file in `lib/services/api` reads `.providerId`.
    Comments are ignored. It was watched red against main's two services: it
    lists exactly `api_pro_service.dart:72` and
    `api_pro_artist_service.dart:139`.

## 5. Not covered

- Not in a build and not seen on a device. The bare-manager case only
  exists against the real API: the mock catalogue and artist services have
  no salon resolver. A Gérant does reach both screens (the dashboard's
  « Services » and « Employés » entries are gated on `catalogue.manage`), so
  the proof is the service tests above.
- The web's own resolvers were not checked. This change is Flutter-only.
- The account fields that are shown as the salon's after a switch (#625 §4)
  are a separate defect.
