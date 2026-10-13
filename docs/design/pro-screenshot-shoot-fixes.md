# Pro app display fixes found during the App Store shoot

| | |
|---|---|
| **Status** | **Approved** (owner, 2026-10-13) — **built** for build 566 |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-10-13 |
| **PRD ref / phase** | Pro app — clients, photos, home, manual booking · V1 |
| **Skills checked** | myweli-dev-guardrails · myweli-verification-guardrails |
| **Governs** | `client_detail_screen.dart` · `widgets/common/timed_cached_image.dart` · `dashboard_screen.dart` · `pro_manual_booking_screen.dart` · `pro_before_after_screen.dart` · `Formatters.formatDateCompact` · `FeatureFlags.smsInvite` |

## 1. Goal & scope

Seen on build 565 while shooting the App Store screenshots on « Maison Nala »
([pro-app-store-screenshots.md](pro-app-store-screenshots.md) §9). Each was
verified in the code before this spec (2026-10-13):

1. **Client card « Dernière » breaks a word.** `_StatsStrip` puts
   `Formatters.formatDate` — « mardi 13 octobre 2026 » — in a quarter-width
   tile at `titleMedium`: « dimanch / e » (visible in App Store screenshot 4).
   The four `Expanded` tiles also come out at different heights.
2. **Client card prints a raw E.164 number** (« +2250700000101 »). The full
   number belongs on the card (`maskClientPhone`: « the full number stays on
   the card only »); only its formatting is wrong.
3. **A slow image's « Réessayer » breaks and sits on the loader.**
   `TimedCachedImage`'s timeout state lays a 25 % black scrim and a white
   `TextButton.icon` (literal colours) over the still-animating placeholder;
   in a third-width photo tile the label reads « Réessay / er » and the loader
   shows through. Shared widget: every image in the app has it.
4. **Home stat cards at different heights.** The two stat rows are plain
   `Row`s of `Expanded` cards; « 114 000 FCFA » wraps in one and not the other.

Plus three wording decisions (owner, 2026-10-13):

5. « Client sans numéro (walk-in) » → **« Client sans numéro »**.
6. The SMS switch (« Envoyer la confirmation par SMS — … (bientôt
   disponible) ») is **hidden** until SMS exists: the backend never reads
   `sendSmsInvite`, and messaging waits for company registration. Behind
   `FeatureFlags.smsInvite` (false); while off the form sends `false`.
7. An Avant/Après pair **without a caption shows no caption line** (was « — »).

## 2. UX

1. « Dernière » shows `Formatters.formatDateCompact` — « 13 oct. 2026 »,
   which can only break between words (§13.3). The tiles are equal height
   (`IntrinsicHeight` + `stretch`, the dashboard's action-grid idiom). Above
   **1.1×** text the strip becomes a **2 × 2 grid** — the dashboard's
   `_kActionGridSingleColumnAbove` reasoning: one-word values (« 17 000 »
   with its narrow no-break space, « Absences ») cannot wrap their way out of
   a quarter-width tile; more width, never a smaller font. The threshold is
   **measured, not borrowed**: at the 360 dp floor a tile has 60 dp inside and
   « Absences » needs ≈ 51.6 dp at 1×, so it breaks just past 1.16×. This
   spec first said 1.3 (the dashboard's value); the test caught « Absences »
   at 67.1 dp in 60 at 1.3×, and 1.1 keeps the ≈ 5 % margin real rendering
   needs over a bare `TextPainter`.
2. The card reads « +225 07 00 00 01 01 » (`Formatters.formatPhoneNumber`);
   the call / WhatsApp actions keep the raw number.
3. Timed out: an **opaque `surface`** cover hides the loader (the request keeps
   running underneath, so a late image still replaces it), with the retry
   control in ink: `TextButton.icon` « Réessayer » when the box is at least
   200 dp wide and 72 dp tall, otherwise an `IconButton` (48 dp) with the
   tooltip « Réessayer ». No literal colours.
4. Each stat row is `IntrinsicHeight` + `CrossAxisAlignment.stretch`.

## 3–7. Contract, data, security, performance

No API or data change. `sendSmsInvite` is still sent (always `false` while the
flag is off), so nothing server-side moves.

## 8. Testing

- `formatDateCompact` unit test; client card: « 13 oct. 2026 », formatted
  phone, equal tile heights, 2 × 2 above 1.1× (checked at 1, 1.1, 1.15,
  1.2, 1.3, 1.5 and 2×, real fonts), no mid-word break at any of them.
- `TimedCachedImage` timeout: icon-only with tooltip in a narrow box and in a
  wide-but-short strip (320 × 60), the label in a roomy one, whole at 2× in
  the smallest roomy box (200 × 72), and the cover **on** the loader — a hit
  test at the loader's centre reaches the cover first, so a cover painted
  under it fails. *Not guarded:* a late image replacing the cover (under the
  test clock a network image never completes).
- Dashboard: both cards in a row share one height — on the shoot's figures
  (« 0 FCFA » beside « 114 000 FCFA »), in real fonts, at 1×, 1.3× and 2×.
- Manual booking: « Client sans numéro », no SMS switch, `sendSmsInvite`
  false. Avant/Après: no « — ».
- Each new guard watched red; goldens regenerated on Linux and reviewed.

**Mutations (2026-10-13, on committed code): 22 run, 19 red.** M1–M3 date
format and phone; M4b the client tiles back to a plain `Row`; M5–M6 the 2 × 2
threshold (1.3, never); M7–M11 the retry label's width and height floors, a
translucent cover, a cover painted under the loader; M12b–M13b each dashboard
row back to a plain `Row`; M14–M17 « (walk-in) », the switch shown, the flag
ignored, the flag on; M18–M19 « — » back, the caption dropped. **The three
survivors are equivalent:** dropping only `stretch` (M4, M12, M13) changes
nothing, because `IntrinsicHeight` fixes the row's height and each card's
`Column` (`mainAxisSize.max`) fills it. `stretch` stays as the action grid's
idiom, so a card that later shrinks its `Column` still lines up.

**Two guards were vacuous until their mutations survived.** The dashboard test
measured a freshly registered salon, every figure « 0 », so both cards held
the same text. The client test compared only tiles whose tops matched, but
unequal tiles in a plain `Row` are centred, so their tops differ as well (60
vs 84 dp, tops 236 vs 224): every wrong pair was skipped. Both are fixed — the
shoot's figures; rows by vertical overlap with their membership asserted.

## 9. Rollout

With PR #573 in **build 566**.

## 10. Definition of done

- [x] Tests green, `flutter analyze` 0, guards watched red (§8).
- [x] Goldens regenerated on Linux (`goldens.yml` run 38332107792) and
      reviewed: only `pro_dashboard_w360_x2` moved; 50 byte-identical.
- [x] SYSTEM.md §21 row 92 for the timeout overlay.
- [ ] On device, build 566: the client card, a slow photo, the home.

## 11. Open questions

None.
