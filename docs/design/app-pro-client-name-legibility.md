# The client's name on three Pro screens: never cut, never squeezed

| | |
|---|---|
| **Status** | Approved (2026-11-28) |
| **Approved** | by the owner, 2026-11-28, on §5: « Approve as recommended » (all five decisions) |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-28 |
| **Module / phase** | `clients` (the list and the client card) · `journal` (the day's timeline) · V1 |
| **Register row** | [SYSTEM.md](SYSTEM.md) §21 row 100: « the screens: next, one slice each, on the owner's word » |
| **Rule** | [SYSTEM.md](SYSTEM.md) §13.3 « A flexed label may not be squeezed below a readable prefix » (A12) and « A value the user reads as one token … may not break INSIDE a word » (A11 C8, A13: a proper noun the user chooses between) |
| **Precedents** | [app-team-email-seams.md](app-team-email-seams.md) (#905, « Équipe »: the chip moved under the label, the initial avatar dropped) · [app-pro-profile-email-seams.md](app-pro-profile-email-seams.md) (#912, the member « Profil »: the chip under the person) |
| **Builds on** | [amounts-that-fit.md](amounts-that-fit.md): `TextFit` and « the widest shape in which every value stays whole » |
| **Governs** | `mobile/lib/screens/provider/clients/client_detail_screen.dart` (`_Header`) · `mobile/lib/screens/provider/clients/client_list_screen.dart` (`_ClientRow`) · `mobile/lib/screens/provider/journal/pro_journal_screen.dart` (`_TimelineCard`) · [clients-c1.md](clients-c1.md) §5 and [journal-j1b-app.md](journal-j1b-app.md) §4.2 (their row descriptions) |
| **Skills checked** | `myweli-dev-guardrails` |

---

## 1. Goal & scope

PR #909 corrected `expectNoLegibilityCrush` so that it sees
`Text(overflow: ellipsis)` with no `maxLines`. It then measured five places
where a name is squeezed below the 8-character floor. #905 and #912 fixed two
of them. This spec fixes the other three, all in the Pro app:

1. **The client card's header** (`client_detail_screen.dart:357`): the name in
   `titleLarge`, beside the « MyWeli » badge and the « Appeler » and
   « WhatsApp » buttons.
2. **The client list's row** (`client_list_screen.dart:265`): the name beside
   the « MyWeli » chip and the absence chip, with up to two tags at the
   row's right edge.
3. **The journal's row** (`pro_journal_screen.dart:876`): the name beside the
   absence chip and the deposit icon, with the status chip at the card's
   right edge.

**The goal:** a salon reads its client's whole name at every text size, on
every phone width we support, and no row overflows. §13.3's fix is more
width, never a smaller font, and these three places can give it.

**Out of scope:** §7.

## 2. Measured before building

**Setup.** `main` at `47e46cfd`, Roboto (the real font), the real screens
driven through the mock services. Phones 360 and 390 dp wide, text at 1× and
2×. A throwaway probe ran the corrected sweep in report mode, read each
name's box, and photographed every screen. It was not committed.

**Data.** Row 100 measured the seeds only: « Aïcha Koné », « Koffi Yao »,
« Tante Marie », « Jean Kouassi ». A salon's real base also has long names,
clients with several absences, several tags, and deposits. The probe adds
four such clients and three such bookings on the same day:

- « Adjoua Kouamé Konan »: three words, MyWeli, three absences, tags VIP and
  Fidèle. In the journal: « En attente », two absences, a deposit.
- « Marie-Laure N’Guessan »: a hyphen and an apostrophe. Guest, one absence,
  tag Nouvelle. In the journal: « Confirmé », one absence, a deposit.
- « Fatoumata Ouédraogo »: a guest with no chip.
- « Abdoulkarim Kouakoussou »: an eleven-letter word. MyWeli, two absences,
  VIP.

### 2.1 What a row shows today

Each cell gives the width the name gets, then the characters drawn before
« … ». « whole » means the full name fits on its line.

**The client card's header** (`titleLarge`)

| Client | 360 × 1× | 360 × 2× | 390 × 1× | 390 × 2× |
|---|---|---|---|---|
| « Aïcha Koné » (MyWeli) | 77 dp: **5 of 10** | 137: **4** | 107: 8 | 167: **6** |
| « Koffi Yao » (MyWeli) | 77: **6 of 9** | 137: **6** | whole | 167: **7** |
| « Adjoua Kouamé Konan » (MyWeli) | 77: **5 of 19** | 137: **4** | 107: 8 | 167: **5** |
| « Marie-Laure N’Guessan » (guest) | 136: 10 of 21 | 232: 8 | 166: 14 | 262: 10 |
| « Fatoumata Ouédraogo » (guest) | 136: 10 of 19 | 232: 8 | 166: 12 | 262: 10 |

**At the default text size, on the most common phone width, the card cuts
every linked client's name.** Beside the actions and the badge, the name gets
77 dp at 360. A guest card has no badge and gets 136 dp, which is still
short of most full names.

**The client list's row** (`bodyLarge`, medium weight)

| Row (its chips) | 360 × 1× | 360 × 2× | 390 × 1× | 390 × 2× |
|---|---|---|---|---|
| « Aïcha Koné » (MyWeli · VIP) | whole | 109: **5 of 10** | whole | 139: **7** |
| « Koffi Yao » (MyWeli · 2 absences) | whole | 40: **0 of 9** | whole | 70: **2** |
| « Adjoua Kouamé Konan » (MyWeli · 3 absences · VIP · Fidèle) | 28: **1 of 19** | 0: **0**, the row **overflows by 111 dp** | 58: **5** | 0: **0**, overflows by 81 dp |
| « Marie-Laure N’Guessan » (1 absence · Nouvelle) | 118: 12 of 21 | 25: **0** | 148: 16 | 55: **1** |
| « Fatoumata Ouédraogo » (none) | whole | 272: 14 of 19 | whole | 302: 16 |

**The journal's row** (`bodyLarge`, medium weight)

| Row (its chips) | 360 × 1× | 360 × 2× | 390 × 1× | 390 × 2× |
|---|---|---|---|---|
| 10:30 « Jean Kouassi » (Confirmé) | whole | 84: **3 of 12** | whole | 114: **5** |
| 11:30 « Adjoua Kouamé Konan » (En attente · 2 absences · deposit) | 64: **5 of 19** | 0: **0**, the row **overflows by 83 dp** | 94: 9 | 0: **0**, overflows by 53 dp |
| 12:30 « Marie-Laure N’Guessan » (Confirmé · 1 absence · deposit) | 75: **7 of 21** | 0: **0**, overflows by 62 dp | 105: 11 | 0: **0**, overflows by 32 dp |
| 13:30 « Fatoumata Ouédraogo » (Confirmé) | whole | 84: **3 of 19** | whole | 114: **5** |

The 2× pictures show two more defects on the same row:

- « 1 prestation » breaks inside its word, « 1 prest » / « ation », in 84 dp.
- An overflowing row draws its chips past the card's edge.

### 2.2 What row 100 did not see

- **The default text size is affected too.** On the card, every linked
  client is cut at 1×. On the list and in the journal, any client with an
  absence chip and a long name is cut at 1× (1 and 5 characters at 360).
- **The rows overflow.** With a client's real chips, the name gets 0 dp and
  the chips run off the card. That is not a crush the gate measures. It is a
  layout exception, and the a11y suite never pumped these screens.
- **The deposit icon is never heard.** It is a bare `Icon` with no label. A
  screen reader hears « 11:30, 12:00, Adjoua Kouamé Konan, 2 absences,
  2 prestations, En attente », and nothing about the deposit.

### 2.3 The widths a name needs

Roboto, in dp, measured with `TextFit` as `Text` draws them. One word is one
piece: the engine may break only between words or after a hyphen.

| Word | `titleLarge` 1× | 2× | `bodyLarge` medium 1× | 2× |
|---|---|---|---|---|
| « Fatoumata », « Ouédraogo », « N’Guessan » | 105–109 | 211–217 | 81–83 | 158–162 |
| « Christabelle » | 119 | 238 | 92 | 177 |
| « Abdoulkarim » | 127 | 253 | 97 | 188 |
| « Kouakoussou » | 134 | **268** | 103 | **200** |

## 3. Candidates, measured

The shape in §4 was built as a throwaway prototype, measured with the same
probe, photographed, and reverted. Every name below is drawn whole. No row
overflows at either width or text size.

| Screen | Width the name gets | 1× | 2× |
|---|---|---|---|
| Client card | 232 dp at 360, 262 at 390 (296 and 326 without the avatar) | one line each, except « Marie-Laure » / « N’Guessan » at 360 (233 in 232) | « Aïcha Koné », « Koffi Yao » on one line. « Adjoua » / « Kouamé » / « Konan ». « Marie- » / « Laure » / « N’Guessan » (after the hyphen, a legal break). « Abdoulkarim » / « Kouakoussou » with the avatar dropped (§4.1) |
| Client list | 272 dp at 360, 302 at 390 | one line each | the long names on two lines, « Adjoua Kouamé » / « Konan ». A word of up to about 15 letters fits |
| Journal | 236 dp at 360 × 1×, 266 at 390 × 1×. 195 at 360 × 2×, 225 at 390 × 2× | one line each | « Jean » / « Kouassi » at 360 (198 in 195), one line at 390. « Abdoulkarim » / « Kouakoussou » with the time moved above the name at 360 (§4.3) |

**What a screen reader hears on the prototype** (360 × 1×):

- The list: « A, Adjoua Kouamé Konan, MyWeli, 3 absences, VIP, Fidèle,
  +225 07 •• •• •04 · 8 visites · dernière hier ». Today the tags come last,
  after the visits line.
- The card: unchanged, « A, Aïcha Koné, MyWeli, +225 07 00 00 00 01, Numéro
  du compte client ».
- The journal: « 11:30, 12:00, Adjoua Kouamé Konan, 2 prestations, En
  attente, 2 absences, Acompte ».

## 4. The shape (proposed)

Each name gets a line of its own, as wide as the row allows. It wraps
between its words and is never cut. The chips move to a line under it, as
on « Équipe » (#905) and the member « Profil » (#912). Nothing shrinks. What
gives way is the height of a row.

### 4.1 The client card's header

```text
Today (360 × 1×)                       Proposed
[A]  Adjou… [MyWeli]   📞  💬          [A]  Adjoua Kouamé Konan
     +225 07 00 00 00 04                    [MyWeli]
     Numéro du compte client                +225 07 00 00 00 04     📞  💬
                                            Numéro du compte client
```

- **The name** takes the column's full width beside the avatar: 232 dp at
  360 instead of 77. It is `titleLarge` in ink with no ellipsis, and wraps
  between its words.
- **The « MyWeli » badge moves under the name**, unchanged, with
  `spacingXS` above it. A guest card has no badge, as today.
- **« Appeler » and « WhatsApp » move beside the number.** Today they sit
  beside the whole column, name included. They act on the number, so that is
  where they go. The rule for when they fit is unchanged and measured as
  today: beside the number while it fits on one line there, under it when it
  does not. The number never wraps (amounts-that-fit.md §11 Q3).
- **The avatar aligns with the top of the name** instead of the column's
  middle. The column is taller now. Centred, the avatar floats beside the
  number at 2×.
- **When the name's longest word does not fit beside the avatar, the avatar
  is not drawn.** This is measured with `TextFit` on the name, from the
  header's existing `LayoutBuilder`, the way the number's place is decided.
  The name then takes the card's full width: 296 dp at 360. Measured cases:
  « Kouakoussou » at 2× needs 268 dp, more than the 232 beside the avatar at
  360 and the 262 at 390. Nine-letter words such as « Fatoumata » and
  « Ouédraogo » (211–217 dp) keep it. The avatar is an initial in a circle,
  so it carries nothing the name does not.

### 4.2 The client list's row

```text
Today (360 × 1×)                                 Proposed
[A]  A… [MyWeli] [3 absences]    [VIP] [Fidèle]  [A]  Adjoua Kouamé Konan
     +225 07 •• •• •04 · 8 visites ·                  [MyWeli] [3 absences] [VIP] [Fidèle]
     dernière hier                                    +225 07 •• •• •04 · 8 visites · dernière hier
```

- **The name** is the row's title alone, the row's full width beside the
  avatar: 272 dp at 360. Same style as today, no ellipsis, wraps between its
  words.
- **One chip line under it**, a `Wrap`, in this order: « MyWeli », the
  absences (neutral at 1, red from 2, as today), then the first two tags. The
  tags leave the right edge, where they took width from the name and the
  visits line at every size.
- **No chip, no line.** A client with no badge, no absence and no tag keeps
  today's two lines, like « Fatoumata Ouédraogo ».
- **The visits line follows**, as today.
- A row with chips is up to one chip line taller at 1×. It can be less,
  because the visits line no longer wraps beside the tags. That is the price
  #905 paid on « Équipe ».

### 4.3 The journal's row

```text
Today (360 × 1×)                                  Proposed
▌ 11:30  Adjou… [2 absences] 💰  [En attente]     ▌ 11:30  Adjoua Kouamé Konan
▌ 12:00  2 prestations                            ▌ 12:00  2 prestations
                                                  ▌        [En attente] [2 absences] 💰
```

- **The name** takes the column's full width beside the time: 236 dp at
  360 × 1×. Same style as today, struck through when cancelled, no
  ellipsis, wraps between its words.
- **« N prestations » stays under the name**, beside the end time, as
  today.
- **One chip line under them**, a `Wrap`: the **status** chip first (it
  leaves the right edge), then the absences, then the deposit icon. The
  status keeps its colour, and the card keeps its coloured left edge.
- **The time aligns with the top of the name** instead of the middle of the
  card.
- **When the name's longest word does not fit beside the time, the time goes
  above the name**: « 14:30 » then « 15:00 » on one line, the name and the
  rest under it at the card's full width (293 dp at 360 × 2×). This is
  measured with `TextFit`, as in §4.1. Measured cases: at 2× on 360 the name
  gets 195 dp beside the time, and « Kouakoussou » needs 200. Every other
  name in §2 keeps the time beside it.
- **The deposit icon is heard as « Acompte »** (`semanticLabel`), the word
  the app uses for it everywhere else (« Acompte » settings, « Acompte
  annoncé » on the booking).
- **Every card is one chip line taller at 1×** (64 dp → 92 dp at 360),
  because every card has a status. This applies to the day's timeline only: the free-time rows
  (« Libre — 11:00 ») do not change.

### 4.4 Copy

No visible text changes. One new spoken label: **« Acompte »** on the
journal's deposit icon (§5 Q4).

[clients-c1.md](clients-c1.md) §5 and [journal-j1b-app.md](journal-j1b-app.md)
§4.2 are amended to describe these rows. §13.3's text does not change: these
places follow rules it already states. §21 row 100 records the three screens
as fixed, together with what §2.2 found.

## 5. Decisions (answered 2026-11-28, all five as recommended)

1. **The shape: the chips under the name, at every text size, on all three
   screens** (§4). *Recommended.* It is what #905 and #912 did. It is one
   shape, so no branch can go stale. At 1× it moves the journal's status chip
   from the right edge to under the name, and makes a row with chips one line
   taller.
   - *Alternative:* chips stay beside the name while the whole line fits,
     and go under it when it does not, measured for each row. Today's look
     stays for short rows at 1×. But the same list then mixes two shapes: any
     row with absences and a long name goes under even at 1× (§2.1: 1 and 5
     characters at 360).
   **Approved.**
2. **The name is never cut: it wraps between its words.** *Recommended.*
   - *Alternative:* one line with « … », in the new width. That clears the
     8-character floor, but cuts long names at 2× (« Adjoua Kouamé K… »), so
     two clients who share a first name and the start of a surname look the
     same in the list.
   **Approved.**
3. **A word too long for the line: the card drops its avatar, and the
   journal moves the time above the name, only for that name at that size**
   (§4.1, §4.3). *Recommended.* §13.3 says a name the salon chooses between
   may not break inside a word while the layout has width to give, and here
   it does.
   - *Alternative:* keep the avatar and the time where they are, and accept
     a break inside such a word (« Kouakouss » / « ou ») at 2×, recorded in
     §21. #912 accepted this for an e-mail piece, but only because no layout
     had any more width to give.
   **Approved.**
4. **The deposit icon is heard as « Acompte ».** *Recommended:* today a
   screen reader user is never told about the deposit.
   - *Alternative:* leave it unheard, as today.
   **Approved.**
5. **One PR for the three screens, or one per screen.** *Recommended: one
   PR.* One spec, one test file, one golden run. Each screen has its own
   commits, and they can be read one at a time. **Approved: one PR.**

## 6. Tests: red first, on the code before the change

- **`test/a11y/pro_client_names_test.dart` (new).** The three screens as gate
  subjects, through `pumpPushedAtWidth`, at 360, 375 and 390 dp × 1× and 2×.
  There is one `testWidgets` per screen, width and size (the reason is in
  `layout_test.dart`'s header). It uses the real font and §2's data.
  Services are assigned by hand: the clients through a mock subclass serving
  §2's seven clients, and the journal's day through `MockData.appointments`.
  Each test checks:
  - `expectNoLegibilityCrush`, `expectNoUndeclaredTruncation`,
    `expectNoVerticalClip`, and no layout exception (an overflow fails the
    pump);
  - `expectNoMidWordBreak` on each name, by name (§13.3 applies it by name);
  - **the shape itself**: each chip sits below its name, and the status chip
    sits below the name in the journal. This is what makes a mutation red at
    1×, where widths may still fit;
  - **the branch taken** (§13.3: « Assert the thing itself »): the card draws
    its avatar exactly when the name's longest word fits beside it, and the
    journal puts the time beside the name exactly when the word fits there.
    Each branch is checked on « Kouakoussou » and on a name that fits;
  - what a screen reader hears: the journal's row says « Acompte », and the
    list's row hears the tags before the visits line.

  **Red first:** on today's code, the crush gate fails on all three (the card
  at 360 × 1×, the list and the journal at 2×), the list and the journal
  overflow at 2×, and the shape checks fail. Each name loop starts with a
  name that fails today.
- **Existing tests**: `client_screens_test.dart`,
  `pro_journal_screen_test.dart` and the journal flow tests are run. Any
  that read the old layout are updated, and the PR names each one.
- **Goldens, drawn on Linux** (`gh workflow run goldens.yml`):
  - `pro_journal_day` changes: the status chip moves under « Jean
    Kouassi », and the card is taller;
  - new: `pro_client_list_w360_x1`, `pro_client_list_w360_x2`,
    `pro_client_card_w360_x1`, `pro_client_card_w360_x2` and
    `pro_journal_day_w360_x2`. No picture of the list or the card exists
    today. These use the seeds, so Koffi Yao's two absences appear.

  Every changed image is looked at. Every other one must stay byte-identical.
- **Mutations, on committed code**, each applied once, with the failing tests
  read off the run:
  - each screen's chips back beside the name;
  - the ellipsis back;
  - the list's tags back at the right edge;
  - the journal's status back at the right edge;
  - the avatar always drawn, and never drawn;
  - the time always beside;
  - the deposit unheard;
  - the actions back beside the whole column.

## 7. Not covered: follow-ups

- **The website** (`web/app/pro/(dash)/clients`, the Pro journal) has its own
  layout, a table on desktop. It was not measured here. The web mirrors the
  flow, not the drawing (web-mirror-app-flow).
- **The Pro appointment list's client name** shows 9 of 12 characters at
  360 × 2×, one above the floor (row 100). It passes, so it is left as it is.
- **A word wider than the card itself** (about 12 letters of `titleLarge` at
  2× on 360, without the avatar) still breaks inside the word. Past that
  point, no layout has more to give.
- **The masked number in the list's visits line** wraps between its groups at
  2×, as it does today. It is a masked number, not a dialable one, and it is
  outside these three rows' names.

## 8. What does not change

No API, data, or security change: the screens draw the fields they already
receive. Performance: two `TextFit` measurements per card and per journal
row, from a `LayoutBuilder` outside any `IntrinsicHeight`, the same cost as
the header's number today. The rows ship with the next Pro store build, which
is the owner's to make. No flag.
