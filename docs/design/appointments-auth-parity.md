# Appointments & auth parity (P2c — audit 1.5 / 1.6 / 1.10 / resend)

**Status:** Built (PR fix/parity-p2c-appointments-auth) · **Audit:**
[parity-audit-modules-2026-07.md](parity-audit-modules-2026-07.md) modules 1 + 11 ·
**No backend change** — arrive/OTP endpoints and the public phone/whatsapp
fields all pre-existed.

## Scope — the last P2 batch

1. **1.5 app cancel-dialog deposit warning — VERIFIED ALREADY PRESENT.** The
   audit called the app's dialog bare; the current
   `appointment_detail_screen._handleCancel` shows a `cancellationOutcome`
   block (forfait « à moins de X h » vs remboursé) — strictly richer than
   web's static line. Doc tick only, no code.
2. **1.6 « Appeler » is fake on the app + web detail has no contact action.**
   - App: the consumer detail's « Appeler » now fetches the salon
     (`getProviderById`) and launches `tel:` (the provider-detail idiom);
     no phone → « Numéro indisponible ». A « WhatsApp » button joins it when
     the salon has one (wa.me, digits-only — the same normalization as the
     salon page).
   - Web: the BFF enrichment (which already fetches the full public provider)
     adds `providerPhone`/`providerWhatsapp`; the consumer detail renders
     « Appeler » (tel:) + « WhatsApp » (wa.me) links when present.
3. **1.10 « Client arrivé » absent from both DETAIL pages** (J1b §4.2 debt).
   - App: the pro detail's confirmed block gains « Client arrivé » (same-day
     only, hidden once `arrivedAt` set) via `ProJournalProvider.arrive`
     (the existing `markArrived` seam); success snackbar + reload.
   - Web: `ProAppointmentDetailClient` gains the same button for confirmed
     same-day bookings without `arrivedAt`, calling the existing
     `arriveAppointment`; shows « Arrivé à HH:MM » once set.
4. **Email-code RESEND with cooldown on BOTH surfaces** (module 11) — the
   dormant phone-OTP screen's pattern (60 s cooldown), ported to the email
   code step everywhere: « Renvoyer le code (Xs) » disabled while counting,
   then active; resend re-calls the same request-OTP seam (server-side resend
   budget already enforces abuse limits).
   - App: consumer `login_screen` + pro `pro_login_screen` (Timer, restarts
     on each send).
   - Web: `LoginOptions` (consumer + inline booking) + `ProLoginOptions`
     (interval effect, restarts on each send).

## Tests

- App: widget tests — consumer login code step shows the countdown then an
  active « Renvoyer le code »; pro detail shows « Client arrivé » for a
  same-day confirmed booking (analyze 0).
- Web unit: none new (UI-only; helpers pre-tested).
- Web e2e: pro detail journey extends with Client arrivé → « Arrivé à » ;
  consumer detail shows Appeler/WhatsApp hrefs (stub provider has both);
  login code step shows the resend control.
