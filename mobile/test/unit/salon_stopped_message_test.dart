import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/booking_error_cta.dart';

/// What a surface says about a salon's STATE, as opposed to a booking's
/// refusal (§21 row 82, `salon-state-and-refusals.md` §6).
///
/// **Two doors, one product.** `bookingErrorCta`/`_messageFor` answer for a
/// refusal *code* the server returned to a write. This answers for a *status*
/// the server put on a document the client is holding. They are different
/// questions reached from opposite directions, and the whole risk is that they
/// drift into two different sentences for one fact — so the sentences are
/// pinned here against the exact strings
/// `api_appointment_service._messageFor` already ships.
void main() {
  group('the tense carries the distinction', () {
    test('a draft salon has never published — « pas encore »', () {
      expect(
        salonStoppedMessage('draft'),
        'Ce salon n’accepte pas encore de réservations en ligne.',
      );
    });

    test('a suspended salon was stopped — « ne … plus »', () {
      expect(
        salonStoppedMessage('suspended'),
        'Ce salon ne prend plus de rendez-vous sur Myweli.',
      );
    });

    test('the two are not the same sentence', () {
      // Row 82 exists because one code named both states and every surface
      // fell through to a generic apology. Collapsing the copy would undo it
      // one layer up.
      expect(
        salonStoppedMessage('draft'),
        isNot(salonStoppedMessage('suspended')),
      );
    });

    test('neither offers a retry', () {
      // §12 as amended by row 82: a retry control that cannot succeed is not a
      // way out, it is the dead end with a button on it. Retrying fixes
      // neither of these.
      for (final s in ['draft', 'suspended']) {
        expect(salonStoppedMessage(s), isNot(contains('Réessay')));
      }
    });
  });

  group('a live salon says nothing', () {
    test('active is silent', () {
      expect(salonStoppedMessage('active'), isNull);
    });

    test('and so is NO status at all — the NULL trap', () {
      // Seeded salons carry no stored status and Postgres reads NULL as
      // active. A switch whose default said « suspended » would put « ne prend
      // plus de rendez-vous » on every live salon in the country.
      expect(salonStoppedMessage(null), isNull);
    });

    test('an unknown future status is silent too — it fails OPEN', () {
      // Deliberate, and the same choice `isPublicSalon` makes on the server: a
      // fourth lifecycle state invented later should not start telling clients
      // a salon has stopped. The contract's enum is pinned so nobody adds one
      // without deciding.
      expect(salonStoppedMessage('archived'), isNull);
    });
  });

  test('the way out is the phrase the product already uses', () {
    // §17 — one way to say a thing. `kDiscoverSalonsCta` exists so a surface
    // that is not a refusal can reuse the WORDS without calling
    // `bookingErrorCta`, whose argument is precisely that it answers for two
    // booking codes and null for everything else.
    expect(kDiscoverSalonsCta.label, 'Découvrir des salons');
    expect(kDiscoverSalonsCta.href, '/');
    expect(bookingErrorCta('provider_suspended'), kDiscoverSalonsCta);
    // The pair: the constant must not have turned the function unconditional.
    expect(bookingErrorCta('slot_unavailable'), isNull);
  });
}
