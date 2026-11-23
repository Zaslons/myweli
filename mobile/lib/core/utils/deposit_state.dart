import '../../models/appointment.dart';

/// What the deposit row of a client's own booking says and offers
/// (appointment-detail-complete.md §2.7, decision 197). One table for the app
/// and the web, pinned in `docs/design/fixtures/deposit-state.json`.
enum DepositAction {
  /// « Envoyer l’acompte » — the sheet that takes the proof.
  send,

  /// « Voir ma capture ».
  viewProof,
}

class DepositState {
  final String label;
  final String? sentence;
  final DepositAction? action;

  /// « Solde à régler au salon » — only while the booking is open. On a
  /// cancelled booking it would say money is owed; on a completed visit or an
  /// absence MyWeli does not know what was paid at the salon.
  final bool showBalance;

  const DepositState({
    required this.label,
    this.sentence,
    this.action,
    required this.showBalance,
  });
}

/// The no-custody sentence, built from the approved cancel sentences' last
/// clause: it promises no refund and does not say who cancelled.
const String kDepositSeeTheSalon =
    'Voyez directement avec le salon : MyWeli ne détient aucun acompte.';

/// Null when the booking has no deposit: then the block is not drawn.
///
/// **Only what MyWeli knows.** A salon confirms a booking, not a payment, and
/// can confirm one nobody paid a deposit for (`accept` checks no proof), so
/// « Acompte confirmé » is gone. « Aucun justificatif envoyé » says no proof
/// was attached, not that no money moved.
///
/// **« Envoyer l’acompte » stops at the appointment's time** (exactly at it
/// counts as past, as the client rule says): after it, a deposit for a visit
/// the salon never confirmed would be money sent for nothing.
DepositState? depositState(Appointment a, DateTime now) {
  if (a.depositAmount <= 0) return null;
  final proof = (a.depositScreenshotUrl ?? '').isNotEmpty;
  final ahead = a.appointmentDate.isAfter(now);
  final proofAction = proof ? DepositAction.viewProof : null;
  switch (a.status) {
    case AppointmentStatus.pending:
      if (ahead) {
        return proof
            ? const DepositState(
                label: 'Acompte — en attente de confirmation',
                sentence: 'Le salon confirmera après vérification.',
                action: DepositAction.viewProof,
                showBalance: true,
              )
            : const DepositState(
                label: 'Acompte à envoyer',
                sentence:
                    'Payez le salon directement, puis joignez une capture.',
                action: DepositAction.send,
                showBalance: true,
              );
      }
      return proof
          ? const DepositState(
              label: 'Acompte — non confirmé',
              sentence: kDepositSeeTheSalon,
              action: DepositAction.viewProof,
              showBalance: true,
            )
          : const DepositState(
              label: 'Aucun justificatif envoyé',
              showBalance: true,
            );
    case AppointmentStatus.confirmed:
      return DepositState(
        label: proof ? 'Acompte — justificatif envoyé' : 'Acompte',
        action: proofAction,
        showBalance: true,
      );
    case AppointmentStatus.cancelled:
      return DepositState(
        label: 'Acompte',
        sentence: proof ? kDepositSeeTheSalon : null,
        action: proofAction,
        showBalance: false,
      );
    case AppointmentStatus.completed:
    case AppointmentStatus.noShow:
      return DepositState(
        label: 'Acompte',
        action: proofAction,
        showBalance: false,
      );
  }
}
