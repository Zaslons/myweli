# Pro app display fixes found during the App Store shoot

| | |
|---|---|
| **Status** | **Approved** (owner, 2026-10-13) — building |
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
- `TimedCachedImage` timeout: icon-only with tooltip in a narrow box, label
  in a wide one, the loader not visible, a late image replaces the cover.
- Dashboard: both cards in a row share one height.
- Manual booking: « Client sans numéro », no SMS switch, `sendSmsInvite`
  false. Avant/Après: no « — ».
- Each new guard watched red; goldens regenerated on Linux and reviewed.

## 9. Rollout

With PR #573 in **build 566**.

## 10. Definition of done

- [ ] Tests green, `flutter analyze` 0, guards watched red.
- [ ] Goldens regenerated and reviewed.
- [ ] SYSTEM.md §21 row added for the timeout overlay (literal colours, a
      control drawn over a live animation).

## 11. Open questions

None.
