# Web — four sentences that weren't true (B12.1–B12.4) — design spec

| | |
|---|---|
| **Status** | **Built and merged 2026-11-02** (#723). The owner approved the words the same day (§7) |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-02 |
| **PRD ref / phase** | Pro offers (team-access R2a), client cancellation, booking confirmation, Pro access · V1 |
| **Module** | Web only: `lib/pro/subscription-plans.ts`, `lib/pro/landing.ts`, `EquipeClient`, `lib/account/appointments.ts`, `AppointmentDetailClient`, `BookingFlow`, `app/pro/connexion/page.tsx` |
| **Origin** | [web-flow-audit-2026-11.md](web-flow-audit-2026-11.md): P1, C1, C2, P2. Fixed first by the owner's order (BACKLOG decision 67) |
| **Skills checked** | myweli-web-guardrails ✓ · myweli-verification-guardrails ✓ · no backend, contract or data change |

---

## 1. Goal & scope

**Goal.** Each of these screens says only what is true, using facts the page already has.

**In scope:** the wording in §2–§5, the one link §4 adds, and the block §5 removes.

**Out of scope:**
- Any backend change. The trial's clock stays as it is (owner's decision, §2).
- Whether management stays free after a trial: an open business question, recorded in the BACKLOG.
- The other audit gaps (B12.5 onwards).
- The client app's own cancel sentence: it has the same two problems as §3, and it ships with the next app build (B12.11, new).

---

## 2. B12.1 — when the free trial starts

**The facts, read on `main`:** `chooseOffer` creates the subscription with `trialEndsAt = now + 90 days` (`salon_subscription_service.dart:155-160`). A salon that goes live with no choice gets the same clock at that moment, and a choice made earlier keeps its clock (`:80-92`).

**Decision (owner, 2026-11-02): keep the clock and fix the wording.** Moving the clock to go-live was withdrawn: it would let a salon choose an offer, invite a team and run for free without ever going live.

| Where | Today | New |
|---|---|---|
| `/pro/abonnement`, before any offer | Votre essai de 3 mois démarre à la mise en ligne de votre salon. Vous pouvez choisir ou changer d’offre à tout moment. | **Votre essai de 3 mois démarre dès que vous choisissez une offre ou, sans choix, à la mise en ligne de votre salon. Vous pourrez changer d’offre à tout moment.** |
| `/pro/equipe`, no offer | Choisissez votre offre pour inviter votre équipe. | **Pour inviter votre équipe, choisissez votre offre : vos 3 mois d’essai démarrent à ce moment-là.** |
| `/professionnels`, step 3 | Mettez votre salon en ligne — vos 3 mois offerts commencent | **Mettez votre salon en ligne : vos clients peuvent réserver** |

« 3 mois offerts — sans carte bancaire » and « Vos 3 premiers mois sont offerts » stay: both are true. The Pro app's « Votre offre démarre à la mise en ligne de votre salon » also stays: the app offers no choice, so for its reader it is true.

---

## 3. B12.2 — the deposit when a client cancels

**The facts, read on `main`:**
- The server records the cancellation and has **no refund logic**, because MyWeli holds no money (`appointment_lifecycle_service.dart:24-30`).
- The CGU say so too: « MyWeli n’encaisse, ne détient et ne rembourse aucun fonds », and a dispute over a refund « se règle donc avec le salon » (§4). Cancellation terms are those the salon shows (§5).
- Salons agree to a rule on `/pro/acompte`: before the delay the client « peut annuler et garder son acompte » ; inside it, the deposit isn't refunded.
- The appointment carries `depositAmount`, `depositScreenshotUrl` and `cancellationWindowHours`.

**So the app's sentence cannot simply be copied.** « Votre acompte sera remboursé » promises something neither the server nor MyWeli does, and the app says it even when the client never paid. The web states the salon's rule and says who to see.

