/// Branded subscription-lifecycle emails (the OTP template family —
/// docs/design/team-access-r2a-offers.md). French copy; no PII beyond the
/// salon's own name.
library;

/// The five notice kinds the scheduler sends, in escalation order.
abstract final class SubscriptionNotice {
  static const trialJ14 = 'trial_j14';
  static const trialJ7 = 'trial_j7';
  static const trialJ1 = 'trial_j1';
  static const grace = 'grace';
  static const unpublished = 'unpublished';
}

String subscriptionNoticeSubject(String kind) => switch (kind) {
  SubscriptionNotice.trialJ14 =>
    'Votre essai MyWeli Pro se termine dans 14 jours',
  SubscriptionNotice.trialJ7 => 'Plus que 7 jours d’essai MyWeli Pro',
  SubscriptionNotice.trialJ1 => 'Dernier jour de votre essai MyWeli Pro',
  SubscriptionNotice.grace => 'Votre offre MyWeli a expiré — 7 jours de grâce',
  SubscriptionNotice.unpublished => 'Votre salon n’est plus visible sur MyWeli',
  _ => 'Votre abonnement MyWeli',
};

String _noticeBody(String kind, String salonName) => switch (kind) {
  SubscriptionNotice.trialJ14 =>
    'L’essai gratuit de « $salonName » se termine dans 14 jours. Pour '
        'continuer à recevoir des réservations sans interruption, '
        'contactez-nous pour activer votre offre.',
  SubscriptionNotice.trialJ7 =>
    'Plus que 7 jours d’essai pour « $salonName ». Contactez-nous pour '
        'activer votre offre et continuer sans interruption.',
  SubscriptionNotice.trialJ1 =>
    'Votre essai pour « $salonName » se termine demain. Contactez-nous '
        'aujourd’hui pour éviter toute interruption.',
  SubscriptionNotice.grace =>
    'L’offre de « $salonName » a expiré. Votre salon reste visible pendant '
        '7 jours. Passé ce délai, il ne recevra plus de nouvelles '
        'réservations — vos données et votre agenda restent bien sûr '
        'accessibles.',
  SubscriptionNotice.unpublished =>
    '« $salonName » n’apparaît plus dans les recherches MyWeli et ne reçoit '
        'plus de nouvelles réservations. Vos rendez-vous existants, votre '
        'agenda et vos données restent accessibles. Contactez-nous pour '
        'réactiver votre salon — il sera republié immédiatement.',
  _ => 'Votre abonnement MyWeli a été mis à jour.',
};

String renderSubscriptionNoticeText(String kind, String salonName) =>
    '${_noticeBody(kind, salonName)}\n\n'
    'Nous contacter : https://myweli.com\n\n'
    'MyWeli Pro — votre salon, en ligne.';

String renderSubscriptionNoticeHtml(String kind, String salonName) {
  final body = _noticeBody(kind, salonName);
  return '''
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F6F7F9;padding:24px 0;">
  <tr><td align="center">
    <table role="presentation" width="440" cellpadding="0" cellspacing="0" style="background:#FFFFFF;border-radius:12px;padding:32px;font-family:Arial,Helvetica,sans-serif;">
      <tr><td align="center" style="padding-bottom:24px;">
        <img src="https://myweli.com/brand/myweli_lockup_horizontal_black.png" alt="MyWeli" height="34" style="display:block;">
      </td></tr>
      <tr><td style="font-size:15px;line-height:22px;color:#1A1A1A;padding-bottom:24px;">
        $body
      </td></tr>
      <tr><td align="center" style="padding-bottom:24px;">
        <a href="https://myweli.com" style="background:#1A1A1A;color:#FFFFFF;text-decoration:none;padding:12px 24px;border-radius:8px;font-size:14px;display:inline-block;">Nous contacter</a>
      </td></tr>
      <tr><td style="font-size:12px;line-height:18px;color:#8A8A8A;" align="center">
        MyWeli Pro — votre salon, en ligne.<br>
        <a href="https://myweli.com" style="color:#8A8A8A;">myweli.com</a>
      </td></tr>
    </table>
  </td></tr>
</table>''';
}
