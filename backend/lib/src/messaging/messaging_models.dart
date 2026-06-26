// Outbound-messaging vocabulary, mirroring the app's `models/messaging.dart`
// field-for-field (names match the Dart enums' `.name`). Design:
// docs/design/messaging-notifications.md.

/// Channel a message is sent over. WhatsApp is the default; SMS is the fallback.
enum MessageChannel { whatsApp, sms }

/// Delivery state — `queued` on insert, advanced by the provider + status webhook.
enum DeliveryStatus { queued, sent, delivered, failed }

/// Operational (always allowed) vs marketing (requires explicit opt-in — ARTCI /
/// WhatsApp policy).
enum MessageCategory { transactional, promotional }

/// The FR-NOTIF-001 events. Each maps to an approved WhatsApp Business template.
enum MessageTemplate {
  bookingConfirmed,
  depositReceived,
  reminder24h,
  reminder2h,
  bookingAccepted,
  bookingDeclined,
  rescheduled,
  cancelled,
  refund,
  rebookReminder; // promotional (FR-NOTIF-003)

  /// Only the rebook nudge is promotional; everything else is transactional.
  MessageCategory get category => this == MessageTemplate.rebookReminder
      ? MessageCategory.promotional
      : MessageCategory.transactional;

  static MessageTemplate? tryParse(String name) {
    for (final t in MessageTemplate.values) {
      if (t.name == name) return t;
    }
    return null;
  }
}

/// Maps a Twilio `MessageStatus` (delivery-status webhook) to a [DeliveryStatus]
/// — null = ignore an unrecognised value.
DeliveryStatus? mapTwilioStatus(String status) => switch (status) {
  'queued' || 'accepted' || 'scheduled' => DeliveryStatus.queued,
  'sending' || 'sent' => DeliveryStatus.sent,
  'delivered' || 'read' => DeliveryStatus.delivered,
  'failed' || 'undelivered' => DeliveryStatus.failed,
  _ => null,
};

/// Renders the French body for a [template] from its [params] — mirrors the app's
/// `renderTemplate` (and the approved WhatsApp templates the BSP registers).
/// Missing params render empty rather than throwing.
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
