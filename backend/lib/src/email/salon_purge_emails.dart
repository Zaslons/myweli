/// The two e-mails to a deleted owner's team (B0.24, decision 156,
/// docs/design/deleted-owner-salon-purge.md §5.1): one when the salon's clock
/// starts, naming the day, and a reminder before it. French copy, the
/// subscription notices' frame.
///
/// The salon's name is the salon's to write (a Manager can rename it), and
/// these land in the members' inboxes (threat T73): the HTML escapes it, the
/// plain text keeps it as written, and the subject drops control characters.
library;

import 'dart:convert';

import '../salon_time.dart';

const _html = HtmlEscape(HtmlEscapeMode.element);

const _months = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

/// The due day, in the salon's timezone, as « 18 février 2027 » (§5.1).
String salonPurgeDay(DateTime dueAt, String? tzName) {
  final d = salonWallClock(dueAt, tzName);
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

/// A subject line: one line, no control characters, whatever the salon
/// typed.
String _oneLine(String s) =>
    s.replaceAll(RegExp(r'[\u0000-\u001F\u007F]+'), ' ').trim();

/// The first e-mail's subject: « {Salon} sera supprimé le {date} ».
String salonPurgeNoticeSubject(String salonName, String day) =>
    '${_oneLine(salonName)} sera supprimé le $day';

/// The reminder's subject: « {Salon} sera supprimé dans 7 jours ». The count
/// is the days really left, so a night the job did not run never makes it
/// say 7 when it is 3.
String salonPurgeReminderSubject(String salonName, int daysLeft) {
  final when = daysLeft <= 1 ? 'demain' : 'dans $daysLeft jours';
  return '${_oneLine(salonName)} sera supprimé $when';
}

/// The body both e-mails share (§5.1's draft, signed off in this PR).
List<String> _paragraphs(String salonName, String day) => [
  'Bonjour,',
  'Le propriétaire du salon $salonName a supprimé son compte MyWeli Pro. '
      'Le salon n’est plus visible du public et ne reçoit plus de '
      'réservations en ligne.',
  'Vous gardez votre accès au salon dans MyWeli Pro, selon votre rôle, '
      'jusqu’au $day. Ce jour-là, le salon sera supprimé définitivement : son '
      'agenda, y compris les rendez-vous prévus après cette date, son fichier '
      'clients, ses prestations, son équipe, ses avis et ses photos. Pensez à '
      'prévenir les clients concernés.',
  'Votre compte MyWeli Pro n’est pas supprimé. Pour le supprimer aussi : '
      'Profil → Supprimer mon compte.',
  '— L’équipe MyWeli',
];

String renderSalonPurgeText(String salonName, String day) =>
    _paragraphs(salonName, day).join('\n\n');

String renderSalonPurgeHtml(String salonName, String day) {
  final rows = _paragraphs(_html.convert(salonName), day)
      .map(
        (p) =>
            '      <tr><td style="font-size:15px;line-height:22px;'
            'color:#1A1A1A;padding:16px 28px 0;">$p</td></tr>',
      )
      .join('\n');
  return '''
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F6F7F9;">
  <tr><td align="center" style="padding:24px 12px;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:440px;background:#FFFFFF;border-radius:12px;font-family:Arial,Helvetica,sans-serif;">
      <tr><td align="center" style="padding:28px 28px 8px;">
        <img src="https://myweli.com/brand/myweli_lockup_horizontal_black.png" alt="MyWeli" height="34" style="display:block;">
      </td></tr>
$rows
      <tr><td style="font-size:12px;line-height:18px;color:#8A8A8A;padding:24px 28px 28px;" align="center">
        MyWeli Pro — votre salon, en ligne.<br>
        <a href="https://myweli.com" style="color:#8A8A8A;">myweli.com</a>
      </td></tr>
    </table>
  </td></tr>
</table>''';
}
