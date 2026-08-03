import 'dart:io';

import 'package:myweli_backend/src/salon_visibility.dart';
import 'package:test/test.dart';

/// One primitive answers « may an anonymous caller read this salon? » (T51,
/// Decision C).
///
/// **This file exists for the spelling, not the rule.** The rule is obvious;
/// the spelling is a trap that has already been documented twice in prose and
/// never once in an assertion. Seeded salons carry **no `status` key** and
/// Postgres reads a NULL column as active, so `status != 'active'` — the way
/// almost everyone writes it — hides every seeded salon and every in-memory
/// fixture. `booking_service.dart:65-67` records the trap as a comment; this
/// makes it executable, so the mutation that reintroduces it goes red instead
/// of shipping.
void main() {
  group('the HIDE form, not the negative form', () {
    test('a salon with no status key is public — the seeded shape', () {
      // The pair. Without this, `status != 'active'` passes every other
      // assertion in the file while refusing every salon in the seed.
      expect(isPublicSalon({'id': 'p1', 'name': 'Beauté Divine'}), isTrue);
    });

    test('an explicit null status is public — the Postgres shape', () {
      expect(isPublicSalon({'id': 'p1', 'status': null}), isTrue);
    });

    test('active is public', () {
      expect(isPublicSalon({'id': 'p1', 'status': 'active'}), isTrue);
    });

    test('draft and suspended are not', () {
      expect(isPublicSalon({'id': 'p1', 'status': 'draft'}), isFalse);
      expect(isPublicSalon({'id': 'p1', 'status': 'suspended'}), isFalse);
    });

    test('a missing salon is not public, and does not throw', () {
      // Every caller reads `byId` first; folding the null in here is what lets
      // a route say `if (!isPublicSalon(p))` once instead of twice, and it is
      // the same 404 either way — hidden and nonexistent are indistinguishable
      // on purpose (T51: no enumeration oracle).
      expect(isPublicSalon(null), isFalse);
    });
  });

  group('the status a client is told', () {
    test('a missing key normalises to active — resolved server-side, once', () {
      // Otherwise every client re-implements the NULL trap, and the first one
      // to spell it `?? 'draft'` silently stops a live salon from being booked.
      expect(publicSalonStatus({'id': 'p1'}), 'active');
      expect(publicSalonStatus({'id': 'p1', 'status': null}), 'active');
    });

    test('an explicit status is passed through unchanged', () {
      expect(publicSalonStatus({'status': 'draft'}), 'draft');
      expect(publicSalonStatus({'status': 'suspended'}), 'suspended');
      expect(publicSalonStatus({'status': 'active'}), 'active');
    });
  });

  test('the contract still has exactly the three statuses this rule knows', () {
    // The hide form fails OPEN: a fourth status invented tomorrow would be
    // public by default. That is the right default — a new state should not
    // silently vanish from discovery — but it is only SAFE if a fourth cannot
    // be added without someone reading this sentence.
    final yaml = File('../docs/api/openapi.yaml').readAsStringSync();
    final matches = RegExp(
      r'enum: \[draft, active, suspended\]',
    ).allMatches(yaml);
    expect(
      matches,
      isNotEmpty,
      reason:
          'the Provider.status enum moved or was reworded — re-read '
          'hiddenSalonStatuses before changing it',
    );
    expect(
      yaml.contains(RegExp(r'enum: \[draft, active, suspended, ')),
      isFalse,
      reason:
          'a fourth salon status was added: decide explicitly whether it is '
          'public, because isPublicSalon fails open and will publish it',
    );
  });
}
