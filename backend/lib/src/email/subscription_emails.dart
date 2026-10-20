/// Branded subscription-lifecycle emails (the OTP template family —
/// docs/design/team-access-r2a-offers.md). French copy; no PII beyond the
/// salon's own name.
///
/// That name is the salon's to write — a Manager can rename it
/// (`profile.manage`) — and these notices land in the OWNER's inbox
/// (threat T73): the HTML escapes it, the plain text keeps it as written.
library;

import 'dart:convert';

const _text = HtmlEscape(HtmlEscapeMode.element);

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

/// The OTP e-mail's frame (`renderOtpEmailHtml`): a full-width card capped
/// at 440px, padding on the cells — a fixed `width="440"` card plus its
/// padding scrolled sideways on a phone (seen at 310px).
String renderSubscriptionNoticeHtml(String kind, String salonName) {
  final body = _text.convert(_noticeBody(kind, salonName));
  return '''
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F6F7F9;">
  <tr><td align="center" style="padding:24px 12px;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:440px;background:#FFFFFF;border-radius:12px;font-family:Arial,Helvetica,sans-serif;">
      <tr><td align="center" style="padding:28px 28px 0;">
        <img src="https://myweli.com/brand/myweli_lockup_horizontal_black.png" alt="MyWeli" height="34" style="display:block;">
      </td></tr>
      <tr><td style="font-size:15px;line-height:22px;color:#1A1A1A;padding:24px 28px 0;">
        $body
      </td></tr>
      <tr><td align="center" style="padding:24px 28px 0;">
        <a href="https://myweli.com" style="background:#1A1A1A;color:#FFFFFF;text-decoration:none;padding:12px 24px;border-radius:8px;font-size:14px;display:inline-block;">Nous contacter</a>
      </td></tr>
      <tr><td style="font-size:12px;line-height:18px;color:#8A8A8A;padding:24px 28px 28px;" align="center">
        MyWeli Pro — votre salon, en ligne.<br>
        <a href="https://myweli.com" style="color:#8A8A8A;">myweli.com</a>
      </td></tr>
    </table>
  </td></tr>
</table>''';
}
