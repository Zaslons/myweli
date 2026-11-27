# The Pro « Profil » and the Android sign-up: the account's address, broken only at its seams

| | |
|---|---|
| **Status** | Approved (2026-11-27), not built |
| **Approved** | by the owner, 2026-11-27, on §5: « Person, then chip » (§4.1 as a whole) and « Secondary » (§4.2), both as recommended |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-27 |
| **Module / phase** | `access` (the member's Profil) · `auth` (the Android Pro sign-up, E3) · V1 |
| **Register row** | [SYSTEM.md](SYSTEM.md) §21 row 99 (extended) |
| **Rule** | [SYSTEM.md](SYSTEM.md) §13.3 « An e-mail address breaks only at its seams » and « A sentence that names an address gives it a line of its own » (#895) |
| **Builds on** | [app-team-email-seams.md](app-team-email-seams.md) (PR #905, not merged): `EmailSentence` and the gate's `within:`. This branch is cut from #905's |
| **Parity** | the website's member Profil ([web-email-seams.md](web-email-seams.md) §2 place 3, PR #902, not merged): the address alone, the role chip under it |
| **Governs** | `mobile/lib/screens/provider/profile/pro_profile_screen.dart` (the member header) · `mobile/lib/screens/provider/android/pro_sign_up_screen.dart` (`_carriedIdentity`) · `mobile/test/a11y/pro_profile_email_test.dart` · `mobile/test/a11y/pro_sign_up_email_test.dart` · [pro-android-signup.md](pro-android-signup.md) §2.2 and §2.4 row 8 (their copy) |
| **Skills checked** | `myweli-dev-guardrails` |

---

## 1. Goal & scope

#905 brought « Équipe » under §13.3's e-mail rule and named two Pro places
it left out (its §7). They are the last known app sites that draw an
address. This brings both under the rule.

**In scope:**

- the member header of the Pro « Profil » (manager, réception,
  collaborateur: every role but the owner, who sees the salon card);
- the Android sign-up's E3 line « Compte : {e-mail} », shown when a sign-in
  verify answered « no account » and the sign-up carries that address.

**Out of scope:** §7.

## 2. Measured before building

Branch point: #905's head (`fix/app-team-email-seams`). Roboto, the real
font. A throwaway probe drove the real screens through the mock services: a
manager signed in by e-mail OTP for the Profil, and `ProSignUpScreen` with a
carried address for E3. Width: 360 dp. Text: 1× and 2×.

Addresses: `awa@exemple.ci`, `koffi.yao@gmail.com`,
`aminata.kone@exemple.ci`, `retard@myweli.com`,
`awa.kone.nouvelle@outlook.com`, `adjoua.kouame.konan@hotmail.com`,
`ouattaraaminatakone@exemple.ci` and the seed's `awa.manager@myweli.test`.
#905's lesson was that a domain is one piece, so the list holds the
twelve-character ones.

### 2.1 Who has a name

The header's title is the account's name, or its address when it has none.
**A member invited by e-mail has no name.** The server's
`createMemberAccount` (`backend/lib/src/db/postgres_provider_auth_repository.dart`)
inserts `id, phone_number, business_name, business_type, email, …`, with no
`name`, and the Pro app has no screen that sets one. Only the mock's seeded
members (« Awa Traoré », « Fatou Bamba », « Sonia Koné ») have a name. So
**the case real members see is the nameless one**, and the tests and the
golden were never shown it.

### 2.2 The Profil's member header

The card's content is 280 dp wide at 360. Its title sits beside the role
chip (`Expanded`, ellipsis, `titleMedium`). The address follows on its own
line (`bodyLarge`, secondary, no break marks).

| Case | 1× | 2× (360 dp) |
|---|---|---|
| **No name** (every real member) | The title is the address, **cut** past ≈ 25 characters in 217 dp: « awa.kone.nouvelle@outlook… », « adjoua.kouame.konan@hot… ». **Then the address again**, whole, on the line under it | The title has 173 dp beside « Manager » and cuts **every** address: « awa@exe… », « koffi.yao… », « aminata.k… », « retard@m… », « awa.kone.… ». **The line under it breaks mid-word**: « aminata.kone@exe » / « mple.ci », « koffi.yao@gmail.c » / « om », « retard@myweli.co » / « m », « adjoua.kouame.ko » / « nan@hotmail.com », « awa.manager@my » / « weli.test » |
| **A name** (the seeds) | The name beside the chip. The address under it, whole | The same mid-word breaks on the address line |

**What a screen reader hears today.** The card is one node. Nameless, it
hears the address **twice**: « aminata.kone@exemple.ci, Manager,
aminata.kone@exemple.ci, Salon, Salon Excellence ».

### 2.3 The Android sign-up, E3

One `Text`, « Compte : {adresse} », `bodyLarge`, ink, in a 312 dp column.

| 1× | 2× (360 dp) |
|---|---|
| Fits on one line up to ≈ 28 characters: « Compte : aminata.kone@exemple.ci ». A longer one moves whole to line 2, « Compte : » left alone on line 1 | **Mid-word**: « Compte : aminata.ko » / « ne@exemple.ci », « Compte : » / « koffi.yao@gmail.co » / « m », « Compte : awa.kone.n » / « ouvelle@outlook.co » / « m », « Compte : adjoua.kou » / « ame.konan@hotmail. » / « com », « Compte : awa.manag » / « er@myweli.test » |

A screen reader hears « Compte : {adresse} », one node, as it should.

### 2.4 The pieces, measured

The width each piece needs, in dp. A domain is one piece: §13.3 never breaks
it at its « . ».

| Piece | `titleMedium` 1× | 2× | `bodyLarge` 1× | 2× |
|---|---|---|---|---|
| `@hotmail.com` · `@outlook.com` | 106 | **210** | 110 | **214** |
| `@myweli.com` | 102 | 203 | 105 | 205 |
| `@myweli.test` | 98 | 195 | 102 | 197 |
| `@exemple.ci` · `@gmail.com` | 92–94 | 182–185 | 95–96 | 184–187 |
| `awa.kone.nouvelle` (three pieces, side by side) | 136 | 269 | 140 | 272 |
| `ouattaraaminatakone` (one piece) | 156 | **309** | 162 | **314** |

Every domain fits the Profil's 280 dp and the sign-up's 312 dp at 2×.
**Nothing fits 173 dp beside a chip**: even `@gmail.com` needs 182 there.
So the chip has to leave the address's line. A single name piece wider than
the line, like « ouattaraaminatakone », still breaks inside on both screens.
§13.3 accepts that: no layout has more width to give.

## 3. Candidates, measured

The shape of §4 was built as a throwaway prototype, measured with the same
probe, then reverted.

| Place | 1× | 2× (360 dp) |
|---|---|---|
| Profil, no name: the address alone as the title, the chip under it, the second address line gone | whole, every one (« adjoua.kouame.konan@hotmail.com » in 268 dp) | « awa@exemple.ci » · « koffi.yao » / « @gmail.com » · « aminata.kone » / « @exemple.ci » · « retard » / « @myweli.com » · « awa.kone.nouvelle » / « @outlook.com » · « adjoua.kouame » / « .konan » / « @hotmail.com » · « awa.manager » / « @myweli.test ». Only « ouattaraaminatako » / « ne@exemple.ci » breaks inside |
| Profil, a name: the name, the address under it, the chip under both | whole | the same seams as above, on the secondary line |
| Sign-up E3: « Compte : », then the address on a line of its own | whole on its line | « koffi.yao » / « @gmail.com » · « aminata.kone » / « @exemple.ci » · « retard@myweli.com » · « awa.kone.nouvelle » / « @outlook.com » · « adjoua.kouame » / « .konan » / « @hotmail.com ». Only « ouattaraaminatakon » / « e@exemple.ci » breaks inside |

What a screen reader heard on the prototype: « aminata.kone@exemple.ci,
Manager, Salon, Salon Excellence » (no name, once). « Awa Traoré,
aminata.kone@exemple.ci, Manager, Salon, Salon Excellence » (a name).
« Compte : aminata.kone@exemple.ci » (E3, one node). No break mark is heard.

## 4. The shape (proposed)

### 4.1 The Profil's member header

The person first, each on a line of its own, then the role:

```text
No name (every invited member)      A name (the seeds)
aminata.kone                        Awa Traoré
@exemple.ci                         aminata.kone
[Manager]                           @exemple.ci
                                    [Manager]
Salon
Salon Excellence                    Salon
                                    Salon Excellence
```

- **The title** is the name, or, without one, the address. It is
  `titleMedium`, in ink, full width, with no ellipsis. The address breaks
  only at its seams (`Formatters.breakableEmail`). A name wraps between its
  words, as a heading may (§13.3).
- **The address under a name**: `bodyLarge`, secondary, as today, now
  breaking only at its seams.
- **An address is drawn once.** Without a name, the title is the address,
  and the line under it is not drawn again.
- **The role chip moves under them**, on a line of its own, with
  `spacingS` above it. This is the website's member Profil (#902) and
  « Équipe »'s sheet heading (#905).
- A screen reader hears the card as one node, as today. It hears the name
  if there is one, then the address, without its marks, then the role, then
  « Salon » and the salon's name.

### 4.2 The Android sign-up, E3

`EmailSentence.addressLast`, as the code step of the same section draws
`CodeSentTo`:

```text
Votre identité de connexion
Elle vous servira à vous connecter à votre espace pro.
En créant votre compte professionnel, …

Compte :
aminata.kone
@exemple.ci

[ Créer mon compte ]
  Utiliser une autre adresse
```

- « Compte : » on its own line, `bodyLarge`, **secondary**. That is a label's
  colour, the colour of « Entrez le code reçu par e-mail à » one step later on
  the same screen.
- The address under it, in ink, breaking only at its seams. Nothing is
  drawn after it. Short addresses get their own line too, at 1× as well: one
  line more than today when the address fits beside « Compte : ».
- A screen reader hears one node, « Compte : {adresse} », as today.

[pro-android-signup.md](pro-android-signup.md) §2.2 and §2.4 row 8 are
amended to say the address has a line of its own. §13.3's text does not
change: both places follow rules it already states. §21 row 99 gains these
two places.

## 5. Decisions (answered 2026-11-27, both as recommended)

1. **The Profil's shape in §4.1 as a whole.** The chip moves under the
   person, the address is drawn once, and a name is no longer cut.
   *Recommended.* The chip cannot stay beside the title: at 2× it leaves
   173 dp, and no domain fits (§2.4). **Approved: « Person, then chip ».**
   - *Alternative:* the same, but the chip under the name and the address
     last (« Awa Traoré » / « [Manager] » / the address). It only differs for
     a named account, which no real member has (§2.1).
2. **E3's « Compte : » in secondary**, the address in ink (§4.2).
   *Recommended:* it matches `CodeSentTo` on the same screen.
   **Approved: « Secondary ».**
   - *Alternative:* both in ink, as today.

## 6. Tests: red first, on the code before the change

- **`test/a11y/pro_profile_email_test.dart` (new).** Through the real
  Profil, a manager signed in, at 360 dp × 2× and 1×, in the real font, with
  the addresses of §2, nameless and named. It checks:
  - `expectEmailAddressOnItsOwnLine` on the header;
  - nameless: the address is drawn once;
  - what a screen reader hears: the card's one node holds the address
    once, without U+200B, before the role.

  Red first for its own reasons: a cut title, a mid-word break, the address
  drawn and heard twice.
- **`test/a11y/pro_sign_up_email_test.dart` (new).** E3 at 360 dp × 2× and
  1×. It checks `expectEmailAddressOnItsOwnLine`, « Compte : » drawn on its
  own, one node heard « Compte : {adresse} », and no mark heard.

  Red first: at 1× the address starts on the line « Compte : » began; at 2×
  it breaks mid-word.
- **`pro_login_android_test.dart`**: its three E3 checks find « Compte : »
  and the address as drawn (`drawnEmail`), not one string.
- **Goldens, authored on Linux** (`gh workflow run goldens.yml`). None
  photographs either place today, so two new ones:
  - `pro_profile_member_w360_x2`: a nameless member whose address has a
    twelve-character domain;
  - `pro_sign_up_carried_w360_x2`: E3 with one.

  Every changed image is looked at; every other one must stay byte-identical.
- **Mutations, on committed code**, each with its failure text. Each place
  goes back to its old drawing: the chip beside the title, the ellipsis, the
  address without marks, the address drawn twice, « Compte : » inline. Also:
  the marks heard, the lead in ink (for decision 2).

## 7. Not covered: follow-ups

- **A single piece wider than a line** still breaks inside (§2.4).
- **The owner's salon card** draws no address.
- **The mock's members have names; real ones do not** (§2.1). The seeds
  show a header no real member sees. A seed change would move other tests,
  so it is a task of its own, if wanted.
- #905's §7 still holds: `expectNoLegibilityCrush` cannot see an ellipsis
  without `maxLines`; `expectNoMidWordBreak` cannot measure a hyphenated
  piece.
