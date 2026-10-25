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

    test('the Pro layers above them: no bare String salon slot either', () {
      // The doubles and API services of H1's interfaces, the Pro providers
      // and screens, the Pro router and the push handler. A `String` here
      // would still accept an account id from anything that calls it
      // directly rather than through the interface.
      final files = <String>[
        for (final dir in [
          'lib/services/mock',
          'lib/services/api',
          'lib/providers',
          'lib/screens/provider',
          'lib/core/push',
        ])
          for (final f in Directory(dir).listSync(recursive: true))
            if (f is File &&
                f.path.endsWith('.dart') &&
                !f.path.contains('/features/') &&
                (dir != 'lib/services/mock' && dir != 'lib/services/api' ||
                    RegExp(
                      r'_(pro_\w+|subscription|auth)_service\.dart$',
                    ).hasMatch(f.path)) &&
                (dir != 'lib/providers' || f.path.contains('/pro_')))
              f.path,
        'lib/core/router/pro_router.dart',
      ];
      // A booking's salon — `Appointment.providerId`, a String until H2.
      const h2 = {'lib/providers/pro_dashboard_provider.dart': 1};
      final found = <String, int>{
        for (final f in files)
          if (bareSalon.allMatches(code(f)).length case final n when n > 0)
            f: n,
      };
      expect(found, h2);
    });

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
      'lib/core/utils/salon_id.dart': 'the type, and `SalonId.none`',
      // The server's JSON — each model's `fromJson`.
      'lib/models/provider_user.dart': 'fromJson: the account default salon',
      'lib/models/salon_membership_info.dart': 'fromJson: « Mes salons »',
      'lib/models/pro_membership.dart': 'fromJson: the membership salon',
      'lib/models/team_member.dart': 'fromJson: a roster row salon',
      'lib/models/team_invitation.dart': 'fromJson: an invitation salon',
      'lib/models/salon_market.dart':
          'fromJson, and `of(Provider)` until H2 types `Provider.id`',
      'lib/models/salon_facts.dart':
          'fromJson, and `of(Provider)` until H2 types `Provider.id`',
      'lib/models/provider_session.dart':
          'fromJson: the persisted R6 selection',
      // A salon id carried by a link or a notification.
      'lib/core/router/pro_router.dart': 'the `?salon=` of a pushed booking',
      'lib/core/push/push_message_handler.dart':
          "the push payload's `providerId` or its route's `?salon=`",
      // The doubles mint and seed salon ids, as the server does.
      'lib/services/mock/mock_data.dart': 'the seed salons',
      'lib/services/mock/mock_auth_service.dart': 'a registered salon',
      'lib/services/mock/mock_pro_service.dart':
          'an added salon, and `Provider.id` until H2',
      'lib/services/mock/mock_session.dart': "the mock's default salon",
    };

    test('`SalonId(` is written only where a salon id is born', () {
      final writes = <String>{
        for (final f in Directory('lib').listSync(recursive: true))
          if (f is File &&
              f.path.endsWith('.dart') &&
              !f.path.contains('/screens/provider/features/') &&
              // `\b`: `resolveActingSalonId(` is a call, not a birth.
              RegExp(r'\bSalonId\(').hasMatch(code(f.path)))
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
