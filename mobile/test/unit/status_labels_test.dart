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
/// Does [src] map a booking status to a French word of its own?
///
/// **Widened after the review measured it against ten re-introduction
/// shapes and found it caught two.** The first version was written around
/// the code A9 deleted — `case` + immediate `return`, and the admin chip's
/// lowercase raw-string form — not around the rule. A Dart 3 switch
/// EXPRESSION, a `Map<String,String>` keyed on `'noShow'`, an extension, a
/// ternary, a `switch (status.name)`, or double quotes all walked past it,
/// and a switch-expression rewrite of the very code it replaced is one of
/// them.
///
/// Deliberately NOT matched: `case AppointmentStatus.noShow:` followed by
/// anything that is not a French string — the colour switches and the
/// deposit-label switch map the same enum to something that is not a status
/// word, and a pin that flags correct code earns an allowlist, which is how
/// a rule stops meaning anything.
bool keepsOwnVocabulary(String src) {
  const q = "['\"]"; // either quote style
  final patterns = [
    // `AppointmentStatus.noShow: 'Absent'` — a map literal
    RegExp('AppointmentStatus[.]noShow:\\s*$q'),
    // `case AppointmentStatus.noShow:\n  return 'Absent';`
    RegExp('case AppointmentStatus[.]noShow:\\s*\\n\\s*return\\s*$q'),
    // `AppointmentStatus.noShow => 'Absent'` — a Dart 3 switch expression
    RegExp('AppointmentStatus[.]noShow\\s*=>\\s*$q'),
    // `'noShow': 'Absent'` / `'noshow' => 'Absent'` — raw-string keyed
    RegExp('${q}no[_-]?[sS]how$q\\s*(:|=>)\\s*$q'),
    // a ternary on the enum that yields a string
    RegExp('AppointmentStatus[.]noShow\\s*\\?\\s*$q'),
  ];
  return patterns.any((p) => p.hasMatch(src));
}

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
        expect(
          find.text(entry.value),
          findsOneWidget,
          reason:
              'the kind switch already routes this status, so the pill '
              'is the right colour with the wrong word beside it',
        );
      });
    }
  });

  group('normalization — one status, however the API spells it', () {
    for (final raw in const ['noShow', 'NO_SHOW', 'no-show', 'noshow']) {
      testWidgets('$raw → « Absent »', (tester) async {
        await pumpApp(tester, home: Scaffold(body: StatusChip.forStatus(raw)));
        await tester.pump();
        expect(
          find.text('Absent'),
          findsOneWidget,
          reason:
              'the openapi enum is `noShow`; the kind switch already '
              'normalises, and the label must too — that asymmetry is the '
              'exact defect web fixed and mobile did not',
        );
      });
    }
  });

  testWidgets('an UNKNOWN status shows « — », never the wire value', (
    tester,
  ) async {
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

    expect(
      find.text('rescheduled_by_salon'),
      findsNothing,
      reason: 'an unrecognised wire value must never render',
    );
    expect(find.text('—'), findsOneWidget);
  });

  group('one vocabulary across the three surfaces', () {
    testWidgets('the consumer card and the admin chip agree on noShow', (
      tester,
    ) async {
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
          ),
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

      expect(
        find.text('Absent'),
        findsNWidgets(2),
        reason:
            'two surfaces, one word — today the admin one prints '
            '« noShow »',
      );
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
  /// **The gate that gates the gate**, and it exists because the pin below was
  /// DEAD for three commits and nothing noticed.
  ///
  /// A9's typography sweep walked `test/` converting `'` to `’`, and this
  /// file's patterns *contain* the forbidden character as data. All three
  /// regexes came out searching for `’` — which cannot delimit a Dart string,
  /// so no valid source could ever match and `offenders` was unconditionally
  /// empty. The sweep's commit message claimed the lesson had been learned and
  /// named `design_system_pin_test.dart` as excluded; it was written one file
  /// too narrowly, and the adversarial review found this.
  ///
  /// Excluding files by name does not scale — the next pin will have the same
  /// property and a different name. Asserting that each pattern still matches a
  /// known offender does, and it fails in the same commit that breaks it.
  test('…and the pin can still fail (the gate that gates the gate)', () {
    const shapes = <String, String>{
      'a map literal': "AppointmentStatus.noShow: 'Absent',",
      'a case + return':
          "case AppointmentStatus.noShow:\n        return 'Absent';",
      'a switch expression': "AppointmentStatus.noShow => 'Non présenté',",
      'a raw-string key': "'no_show': 'Absent',",
      'a ternary': "s == AppointmentStatus.noShow ? 'Absent' : ''",
      'double quotes': 'AppointmentStatus.noShow: "Absent",',
    };
    for (final entry in shapes.entries) {
      expect(
        keepsOwnVocabulary(entry.value),
        isTrue,
        reason:
            '${entry.key} must be detected — this is how a sixth '
            'vocabulary comes back',
      );
    }

    // …and it must NOT flag the shapes that map the same enum to something
    // that is not a status word. A pin that cries wolf gets an allowlist.
    expect(
      keepsOwnVocabulary(
        'case AppointmentStatus.noShow:\n        label = deposit;',
      ),
      isFalse,
      reason: 'the deposit-label switch is correct code',
    );
    expect(
      keepsOwnVocabulary('AppointmentStatus.noShow => AppColors.error,'),
      isFalse,
      reason: 'the colour switch is correct code',
    );
  });

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
        .where((f) => keepsOwnVocabulary(f.readAsStringSync()))
        .map((f) => f.path)
        .toList();

    expect(
      offenders,
      isEmpty,
      reason:
          'EIGHT separate vocabularies render noShow three different '
          'ways — Absent ×6, « Non présenté » ×2, and the raw enum in '
          'admin. (The census said five; the pin measured eight. It also '
          'first said nine, until it stopped counting a colour switch and a '
          'deposit-label switch as vocabularies.) One map, in $home, is what '
          'keeps the three surfaces agreeing — and agreeing with the web '
          'twin they were mirrored from.',
    );
  });
}
