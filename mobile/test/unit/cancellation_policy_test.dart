import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/utils/cancellation_policy.dart';
import 'package:myweli/core/utils/formatters.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/appointment.dart';

/// The cancel confirmation's sentence (docs/design/consumer-app-truth.md
/// §2.2): the salon's rule, the web's words, never a promise of our own.
void main() {
  final at = DateTime(2026, 6, 21, 18, 0);
  // The amount as the app writes it (French grouping, narrow no-break space).
  final fcfa = Formatters.formatCurrency(5000, currency: 'XOF');

  Appointment appt({
    double deposit = 5000,
    String? proof = 'https://cdn.myweli.com/deposit/p.jpg',
    int windowHours = 24,
    String? clientName,
  }) => Appointment(
    id: 'a1',
    userId: 'u1',
    providerId: const SalonId('p1'),
    serviceIds: const ['s1'],
    appointmentDate: at,
    durationMinutes: 60,
    totalPrice: 20000,
    depositAmount: deposit,
    status: AppointmentStatus.confirmed,
    createdAt: DateTime(2026, 6, 1),
    cancellationWindowHours: windowHours,
    depositScreenshotUrl: proof,
    clientName: clientName,
  );

  CancellationNotice? at_(Appointment a, Duration before) =>
      cancellationNotice(a, at.subtract(before));

  test('no deposit: nothing to say', () {
    expect(at_(appt(deposit: 0), const Duration(hours: 1)), isNull);
  });

  test('a booking the salon typed: nothing to say', () {
    expect(at_(appt(clientName: 'Awa'), const Duration(hours: 1)), isNull);
  });

  test('no proof sent: says so, and promises nothing', () {
    for (final proof in [null, '']) {
      final n = at_(appt(proof: proof), const Duration(hours: 48))!;
      expect(
        n.text,
        'Vous n’avez envoyé aucun justificatif d’acompte pour ce rendez-vous.',
      );
      expect(n.tone, CancellationNoticeTone.neutral);
    }
  });

  test('more than N h before: the deposit comes back, from the salon', () {
    final n = at_(appt(), const Duration(hours: 30))!;
    expect(
      n.text,
      'D’après la règle du salon, votre acompte de $fcfa vous revient, '
      'car vous annulez plus de 24 h avant. Voyez avec le salon pour le '
      'récupérer : MyWeli ne détient aucun acompte.',
    );
    expect(n.tone, CancellationNoticeTone.returned);
  });

  test('N h or less before: kept by the salon', () {
    final n = at_(appt(), const Duration(hours: 5))!;
    expect(
      n.text,
      'D’après la règle du salon, votre acompte de $fcfa ne sera pas '
      'remboursé, car vous annulez moins de 24 h avant.',
    );
    expect(n.tone, CancellationNoticeTone.kept);
  });

  test('exactly at the cut-off counts as late', () {
    final n = at_(appt(), const Duration(hours: 24))!;
    expect(n.tone, CancellationNoticeTone.kept);
    expect(n.text, contains('moins de 24 h avant'));
    // One minute earlier is on time.
    expect(
      at_(appt(), const Duration(hours: 24, minutes: 1))!.tone,
      CancellationNoticeTone.returned,
    );
  });

  test('the time has passed: never « moins de 24 h avant »', () {
    for (final after in const [Duration.zero, Duration(hours: -2)]) {
      final n = at_(appt(), after)!;
      expect(
        n.text,
        'D’après la règle du salon, votre acompte de $fcfa ne sera pas '
        'remboursé, car l’heure du rendez-vous est passée.',
      );
      expect(n.tone, CancellationNoticeTone.kept);
    }
  });

  test('a salon with no delay: « avant l’heure », never « plus de 0 h »', () {
    final n = at_(appt(windowHours: 0), const Duration(minutes: 10))!;
    expect(n.text, contains('car vous annulez avant l’heure du rendez-vous.'));
    expect(n.text, isNot(contains('0 h')));
    expect(n.tone, CancellationNoticeTone.returned);
  });

  test('the app never promises a refund of its own', () {
    for (final before in const [
      Duration(hours: 48),
      Duration(hours: 5),
      Duration.zero,
    ]) {
      expect(at_(appt(), before)!.text, isNot(contains('sera remboursé.')));
    }
  });
}
