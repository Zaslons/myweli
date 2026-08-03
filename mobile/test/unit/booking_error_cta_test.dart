import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/booking_error_cta.dart';

/// The way out, offered only where it leads somewhere (§12, §21 row 82).
///
/// §12 says an error state without a way out is « a crash with better
/// manners », and the naive reading of that is « put a button on every
/// error ». This file exists because that reading is wrong in one specific
/// place: for a taken slot the way out is another *time at this salon*, so a
/// « Découvrir des salons » button would walk the client out of the booking
/// they were in the middle of making.
///
/// Its twin is `bookingErrorCta` in `web/lib/booking/window.ts`. The two must
/// answer identically or the same refusal offers a different escape depending
/// on which surface the client happened to open — `booking-refusal.test.ts`
/// holds the other half.
void main() {
  group('a salon that is not live sends you to another salon', () {
    test('both provider codes carry the same label and destination', () {
      for (final code in ['provider_not_published', 'provider_suspended']) {
        final cta = bookingErrorCta(code);
        expect(cta, isNotNull, reason: '$code must offer a way out');
        expect(cta!.label, 'Découvrir des salons');
        expect(cta.href, '/');
      }
    });

    test('and the label is the one the product already uses', () {
      // §17 — one way to say a thing. The spec first drafted « Découvrir
      // d’autres salons »; the shipped phrase is this one, in web's
      // `AccountClient` empty states. Pinned so a future edit has to notice
      // it is changing a phrase that exists in two codebases.
      expect(
        bookingErrorCta('provider_suspended')!.label,
        isNot(contains('autres')),
      );
    });
  });

  group('nothing else does', () {
    test('a taken slot keeps the client here', () {
      // The pair. Without it the CTA could be unconditional and every
      // assertion above would still pass.
      expect(bookingErrorCta('slot_unavailable'), isNull);
    });

    test('a window breach keeps the client here too', () {
      // A14d's two codes already have their own one-tap jumps inside the slot
      // picker (« Aller au dernier jour disponible ») — a second, contrary
      // action pointing away from the salon would fight them.
      expect(bookingErrorCta('beyond_horizon'), isNull);
      expect(bookingErrorCta('too_soon'), isNull);
    });

    test('an unknown code, and no code at all, offer nothing', () {
      expect(bookingErrorCta('something_new'), isNull);
      expect(bookingErrorCta(null), isNull);
    });
  });
}
