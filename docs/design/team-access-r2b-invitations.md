# Team access R2b — invitations & the Équipe API (module `access`, slice A2 server side)

**Status:** Built (PR feat/team-access-r2b-invitations) · **Module doc:**
[modules/access.md](../modules/access.md) §5.2/§6/§7 · **Backend + contract**
(the R3/R5 UIs consume this). Builds on R2a (offers/seats) and R1
(memberships/capabilities).

## Goal & scope

The complete invitation lifecycle: an owner invites an email as Manager /
Réception / Collaborateur (artist-linked); the invitee receives a branded
email, signs in with the NORMAL login (Google/email code) and — instead of
« compte introuvable » — gets « {Salon} vous invite comme {Rôle} »; accepting
creates a **bare member account** (no salon, no business fields) and lands a
working session. Owners manage the team (change role, resend, revoke —
revocation effective on the member's next request, T38). Every action is
audited; seat/offer gates ride R2a.

## The state machine

```
invite (owner, membersManage)
  → invited (expires 7 j, resends 3)
      → accept (identity-proof or session; email must match) → active
      → decline → row deleted
      → revoke (owner) → revoked
      → expire → invisible to the bridge; resend resets the clock
active → revoke → revoked (immediate — per-request resolution)
```

Gates on invite: role ∈ {manager, reception, staff} (`invalid_role`) · staff ⇒
salon-owned artist (`artist_required`/`artist_not_found`) · duplicate → 409
`member_exists` · no live offer → 409 `offer_required` · seats full → 409
`seat_limit` (used = active+invited incl. owner) · >20 invites/salon/day →
429 `invite_rate_limited` (T37). Owner row immutable (`owner_protected`, T36).

## The login bridge (§5.2)

The three identity routes return **202 `{invitations: [...]}`** when the
verified email has pending invitations and no account exists (else the usual
404). The unauthenticated accept (`POST /auth/provider/invitations/accept`)
carries the SAME identity proof as login (idToken or email+code — the email
code survives the login attempt unconsumed by design) → creates the bare
account (`createMemberAccount`: no business fields; the R1 provisioning guard
keeps salons from auto-creating) → activates the membership → ProviderSession.
Authed accounts use `GET /me/provider/invitations` + authed accept/decline
(the session is the proof; the email must match). Responses never reveal
whether an email has an account (no enumeration).

## Endpoints

Owner: `GET/POST /me/provider/members` · `PATCH /me/provider/members/{id}` ·
`POST …/{id}/revoke|resend`. Invitee: `GET /me/provider/invitations` ·
`POST /me/provider/invitations/{id}/accept|decline` ·
`POST /auth/provider/invitations/accept|decline` (identity-proof). Login 202
on google/email-otp/phone-otp verify.

## Threat rows

T36 (escalation) · T37 (spam/phish) · T38 (stale sessions) · T39 (client
base, R1 cross-ref) · T40 (own-scope, lands with R4) — see BACKEND.md §7.

## Tests

The §9 REQUIRED list: the state machine, every validation, every endpoint's
success+4xx+405, both live login bridges, the bare-account+guard+session
proof, email-mismatch and expiry negatives, and the T36/T37/T38 security
suite.
