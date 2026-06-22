import '../../models/messaging.dart';

/// Renders the French body for a [template] from its [params]. These mirror the
/// approved WhatsApp Business templates the backend will register; missing
/// params render as an empty string rather than throwing.
String renderTemplate(MessageTemplate template, Map<String, String> params) {
  String p(String key) => params[key] ?? '';
  switch (template) {
    case MessageTemplate.bookingConfirmed:
      return 'Votre réservation chez ${p('provider')} le ${p('date')} à '
          '${p('time')} est confirmée. Acompte reçu : ${p('deposit')}. '
          'À bientôt !';
    case MessageTemplate.depositReceived:
      return 'Acompte de ${p('deposit')} bien reçu pour votre rendez-vous '
          'chez ${p('provider')}. Merci !';
    case MessageTemplate.reminder24h:
      return 'Rappel : rendez-vous chez ${p('provider')} demain à ${p('time')}.';
    case MessageTemplate.reminder2h:
      return 'Rappel : votre rendez-vous chez ${p('provider')} est dans 2 h '
          '(${p('time')}).';
    case MessageTemplate.bookingAccepted:
      return '${p('provider')} a accepté votre rendez-vous du ${p('date')} à '
          '${p('time')}.';
    case MessageTemplate.bookingDeclined:
      return '${p('provider')} ne peut pas honorer le créneau du ${p('date')}. '
          'Votre acompte sera remboursé.';
    case MessageTemplate.rescheduled:
      return 'Votre rendez-vous chez ${p('provider')} est reporté au '
          '${p('date')} à ${p('time')}.';
    case MessageTemplate.cancelled:
      return 'Votre rendez-vous chez ${p('provider')} du ${p('date')} a été '
          'annulé.';
    case MessageTemplate.refund:
      return 'Remboursement de ${p('amount')} effectué pour votre rendez-vous '
          'chez ${p('provider')}.';
    case MessageTemplate.rebookReminder:
      return 'Cela fait ${p('weeks')} semaines depuis votre visite chez '
          '${p('provider')}. Réserver à nouveau ?';
  }
}
