/// The salon-team alert e-mail — what a member receives when no notification
/// of the MyWeli Pro app could reach them (docs/design/salon-email-alerts.md
/// §3; the owner's words, approved 2026-10-19). The subscription notices'
/// template family: logo, one white card, one button, the footer — on the
/// OTP e-mail's frame (`width="100%"`, `max-width:440px`, padding on the
/// cells): the subscription notices' fixed 440px card plus its 32px padding
/// scrolled sideways on a phone (seen at 310px).
///
/// **No client data** (threat T58, as the push): the caller passes the
/// sentence the push already says. Every string that reaches the HTML is
/// escaped — the salon's name is the salon's to write, and it lands in the
/// inbox of every member of its team.
library;

import 'dart:convert';

/// Where a member turns these off (Espace Pro → Notifications).
const salonAlertSettingsUrl = 'https://myweli.com/pro/notifications';

/// Why this e-mail came, and how to stop it — the place it names is the
/// link in the HTML.
const _footerLead =
    'Vous recevez cet e-mail parce qu’aucune notification de l’app MyWeli Pro '
    'ne vous est parvenue. Pour ne plus le recevoir : ';
const _footerPlace = 'Espace Pro → Notifications';
const salonAlertFooter = '$_footerLead$_footerPlace.';

/// The booking on the web, in ITS salon: the page switches to it first
/// (`?salon=`, docs/design/web-pro-notifications.md §3.4).
String salonAlertLink(String? appointmentId, String providerId) {
  if (appointmentId == null) return 'https://myweli.com/pro/rendez-vous';
  return 'https://myweli.com/pro/rendez-vous/'
      '${Uri.encodeComponent(appointmentId)}'
      '?salon=${Uri.encodeComponent(providerId)}';
}

String renderSalonAlertText({required String body, required String link}) =>
    '$body\n\n'
    '$link\n\n'
    '$salonAlertFooter\n'
    '$salonAlertSettingsUrl\n\n'
    'MyWeli Pro — votre salon, en ligne.';

const _text = HtmlEscape(HtmlEscapeMode.element);
const _attr = HtmlEscape(HtmlEscapeMode.attribute);

String renderSalonAlertHtml({
  required String subject,
  required String body,
  required String button,
  required String link,
}) {
  final href = _attr.convert(link);
  return '''
<!DOCTYPE html>
<html lang="fr">
<head><meta charset="utf-8"><title>${_text.convert(subject)}</title></head>
<body style="margin:0;padding:24px 12px;background-color:#F6F7F9;font-family:Arial,Helvetica,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:440px;background-color:#FFFFFF;border-radius:12px;">
        <tr><td align="center" style="padding:28px 28px 0;">
          <img src="https://myweli.com/brand/myweli_lockup_horizontal_black.png" alt="MyWeli" height="34" style="height:34px;width:auto;border:0;display:block;">
        </td></tr>
        <tr><td style="padding:24px 28px 0;font-size:15px;line-height:22px;color:#1A1A1A;">
          ${_text.convert(body)}
        </td></tr>
        <tr><td align="center" style="padding:24px 28px 0;">
          <a href="$href" style="background-color:#1A1A1A;color:#FFFFFF;text-decoration:none;padding:12px 24px;border-radius:8px;font-size:14px;display:inline-block;">${_text.convert(button)}</a>
        </td></tr>
        <tr><td align="center" style="padding:24px 28px 28px;font-size:12px;line-height:18px;color:#8A8A8A;">
          ${_text.convert(_footerLead)}<a href="${_attr.convert(salonAlertSettingsUrl)}" style="color:#8A8A8A;">${_text.convert(_footerPlace)}</a>.<br><br>
          MyWeli Pro — votre salon, en ligne.
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>''';
}
