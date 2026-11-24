import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/deposit_state.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/appointment.dart';

/// The deposit block of a client's own booking (appointment-detail-complete.md
/// §2.7, decision 197). The web reads the same file: a row changed on one
/// surface turns that surface red; a row changed in the file turns both red.
void main() {
  final now = DateTime.utc(2026, 11, 23, 12);
  final table =
      jsonDecode(
            File(
              '../docs/design/fixtures/deposit-state.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final rows = (table['rows'] as List).cast<Map<String, dynamic>>();

  Appointment appt({
    required AppointmentStatus status,
    required int minutes,
    required bool proof,
    double deposit = 5000,
  }) => Appointment(
    id: 'a',
    userId: 'u1',
    providerId: const SalonId('p1'),
    serviceIds: const ['s1'],
    appointmentDate: now.add(Duration(minutes: minutes)),
    status: status,
    totalPrice: 20000,
    depositAmount: deposit,
    balanceDue: 20000 - deposit,
    depositScreenshotUrl: proof ? 'deposit/u1/proof.jpg' : null,
    createdAt: DateTime.utc(2026),
  );

  test('the table holds every status, both sides of now and the boundary', () {
    expect(rows.length, greaterThanOrEqualTo(14));
    expect(rows.map((r) => r['status']).toSet(), {
      'pending',
      'confirmed',
      'completed',
      'noShow',
      'cancelled',
    });
    expect(rows.any((r) => r['minutesFromNow'] == 0), isTrue);
  });

  for (final r in rows) {
    final status = r['status'] as String;
    final minutes = r['minutesFromNow'] as int;
    final proof = r['proof'] as bool;
    test('$status at $minutes min, proof $proof → « ${r['label']} »', () {
      final s = depositState(
        appt(
          status: AppointmentStatus.values.byName(status),
          minutes: minutes,
          proof: proof,
        ),
        now,
      )!;
      expect(s.label, r['label']);
      expect(s.sentence, r['sentence']);
      expect(s.action?.name, r['action']);
      expect(s.showBalance, r['balance']);
    });
  }

  test('no deposit, no block — whatever the status', () {
    for (final status in AppointmentStatus.values) {
      expect(
        depositState(
          appt(status: status, minutes: 60, proof: false, deposit: 0),
          now,
        ),
        isNull,
        reason: status.name,
      );
    }
  });

  test('« Acompte confirmé » is gone: the salon confirms a booking, not a '
      'payment', () {
    for (final r in rows) {
      expect(r['label'], isNot('Acompte confirmé'), reason: '$r');
      expect(
        r['sentence'] ?? '',
        isNot(contains('confirmé la réception')),
        reason: '$r',
      );
    }
    for (final proof in [true, false]) {
      final s = depositState(
        appt(status: AppointmentStatus.confirmed, minutes: 60, proof: proof),
        now,
      )!;
      expect(s.label, isNot('Acompte confirmé'));
      expect(s.sentence, isNull);
    }
  });
}
