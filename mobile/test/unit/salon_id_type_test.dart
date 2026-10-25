import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// docs/design/hygiene-batch9.md §2.8 (B9.9, decision 33, Q19–Q20) — a salon
/// id is a `SalonId`, so the compiler refuses what the R6 pin could not see:
/// an ACCOUNT id passed positionally to a salon-scoped call
/// (`createService(account.id, …)`, r6-salon-id-pin.md §3, mutation M10).
///
/// H1 types the Pro half — the salon that ACTS. H2 types the public salon
/// (booking, reviews, favorites, `Provider.id`). Until then a `SalonId`
/// passes into their `String` slots (`implements String`, Q20).
void main() {
  /// A Dart file's code, `//` comment lines removed.
  String code(String path) => File(
    path,
  ).readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join('\n');

  final bareSalon = RegExp(r'\bString\??\s+(providerId|salonId)\b');

  group('H1 — the Pro half takes a SalonId', () {
    for (final f in [
      'lib/services/interfaces/pro_service_interface.dart',
      'lib/services/interfaces/pro_clients_service_interface.dart',
      'lib/services/interfaces/pro_artist_service_interface.dart',
      'lib/services/interfaces/subscription_service_interface.dart',
      'lib/services/interfaces/auth_service_interface.dart',
    ]) {
      test('${f.split('/').last}: no salon slot is a bare String', () {
        final src = code(f);
        expect(
          [
            for (final m in bareSalon.allMatches(src))
              src.substring(0, m.start).split('\n').length,
          ],
          isEmpty,
          reason: 'the lines where a salon id is still a String',
        );
      });
    }

    test('the Pro models hold a SalonId', () {
      for (final (file, field) in [
        ('lib/models/provider_user.dart', 'providerId'),
        ('lib/models/salon_membership_info.dart', 'salonId'),
        ('lib/models/pro_membership.dart', 'salonId'),
        ('lib/models/team_member.dart', 'providerId'),
        ('lib/models/team_invitation.dart', 'providerId'),
        ('lib/models/salon_market.dart', 'salonId'),
        ('lib/models/salon_facts.dart', 'salonId'),
      ]) {
        expect(
          code(file),
          matches(RegExp('final SalonId\\?? $field;')),
          reason: '$file: $field',
        );
      }
    });

    test('the resolver answers a SalonId', () {
      expect(
        code('lib/providers/pro_auth_provider.dart'),
        contains('SalonId? get activeSalonId'),
      );
    });

    test(
      'the type is a String at run time, refused as one in a salon slot',
      () {
        final src = code('lib/core/utils/salon_id.dart');
        expect(
          src,
          contains(
            'extension type const SalonId(String value) implements String',
          ),
        );
      },
    );
  });

  group('the birth pin', () {
    // Where a salon id may be MADE from a string. Everywhere else receives
    // one. A `SalonId(account.id)` written tomorrow is visible in review AND
    // fails here — the type makes the mistake loud; this keeps it rare.
    const born = <String, String>{
      'lib/core/utils/salon_id.dart': 'the type, and `SalonId.of` for JSON',
    };

    test('`SalonId(` is written only where a salon id is born', () {
      final writes = <String>{
        for (final f in Directory('lib').listSync(recursive: true))
          if (f is File &&
              f.path.endsWith('.dart') &&
              !f.path.contains('/screens/provider/features/') &&
              code(f.path).contains('SalonId('))
            f.path,
      };
      expect(
        writes,
        unorderedEquals(born.keys),
        reason:
            'A new place makes a SalonId from a string. If the string IS a '
            'salon id from the server, a route or the session, add the file '
            'to `born` with why; if it is an account id, that is the R6 '
            'defect the type exists to refuse.',
      );
    });
  });
}
