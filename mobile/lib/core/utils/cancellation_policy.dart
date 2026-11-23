import '../../models/appointment.dart';
import 'formatters.dart';

/// How the cancel confirmation's deposit box reads: its border and its icon.
enum CancellationNoticeTone {
  /// The salon's rule keeps the deposit (« ne sera pas remboursé »).
  kept,

  /// The salon's rule gives it back (« vous revient »).
  returned,

  /// The rule decides nothing yet: no proof was sent.
  neutral,
}

/// What a client is told about a deposit before cancelling.
class CancellationNotice {
  const CancellationNotice(this.text, this.tone);

  final String text;
  final CancellationNoticeTone tone;
}

/// The sentence the cancel confirmation adds under its question, or null when
/// there is nothing to say (docs/design/consumer-app-truth.md §2.2).
///
/// **It states the salon's rule, and promises nothing of its own.** The deposit
/// is between the client and the salon: the server only records the
/// cancellation (no refund logic, `appointment_lifecycle_service.dart`), and
/// the CGU say MyWeli « ne rembourse aucun fonds ». The app used to say
/// « Votre acompte … sera remboursé », even when no proof was sent (B12.11).
///
/// **The web's rule, word for word** (`cancellationNotice`,
/// `web/lib/account/appointments.ts`), no-break spaces included, and pinned
/// against it by `cancellation_notice_parity_test.dart`. Exactly at the
/// cut-off counts as late, as on the web.
///
/// The web's seventh case, a missing delay, has no twin here:
/// `cancellation_window_hours` is `NOT NULL DEFAULT 24` on the server, so a
/// consumer read always carries it.
CancellationNotice? cancellationNotice(Appointment a, DateTime now) {
  // A booking the salon typed has no client proof to ask for. The app's form
  // of the web's `salonEntered` (`web/lib/bff.ts`).
  if (a.depositAmount <= 0 || a.clientName != null) return null;
  if ((a.depositScreenshotUrl ?? '').isEmpty) {
    return const CancellationNotice(
      'Vous n’avez envoyé aucun justificatif d’acompte pour ce rendez-vous.',
      CancellationNoticeTone.neutral,
    );
  }
  final hours = a.cancellationWindowHours;
  final amount = Formatters.formatCurrency(
    a.depositAmount,
    currency: a.currency ?? a.providerCurrency ?? 'XOF',
  );
  final kept =
      'D’après la règle du salon, votre acompte de $amount ne sera pas '
      'remboursé, car';
  if (!now.isBefore(a.appointmentDate)) {
    return CancellationNotice(
      '$kept l’heure du rendez-vous est passée.',
      CancellationNoticeTone.kept,
    );
  }
  final cutoff = a.appointmentDate.subtract(Duration(hours: hours));
  if (!now.isBefore(cutoff)) {
    return CancellationNotice(
      '$kept vous annulez moins de $hours\u00a0h avant.',
      CancellationNoticeTone.kept,
    );
  }
  final when = hours == 0
      ? 'avant l’heure du rendez-vous'
      : 'plus de $hours\u00a0h avant';
  return CancellationNotice(
    'D’après la règle du salon, votre acompte de $amount vous revient, car '
    'vous annulez $when. Voyez avec le salon pour le récupérer\u00a0: MyWeli '
    'ne détient aucun acompte.',
    CancellationNoticeTone.returned,
  );
}
