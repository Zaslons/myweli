import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/constants/unnamed_salon.dart';
import 'package:myweli/core/utils/calendar_event.dart';
import 'package:myweli/models/team_invitation.dart';
import 'package:myweli/models/team_member.dart';
import 'package:myweli/widgets/team/invitation_card.dart';
import 'package:myweli/widgets/team/revoked_access_banner.dart';

import '../support/pump_app.dart';

/// docs/design/hygiene-batch9.md §2.9 (B9.10) — a salon with no name has one
/// set of words: « Salon » as a title, « le salon » in a client's sentence,
/// « votre salon » in the Pro session's. There were five forms, and an empty
/// string that `?? 'Salon'` let through as an empty title.
void main() {
  group('salonNameOr', () {
    test('a name is the name', () {
      expect(salonNameOr('Salon Awa', kUnnamedSalon), 'Salon Awa');
    });

    test('null, empty or blank is the unnamed word', () {
      expect(salonNameOr(null, kUnnamedSalon), 'Salon');
      expect(salonNameOr('', kUnnamedSalon), 'Salon');
      expect(salonNameOr('   ', kUnnamedSalonInSentence), 'le salon');
    });
  });

  test('the calendar event of an unnamed salon is « Rendez-vous — Salon »: a '
      'title, not « le salon » (and the web\'s, not « MyWeli »)', () {
    for (final name in const <String?>[null, '', '  ']) {
      final e = buildAppointmentCalendarEvent(
        providerName: name,
        serviceNames: const ['Coupe'],
        start: DateTime.utc(2026, 11, 2, 10),
        totalDurationMinutes: 30,
      );
      expect(e.title, 'Rendez-vous — Salon', reason: '$name');
    }
  });

  test('an invitation without a salon name keeps none: the screen says it, '
      'in the form its sentence needs', () {
    final i = TeamInvitation.fromJson(const {'id': 'i1', 'role': 'manager'});
    expect(i.salonName, '');
  });

  testWidgets('the invitation card of an unnamed salon: « Le salon vous '
      'invite comme … »', (tester) async {
    await pumpApp(
      tester,
      home: Scaffold(
        body: InvitationCard(
          invitation: const TeamInvitation(
            id: 'i1',
            providerId: 'p1',
            salonName: '',
            role: TeamRole.manager,
            roleLabel: 'Gérant',
            expiresAt: null,
          ),
          onAccept: () {},
          onDecline: () {},
        ),
      ),
    );
    expect(find.textContaining('Le salon vous invite comme'), findsOneWidget);
  });

  testWidgets('the revoked banner of an unnamed salon says the app\'s one '
      'sentence for a withdrawn access — never « Votre accès à votre salon »', (
    tester,
  ) async {
    await pumpApp(
      tester,
      home: const Scaffold(
        body: RevokedAccessBanner(salonName: kUnnamedOwnSalon),
      ),
    );
    expect(find.text('Votre accès à ce salon a été retiré.'), findsOneWidget);
  });

  // The pin: the words live in `unnamed_salon.dart`, nowhere else. « le
  // salon », « ce salon », « votre salon » as a whole literal are never a
  // label. « Salon » is one too — a column, a section, an admin title — so
  // it counts only as a fallback: after `??`, `==` or a ternary's `? … :`.
  test('no screen spells an unnamed salon itself', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) =>
              f.path.endsWith('.dart') &&
              !f.path.endsWith('core/constants/unnamed_salon.dart'),
        )
        .toList();
    expect(files.length, greaterThan(100), reason: 'run from mobile/');
    final fallback = RegExp(
      r"'(le salon|Le salon|ce salon|votre salon)'"
      r"|(\?\?|==|\?[^:?]*:)\s*'Salon'",
    );
    final hits = [
      for (final f in files)
        for (final (i, line) in f.readAsLinesSync().indexed)
          if (!line.trimLeft().startsWith('//') && fallback.hasMatch(line))
            '${f.path}:${i + 1}: ${line.trim()}',
    ];
    expect(hits, isEmpty, reason: 'use salonNameOr and kUnnamedSalon*');
  });
}
