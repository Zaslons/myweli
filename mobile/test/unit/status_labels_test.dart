import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/admin/widgets/status_chip.dart';
import 'package:myweli/widgets/booking/appointment_card.dart';
import 'package:myweli/widgets/booking/compact_appointment_tile.dart';
import 'package:provider/provider.dart';

import '../support/pump_app.dart';

/// A9 — one French vocabulary for a booking status (SYSTEM.md §17, §18).
///
/// **The product's only real user-visible English string is here, and it is
/// ours, not the framework's.** `admin/widgets/status_chip.dart` routes
/// `confirmed`, `cancelled` and `noshow` through its *kind* switch — tinting
/// the pill correctly — and then falls through `_frenchLabel` to
/// `raw ?? '—'`, printing the raw enum beside the correctly-coloured chip.
///
/// `web/components/StatusChip.tsx:55` documents this exact fix as one it
/// mirrored **from** mobile:
///
/// > mobile's `StatusChip.forStatus` treats `NO_SHOW`/`noShow`/`no-show` as one
/// > status, and a label that only matches the exact spelling would tint the
/// > pill red while printing the raw enum string beside it (the review's catch).
///
/// Web shipped `NORMALIZED_FR`; mobile — the twin it was mirrored from — never
/// got it. WEB-SYSTEM §15 row 18 records the web half; nothing records this one.
///
/// **The vocabulary is web's**, because web already had to settle it across
/// consumer, pro and admin: `web/lib/account/appointments.ts:94-100`, where
/// `noShow: 'Absent'` carries the comment `// app label`. Mobile's two pro
/// surfaces say « Non présenté » — so mobile disagrees with mobile, and with
/// its own twin.
void main() {
  // `AppointmentCard` resolves the salon through `ProviderProvider`, which
  // reads `serviceLocator.providerService` — so this suite needs DI, the same
  // way `appointment_card_test.dart:15` does.
  setUpAll(setupDependencyInjection);

  Appointment appointment(AppointmentStatus status) => Appointment(
        id: 'a1',
        userId: 'u1',
        providerId: 'p1',
        serviceIds: const ['s1'],
        appointmentDate: DateTime(2026, 7, 20, 14, 30),
        status: status,
        totalPrice: 15000,
        createdAt: DateTime(2026, 7, 1),
      );

  group('the English leak — admin prints the raw enum', () {
    for (final entry in const {
      'confirmed': 'Confirmé',
      'cancelled': 'Annulé',
      'completed': 'Terminé',
      'pending': 'En attente',
    }.entries) {
      testWidgets('${entry.key} → « ${entry.value} »', (tester) async {
        await pumpApp(
          tester,
          home: Scaffold(body: StatusChip.forStatus(entry.key)),
        );
        await tester.pump();
        expect(find.text(entry.value), findsOneWidget,
            reason: 'the kind switch already routes this status, so the pill '
                'is the right colour with the wrong word beside it');
      });
    }
  });

  group('normalization — one status, however the API spells it', () {
    for (final raw in const ['noShow', 'NO_SHOW', 'no-show', 'noshow']) {
      testWidgets('$raw → « Absent »', (tester) async {
        await pumpApp(
          tester,
          home: Scaffold(body: StatusChip.forStatus(raw)),
        );
        await tester.pump();
        expect(find.text('Absent'), findsOneWidget,
            reason: 'the openapi enum is `noShow`; the kind switch already '
                'normalises, and the label must too — that asymmetry is the '
                'exact defect web fixed and mobile did not');
      });
    }
  });

  testWidgets('an UNKNOWN status shows « — », never the wire value',
      (tester) async {
    // Written because a mutation caught the gap: restoring the old
    // `?? raw` fallback kept every other assertion in this file green, since
    // they all test statuses the map knows. But falling back to the raw string
    // IS the defect — it is how `noShow` reached a user's screen. A status the
    // app does not recognise is not a status the app should print.
    await pumpApp(
      tester,
      home: Scaffold(body: StatusChip.forStatus('rescheduled_by_salon')),
    );
    await tester.pump();

    expect(find.text('rescheduled_by_salon'), findsNothing,
        reason: 'an unrecognised wire value must never render');
    expect(find.text('—'), findsOneWidget);
  });

  group('one vocabulary across the three surfaces', () {
    testWidgets('the consumer card and the admin chip agree on noShow',
        (tester) async {
      await pumpApp(
        tester,
        // `AppointmentCard` reads the salon through a `Consumer` — the tile
        // below does not, which is why only this one needs the provider.
        // `.value`, not `create:` — a lazily-created provider that is torn
        // down mid-suite throws `Null is not a subtype of ProviderProvider`
        // out of `_CreateInheritedProviderState.dispose`, and it surfaces
        // while the NEXT test is pumping, so it reads as that test failing.
        // Fixture detail, not a product fact; recorded so the next person does
        // not spend the same twenty minutes on it.
        providers: [
          ChangeNotifierProvider<ProviderProvider>.value(
            value: ProviderProvider(),
          )
        ],
        home: Scaffold(
          body: Column(
            children: [
              AppointmentCard(
                appointment: appointment(AppointmentStatus.noShow),
                onTap: () {},
              ),
              StatusChip.forStatus('noShow'),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Absent'), findsNWidgets(2),
          reason: 'two surfaces, one word — today the admin one prints '
              '« noShow »');
    });

    testWidgets('…and so does the compact tile', (tester) async {
      await pumpApp(
        tester,
        home: Scaffold(
          body: CompactAppointmentTile(
            appointment: appointment(AppointmentStatus.noShow),
            providerName: 'Salon Awa',
            onTap: () {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Absent'), findsOneWidget);
    });
  });

  /// The behavioural tests above reach three of the five maps. The two pro ones
  /// live in private `_statusFr` constants inside stateful screens that need a
  /// provider tree to pump — so a pin covers the CLASS instead, which is also
  /// the only thing that stops a sixth map appearing.
  ///
  /// Named rather than implied, per A8's lesson: gates that reach three of five
  /// call sites are three call sites of coverage.
  test('no screen keeps its own status vocabulary (§17, §18)', () {
    // §18: a market/domain fact lives in `core/`, never inlined in a widget —
    // "hardcoding a market fact in a widget fails review even when it works for
    // Côte d'Ivoire". A French status label is that kind of fact.
    const home = 'lib/core/utils/status_labels.dart';
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith(home.substring('lib/'.length)))
        .where((f) {
          final src = f.readAsStringSync();
          // A status→FRENCH-STRING map, in any of the three shapes the app
          // uses. Deliberately NOT every `case AppointmentStatus.noShow:` —
          // the first draft of this pin matched those and swept up a colour
          // switch and a deposit-label switch, which map the same enum to
          // something that is not a status word. A pin that flags correct code
          // gets an allowlist, and an allowlist is how a rule stops meaning
          // anything.
          return
              // `AppointmentStatus.noShow: 'Absent',`
              RegExp('AppointmentStatus[.]noShow:\\s*’').hasMatch(src) ||
                  // `case AppointmentStatus.noShow:\n  return 'Absent';`
                  RegExp('case AppointmentStatus[.]noShow:\\s*\\n\\s*return ’')
                      .hasMatch(src) ||
                  // the admin chip's raw-string form — `'noshow' => 'Absent'`,
                  // NOT `'noshow' => AdminChipKind.danger`, which is the KIND
                  // switch and is correct where it is. The pin's first draft
                  // flagged that too.
                  RegExp('’noshow’[^\\n]*=>\\s*’').hasMatch(src);
        })
        .map((f) => f.path)
        .toList();

    expect(offenders, isEmpty,
        reason: 'EIGHT separate vocabularies render noShow three different '
            'ways — Absent ×6, « Non présenté » ×2, and the raw enum in '
            'admin. (The census said five; the pin measured eight. It also '
            'first said nine, until it stopped counting a colour switch and a '
            'deposit-label switch as vocabularies.) One map, in $home, is what '
            'keeps the three surfaces agreeing — and agreeing with the web '
            'twin they were mirrored from.');
  });
}