**The rule** (`cancellationNotice(appointment, now)`, pure and tested; the same cut-off as the app's `cancellation_policy.dart`: exactly at the cut-off counts as late):

| Case | What the confirmation says after « Confirmer l’annulation ? » |
|---|---|
| No deposit | Nothing more, as today |
| Deposit asked, **no proof sent** | **Vous n’avez envoyé aucun justificatif d’acompte pour ce rendez-vous.** |
| Proof sent, **more than N h before** | **D’après la règle du salon, votre acompte de 5 000 FCFA vous revient, car vous annulez plus de 24 h avant. Voyez avec le salon pour le récupérer : MyWeli ne détient aucun acompte.** |
| Proof sent, **N h or less before** | **D’après la règle du salon, votre acompte de 5 000 FCFA ne sera pas remboursé, car vous annulez moins de 24 h avant.** |
| Proof sent, the appointment's time has passed | **D’après la règle du salon, votre acompte de 5 000 FCFA ne sera pas remboursé, car l’heure du rendez-vous est passée.** « moins de 24 h avant » would be false here |
| Proof sent, a salon with no delay (0 h), before the time | The refund sentence, with **car vous annulez avant l’heure du rendez-vous**: never « plus de 0 h » |
| Proof sent, the delay missing (older data) | **Le remboursement de votre acompte dépend de la règle du salon. Voyez directement avec lui : MyWeli ne détient aucun acompte.** |

**Edge cases.** A booking the salon entered has no client proof to ask for, so it adds nothing (`salonEntered` → first row). The amount uses `formatFcfa` with the salon's currency. The sentence is computed when the confirmation opens, from the same clock as the page. A client's wrong clock could pick the wrong row, as in the app: the sentence is advice, and nothing is enforced.

---

## 4. B12.3 — after booking

**The facts:** a client on the website alone gets a row in the notification feed, and no e-mail or push while WhatsApp and SMS are off (`booking_notifier.dart:62-88`). The page has no way to reach the booking. Its only button is the store link, which renders nothing today. The app goes to « Mes rendez-vous ».

| | Today | New |
|---|---|---|
| Sentence | {salon} va confirmer votre rendez-vous. Vous recevrez une notification. | **{salon} va confirmer votre rendez-vous. Sa réponse apparaîtra dans vos rendez-vous et vos notifications.** |
| Action | Store link only | **« Voir mon rendez-vous »** → `/mon-compte/{id}`, and the store link stays beside it |

**States.**
- **No deposit:** the link is the page's filled action.
- **Deposit:** `DepositProof` stays first and keeps the page's filled action; the link is secondary.
- **No id in the answer** (should not happen): « Voir mes rendez-vous » → `/mon-compte`. Never a dead end.

The sign-in gate has already run at this point, so both pages open.

---

## 5. B12.4 — the sign-up loop on `/pro/connexion`

**The facts:** the app sends new salons to the website (`pro_login_screen.dart:465-470`). When store URLs are set, this page would say the opposite, and its button would open the **client** app, since there is only one pair of store URLs. Hidden today, it appears on the day the URLs are set, which is launch.

**The fix:** remove the block. « Créer mon compte » → `/pro/inscription` is already in the sign-in form (`ProLoginOptions.tsx:247`), so a new salon loses nothing.

**Install push.** The guardrail asks for one where appropriate, but this one points at the wrong app. A real Pro install link needs its own pair of store URLs, after release (B0.5's neighbour, recorded in the BACKLOG).

---

## 6. Tests, rollout

Each guard is watched red on committed work. Unit tests use the existing `AppointmentDetailClient`, `BookingFlow` and `pro-access` harnesses.

| Guard | Holds | Red when |
|---|---|---|
| `cancellationNotice` unit table | Every row of §3, one minute either side of the cut-off, and exactly at it | The boundary or a row changes |
| Detail page test | The confirmation shows the sentence for a late, proven deposit | The page keeps the old sentence |
| `BookingFlow` test | The link and its `href`, both variants, and « Vous recevrez une notification » gone | The link is removed |
| e2e `booking.spec.ts` | The link opens the real detail page | The route is wrong |
| `/pro/connexion` test, store URL **set** | No store link and no « dans l’app » | The block returns. `served-html.spec.ts` cannot see this: its build has no store URLs |
| `pro-subscription.test.ts` | The new sentence, and no source still says « démarre à la mise en ligne » or « vos 3 mois offerts commencent » | The old wording returns |

**What these cannot see:** whether a salon honours its rule, and whether the server's clock changes one day. The second is pinned by the backend's own tests, not by these words.

**Rollout.** One PR, one web deploy on the owner's word, read back on `myweli.com`. No backend deploy, so the Apple keys are untouched. `web-pro-access.md`'s old sentences get a dated correction.

---

## 7. Decisions

Both answered by the owner on 2026-11-02:

- **The words in §2–§4:** approved as written.
- **A deposit asked and no proof sent:** the confirmation says so, in one calm sentence, since a client may have paid and forgotten the screenshot.

---

## 8. What was seen

- **Red on the old code:** 19 tests.
- **Green with the fix:** all 2,292 unit tests, types, lint.
- **Each rule broken on purpose, on the committed fix:** 15 of 15 caught, the tree restored after each.
- **In a real build:** `booking.spec.ts` follows « Voir mon rendez-vous » to the booking's real page. The cancel confirmation and `/pro/connexion` were looked at, at 375 wide.
- **Not run locally:** two tests in that run call the stub's fixed port (8787), which only CI's configuration uses. CI runs them.
- **A wrong test, caught by CI:** the first e2e assertion looked for « Annuler le rendez-vous », but the stub answers every booking as `appt1`, and `account.spec` had already cancelled it. CI's snapshot showed the real page with « Annulé ». It now asserts the salon's name, and was re-run with `account.spec` first to reproduce CI's order.
- **Read back on `myweli.com` after the merge:** the `/professionnels` step and the absence of the `/pro/connexion` block in the served HTML; the trial and deposit sentences in the deployed scripts; and all the old sentences gone from those scripts.
- **Not seen:** a real phone. **The after-booking screen on the live site:** `/{slug}/reserver` needs a public salon and there are none, so only the tests have covered it.
