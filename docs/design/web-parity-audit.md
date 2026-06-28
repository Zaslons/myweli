# Web ↔ app parity audit (flow / user-story)

| | |
|---|---|
| **Purpose** | Check the shipped web surfaces against the mobile app's **flow & user story** (not visual design — desktop may differ). |
| **Rule** | Memory `web-mirror-app-flow`: web mirrors the app's flow per screen; design adapts to the larger screen / different navigation. |
| **Date** | 2026-06-28. **Status:** audit recorded; remediation sequenced (see §3). |

## 1. Result — most surfaces already match
| Web surface | App screen | Flow match | Notes |
|---|---|---|---|
| Booking `/(slug)/reserver` | `booking/booking_hub` + steps | ✅ | service→staff→slot→confirm(+OTP)→deposit. Only the deposit-screenshot **upload** is deferred to the app (flagged). |
| Account `/mon-compte` | `appointments/my_bookings` | ✅ | Tabs **À venir / Passés / Annulés** match the app exactly; cancel + deposit-consequence match. |
| Login `/connexion`, `/pro/connexion` | `auth/phone_login`→`otp_verify` | ✅ | One page vs two screens = desktop choice; same user story. |
| Pro `/pro/rendez-vous` | `provider/appointments` | ✅ | Calendrier + Liste (Aujourd'hui/À venir/En attente/Tous) — built to mirror (M7.1). |
| Provider `/(slug)` | `providers/provider_detail` | ✅ mostly | Services, Horaires, Avis, **Contact (Appeler + WhatsApp)**, À propos present. See gaps §2. |

## 2. Gaps to close (flow / user-story only)
| # | Surface | Missing vs the app | Severity |
|---|---|---|---|
| ~~**G1**~~ ✅ | **Home `/`** | **Closed (M8.1):** discovery home (hero service+commune search → landings/`/recherche` · category tiles · Salons populaires · "Partout à Abidjan" directory · value props · FAQ) + `/recherche` results. Map view → folded into M8.2. Spec: [web-m8-1-discovery.md](web-m8-1-discovery.md). | ~~High~~ done |
| **G2** | Provider `/(slug)` | Missing **carte / localisation (map)**, **Avant / Après** (before-after gallery), **artistes / équipe**. | Medium |
| ~~**G3**~~ ✅ | Pro home `/pro` "Aujourd'hui" | **Closed (7.3d):** revenue cards (aujourd'hui + ce mois) added to `/pro` from `GET /providers/{id}/dashboard`. (The « Configurer mon profil » nudge follows in 7.3e with `/pro/profil`.) | ~~Medium~~ done |
| **G4** | Account `/mon-compte` | App offers, beyond cancel: **"Réserver à nouveau" (rebook)**, **laisser un avis**, **favoris**, profile **edit**, notif-prefs, data export, deposit-screenshot submit. (Already logged as M6 deferrals.) | Medium |

**Deliberate, not gaps:** deposit-screenshot **upload** stays app-side for now; account **deletion / data export** stay app-only (sensitive). Provider-page contact (Appeler/WhatsApp) is already on web.

## 3. Remediation plan (sequenced — owner approved 2026-06-28)
1. **M7.2** — manage bookings (detail + accept/reject/complete/no-show/cancel), mirroring `provider/appointment_detail`.
2. **M7.3** — catalogue / dispo / profil / abonnement **+ fold G3** (pro "Tableau de bord": revenue stats + "Configurer mon profil" — consume the existing `GET /providers/{id}/dashboard`, no new endpoint).
3. **M8 — consumer parity pass:**
   - **M8.1 ✅ G1** discovery home + `/recherche` ([web-m8-1-discovery.md](web-m8-1-discovery.md)).
   - **M8.2 G2** provider page: map + Avant/Après + artistes (+ map view from G1).
   - **M8.3 G4** account: rebook + laisser un avis + favoris (+ profile edit).

Each item: study the app screen first, write/extend its `web-*.md` spec, mirror the
flow, adapt the layout for desktop. Cross-link back here as items close.
