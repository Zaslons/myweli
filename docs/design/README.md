# Design specs

Every non-trivial part of Myweli gets a **design spec here before any code is written**. A spec is the single, authoritative description of how that part should work — so the build is deliberate, professional, and nothing is missed.

This is a standing rule, not a suggestion (see the `myweli-dev-guardrails` / `myweli-backend-guardrails` skills and the `design-spec-per-part` memory).

> **Before any UI/design work, read [DESIGN-STANDARDS.md](DESIGN-STANDARDS.md)** — the canonical design + UX standards (identity, tokens, components, the four-states/French rules, the consistency sweep). Plus the part's spec below. (Rule: `check-design-standards-first`.)

## The workflow — for every part

1. **Invoke the relevant guardrails skill** (`myweli-dev-guardrails`, and `myweli-backend-guardrails` for anything under `backend/`).
2. **Re-confirm fit** with the agreed ROADMAP, rules, security model, patterns, structure, and architecture — don't drift.
3. **Write the spec** as `docs/design/<part>.md`, copying [`TEMPLATE.md`](TEMPLATE.md). Fill in every applicable section in detail.
4. **Align** on the spec with the user *before* building.
5. **Cross-link** the spec from the files it governs — the [ROADMAP](../ROADMAP.md) entry, the code files (a `// Design: docs/design/<part>.md` reference near the top), and the [API contract](../api/openapi.yaml) — so the design stays discoverable as the source of truth.
6. **Build** to the spec. If reality forces a change, **update the spec in the same PR** (keep it honest, like the PRD/ROADMAP).

When is a spec required? Any new feature, slice, endpoint, screen, or integration. Trivial fixes (typos, a one-line bug, a dependency bump) don't need one.

## Spec status legend

`Draft` (being written / under review) → `Approved` (aligned, ready to build) → `Built` (shipped; spec reflects what exists) → `Superseded` (replaced — link the successor).

## Index

| Part | Spec | Status |
|------|------|--------|
| Admin / ops console — backend (KYC · moderation · mgmt · disputes · analytics) | [admin-console.md](admin-console.md) | Slices 1–3 built |
| Admin / ops console — UI (Flutter Web) | [admin-console-ui.md](admin-console-ui.md) | Complete — dashboard · KYC · moderation · mgmt + support views · disputes · audit log (Journal) |
| Messaging & notifications (WhatsApp + SMS, Twilio) | [messaging-notifications.md](messaging-notifications.md) | Built (PR A foundation + OTP · PR B events + reminder scheduler); real BSP creds = ops |
| Consumer deposit / Mobile Money flow | [consumer-deposit.md](consumer-deposit.md) | Built (B1 + B2) |
| Booking duration-overlap exclusion (btree_gist) | [booking-overlap-exclusion.md](booking-overlap-exclusion.md) | Built |
| Pro KYC (provider verification) | [pro-kyc.md](pro-kyc.md) | Built (provider side) |
| Pro staff (artists) management | [pro-artists.md](pro-artists.md) | Built |
| Consumer reviews | [consumer-reviews.md](consumer-reviews.md) | Built |
| Consumer favorites | [consumer-favorites.md](consumer-favorites.md) | Built |
| Pro deposit policy management | [pro-deposit-policy.md](pro-deposit-policy.md) | Built |
| Image upload pipeline (Cloudflare R2) | [pro-image-upload-pipeline.md](pro-image-upload-pipeline.md) | Built |
| Pro gallery photos (URL list) | [pro-gallery.md](pro-gallery.md) | Built |
| Pro-side reschedule | [pro-reschedule.md](pro-reschedule.md) | Built |
| Provider earnings detail | [provider-earnings.md](provider-earnings.md) | Built |
| Pro manual (walk-in/phone) booking | [pro-manual-booking.md](pro-manual-booking.md) | Built |
| Provider dashboard stats | [provider-dashboard-stats.md](provider-dashboard-stats.md) | Built |
| Pro catalogue app wiring (ApiProService → backend) | [pro-catalogue-app-wiring.md](pro-catalogue-app-wiring.md) | Built |
| Provider services & availability (backend) | [provider-services-availability-backend.md](provider-services-availability-backend.md) | Built |
| _Spec template_ | [TEMPLATE.md](TEMPLATE.md) | — |

> Add a row per spec as it's created. Keep newest at the top.
