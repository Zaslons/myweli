import { describe, expect, it } from 'vitest';
import {
  type Appointment,
  canReschedule,
  isUpcoming,
  rebookHref,
  salonIsLive,
  salonStoppedMessage,
  salonStoppedMessageFor,
} from '../lib/account/appointments';
import { bookingErrorCta, conflictMessage } from '../lib/booking/window';

/// A client's own booking at a salon that STOPPED (§21 row 82, §6 cells 6–7).
///
/// Decision C closes the public salon read, so a salon that goes `draft` or
/// `suspended` leaves every anonymous surface. The client who booked there is
/// not an anonymous surface — the server hydrates their booking — so the
/// account has to do two things it never did: SAY the salon stopped, and stop
/// offering the actions the server would refuse.
///
/// Its twin is `mobile/test/unit/salon_stopped_message_test.dart`. The two must
/// answer identically, or the same salon reads as stopped on one surface and
/// bookable on the other.
const base: Appointment = {
  id: 'a1',
  status: 'confirmed',
  appointmentDate: new Date(Date.now() + 86_400_000).toISOString(),
  providerId: 'p1',
  providerSlug: 'beaute-divine',
};

describe('the tense carries the distinction', () => {
  it('a draft salon has never published — « pas encore »', () => {
    expect(salonStoppedMessageFor('draft')).toBe(
      'Ce salon n’accepte pas encore de réservations en ligne.',
    );
  });

  it('a suspended salon was stopped — « ne … plus »', () => {
    expect(salonStoppedMessageFor('suspended')).toBe(
      'Ce salon ne prend plus de rendez-vous sur Myweli.',
    );
  });

  it('and it is the SAME sentence the booking refusal already uses', () => {
    // One product fact reached from two directions — a status on a document
    // the client holds, and a code the server returned to a write. Different
    // wording for the same fact is exactly the drift §17 forbids, and the
    // reason this assertion exists rather than a comment.
    const asClient = { audience: 'client' as const, taken: 'X', fallback: 'Y' };
    expect(salonStoppedMessageFor('draft')).toBe(
      conflictMessage('provider_not_published', asClient),
    );
    expect(salonStoppedMessageFor('suspended')).toBe(
      conflictMessage('provider_suspended', asClient),
    );
  });

  it('the two states do not share a sentence', () => {
    expect(salonStoppedMessageFor('draft')).not.toBe(
      salonStoppedMessageFor('suspended'),
    );
  });
});

describe('a live salon says nothing', () => {
  it('active is silent', () => {
    expect(salonStoppedMessageFor('active')).toBeNull();
    expect(salonIsLive({ ...base, providerStatus: 'active' })).toBe(true);
  });

  it('and so is NO status at all — the NULL trap', () => {
    // Seeded salons carry no stored status and Postgres reads NULL as active.
    // `providerStatus === 'active'` at a call site would mark every one of
    // them stopped.
    expect(salonStoppedMessageFor(null)).toBeNull();
    expect(salonStoppedMessageFor(undefined)).toBeNull();
    expect(salonIsLive(base)).toBe(true);
    expect(salonStoppedMessage(base)).toBeNull();
  });

  it('an unknown future status is silent too — it fails OPEN', () => {
    // The same choice `isPublicSalon` makes on the server: a fourth lifecycle
    // state invented later must not start telling clients a salon stopped.
    expect(salonStoppedMessageFor('archived')).toBeNull();
  });
});

describe('what a stopped salon withholds, and what it keeps', () => {
  const stopped: Appointment = { ...base, providerStatus: 'suspended' };

  it('« Réserver à nouveau » is withheld — the server would refuse it', () => {
    expect(rebookHref(stopped)).toBeNull();
    // The pair: the link must still work for a live salon, or « always null »
    // would pass.
    expect(rebookHref(base)).toContain('/beaute-divine/reserver');
  });

  it('« Reporter » is withheld', () => {
    expect(canReschedule(stopped)).toBe(false);
    expect(canReschedule(base)).toBe(true);
  });

  it('but the booking is still UPCOMING — it keeps its calendar entry', () => {
    // The distinction this slice had to introduce: `canReschedule` was doing
    // duty as « is upcoming » at two call sites (the calendar export and the
    // « prochaines visites » card), and folding the salon state into it would
    // have silently taken the calendar entry away from a client whose salon
    // shut down.
    expect(isUpcoming(stopped)).toBe(true);
  });

  it('and a PAST booking is neither, whatever the salon is doing', () => {
    const past: Appointment = {
      ...base,
      appointmentDate: new Date(Date.now() - 86_400_000).toISOString(),
    };
    expect(isUpcoming(past)).toBe(false);
    expect(canReschedule(past)).toBe(false);
  });
});

describe('the way out', () => {
  it('is the phrase the product already ships', () => {
    // §17 — one way to say a thing. `bookingErrorCta` owns the pairing; this
    // asserts the account surface points at the same place rather than
    // minting a second « discover » link.
    expect(bookingErrorCta('provider_suspended')).toEqual({
      label: 'Découvrir des salons',
      href: '/',
    });
    // The pair: the CTA is still gated, not universal. A taken slot's way out
    // is another TIME at this salon, not another salon.
    expect(bookingErrorCta('slot_unavailable')).toBeNull();
  });
});

describe('the closed browse route, and the retry that cannot succeed', () => {
  it('the salon-is-gone code gets the way out, not a retry', () => {
    // Decision C makes `provider_not_found` reachable by a client holding a
    // stale link: `/availability` answers it for a salon it will no longer
    // serve, indistinguishably from an unknown id (the browse route answers to
    // ANYONE, so naming the state there would be an enumeration oracle).
    //
    // Before this, the funnel rendered « Impossible de charger les créneaux.
    // Vérifiez votre connexion. » beside a « Réessayer » that could never
    // succeed — blaming the connection for a salon-state problem, on the exact
    // surface row 82 is about.
    expect(bookingErrorCta('provider_not_found')).toEqual({
      label: 'Découvrir des salons',
      href: '/',
    });
  });

  it('and the sentence is the status-agnostic one', () => {
    // NOT the tense-carrying pair: the 404 carries no status, by construction.
    // This is the same sentence the mobile landing screens use, and it must
    // stay identical to `kSalonUnavailableMessage` in
    // `mobile/lib/core/utils/booking_error_cta.dart`.
    expect(
      conflictMessage('provider_not_found', {
        audience: 'client' as const,
        taken: 'X',
        fallback: 'Y',
      }),
    ).toBe('Ce salon n’est plus disponible sur Myweli.');
  });

  it('a dropped connection is still a retry — the pair', () => {
    // Without this, folding `provider_not_found` in could have made the CTA
    // unconditional, and the one failure where « Réessayer » is RIGHT would
    // have lost it.
    expect(bookingErrorCta('slot_unavailable')).toBeNull();
    expect(bookingErrorCta(undefined)).toBeNull();
  });
});
