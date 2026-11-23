import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/cancellation_policy.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/appointment.dart';

/// The cancel sentence is ONE sentence on two surfaces: the app's
/// `cancellationNotice` must say what the web's says, word for word
/// (docs/design/consumer-app-truth.md §2.2, B12.11). The web's words were
/// approved first (web-true-sentences.md §3); a change on either side alone
/// turns this red.
///
/// It compares the fixed fragments only: the amount and the delay are
/// formatted by each surface.
void main() {
  // The web source, with its `\u00a0` escapes read as the character.
  final web = File(
    '../web/lib/account/appointments.ts',
  ).readAsStringSync().replaceAll(r'\u00a0', '\u00a0');

  // Every sentence the app can say, from its own function.
  final at = DateTime(2026, 6, 21, 18);
  Appointment appt({String? proof = 'p.jpg', int hours = 24}) => Appointment(
    id: 'a',
    userId: 'u1',
    providerId: const SalonId('p1'),
    serviceIds: const ['s1'],
    appointmentDate: at,
    status: AppointmentStatus.confirmed,
    totalPrice: 20000,
    depositAmount: 5000,
    depositScreenshotUrl: proof,
    cancellationWindowHours: hours,
    createdAt: DateTime(2026),
  );
  final app = [
    cancellationNotice(appt(proof: null), at.subtract(const Duration(days: 2))),
    cancellationNotice(appt(), at.subtract(const Duration(days: 2))),
    cancellationNotice(appt(), at.subtract(const Duration(hours: 2))),
    cancellationNotice(appt(), at),
    cancellationNotice(appt(hours: 0), at.subtract(const Duration(hours: 2))),
  ].map((n) => n!.text).join('\n');

  const fragments = [
    'Vous n’avez envoyé aucun justificatif d’acompte pour ce rendez-vous.',
    'D’après la règle du salon, votre acompte de ',
    ' ne sera pas remboursé, car',
    ' l’heure du rendez-vous est passée.',
    ' vous annulez moins de ',
    '\u00a0h avant',
    ' vous revient, car vous annulez ',
    'avant l’heure du rendez-vous',
    'plus de ',
    'Voyez avec le salon pour le récupérer\u00a0: MyWeli ne détient aucun '
        'acompte.',
  ];

  test('the web file is the one that holds the sentence', () {
    expect(web, contains('export function cancellationNotice('));
  });

  for (final f in fragments) {
    test('both say « ${f.trim()} »', () {
      expect(web, contains(f), reason: 'the web no longer says it');
      expect(app, contains(f), reason: 'the app no longer says it');
    });
  }
}
