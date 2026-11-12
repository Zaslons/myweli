/// The salon validation's e-mails (B0.18 — docs/design/salon-go-live-approval.md
/// §5): the decision, to the salon's owner (§5.2), and the two notes to the
/// admin (§5.1). The subscription notices' template family — logo, one white
/// card, one button, the footer — on the OTP e-mail's frame (`width="100%"`,
/// `max-width:440px`, padding on the cells).
///
/// **Every interpolated string is HTML-escaped** (threat T73): the salon's
/// name is the salon's to write, the refusal note is the admin's free text,
/// and the place-change values are whatever the salon typed. The plain-text
/// parts keep them as written.
library;

import 'dart:convert';

import '../validation/salon_validation_copy.dart';

const _text = HtmlEscape(HtmlEscapeMode.element);
const _attr = HtmlEscape(HtmlEscapeMode.attribute);

/// The salon's own Pro space, switched to it (`?salon=`, as the booking
/// alerts do — docs/design/web-pro-notifications.md §3.4).
String salonValidationLink(String providerId) =>
    'https://myweli.com/pro?salon=${Uri.encodeComponent(providerId)}';

/// The request in the admin console. The console uses hash URLs, so the
/// path rides in the fragment (§4.1).
String adminValidationLink(String providerId) =>
    'https://admin.myweli.com/#/admin/salon-validations/'
    '${Uri.encodeComponent(providerId)}';

/// The salon in the admin console — where « Suspendre » lives (§5.1).
String adminSalonLink(String providerId) =>
    'https://admin.myweli.com/#/admin/providers/'
    '${Uri.encodeComponent(providerId)}';

const _ownerFooter =
    'Vous recevez cet e-mail parce que vous avez demandé la mise en ligne de '
    'votre salon sur MyWeli.';

const _adminFooter = 'MyWeli — console d’administration.';

/// One rendered e-mail.
typedef SalonValidationEmail = ({String subject, String text, String html});

/// §5.2, validated: the salon is online, and — when it runs on a trial —
/// the trial's end date, already in the salon's wall clock ([trialEndsOn],
/// `dd/MM/yyyy`). The e-mail may name the trial; the app and the push never
/// promote it (pro-companion-path §2.1).
SalonValidationEmail renderSalonApprovedEmail({
  required String salonName,
  required String providerId,
  String? trialEndsOn,
}) {
  final paragraphs = [
    'MyWeli a validé « $salonName ». $kApprovedBody',
    if (trialEndsOn != null) 'Votre essai gratuit court jusqu’au $trialEndsOn.',
  ];
  return _render(
    subject: approvedTitle(salonName),
    paragraphs: paragraphs,
    button: 'Ouvrir mon Espace Pro',
    link: salonValidationLink(providerId),
    footer: _ownerFooter,
  );
}

/// §5.2, refused: the reason (the code's sentence, then the admin's note),
/// and what to do next — not after a final refusal, which no new request can
/// answer (§4.3).
SalonValidationEmail renderSalonRefusedEmail({
  required String salonName,
  required String providerId,
  required String code,
  String? note,
}) {
  final sentence = kRefusalSentences[code];
  final n = (note == null || note.trim().isEmpty) ? null : note.trim();
  final paragraphs = [
    ?sentence,
    ?n,
    if (!isFinalRefusalCode(code)) kResubmitSentence,
  ];
  return _render(
    subject: refusedTitle(salonName),
    paragraphs: paragraphs,
    button: 'Ouvrir mon Espace Pro',
    link: salonValidationLink(providerId),
    footer: _ownerFooter,
  );
}

/// §5.1: a new request, to the admin.
SalonValidationEmail renderAdminNewRequestEmail({
  required String providerId,
  required String salonName,
  String? commune,
  String? city,
  String? countryCode,
}) {
  final place = [
    if (commune != null && commune.trim().isNotEmpty) commune.trim(),
    if (city != null && city.trim().isNotEmpty) city.trim(),
  ].join(', ');
  final subject = 'Nouveau salon à valider : $salonName';
  return _render(
    subject: subject,
    paragraphs: [
      subject,
      'Commune : ${place.isEmpty ? '—' : place}',
      'Pays : ${(countryCode == null || countryCode.isEmpty) ? '—' : countryCode}',
    ],
    button: 'Ouvrir la demande',
    link: adminValidationLink(providerId),
    footer: _adminFooter,
  );
}

/// One value of a salon's place before and after a save (§5.1, Q6).
typedef PlaceChange = ({String field, String? before, String? after});

/// The labels of [PlaceChange.field], in the order the e-mail lists them.
const Map<String, String> kPlaceFieldLabels = {
  'location': 'Emplacement',
  'address': 'Adresse',
  'commune': 'Commune',
  'phone': 'Téléphone',
};

/// The subject's words for each field — « {Salon} a modifié son
/// emplacement » (or « son adresse », « son téléphone ») — joined when one
/// save changes several.
const Map<String, String> _placeFieldWords = {
  'location': 'son emplacement',
  'address': 'son adresse',
  'commune': 'son adresse',
  'phone': 'son téléphone',
};

/// §5.1 (Q6): a validated salon changed its pin, address, commune or phone.
/// One e-mail per save, with the old and new values. The salon stays
/// online; the admin can suspend it.
SalonValidationEmail renderAdminPlaceChangedEmail({
  required String providerId,
  required String salonName,
  required List<PlaceChange> changes,
}) {
  final words = <String>[];
  for (final field in kPlaceFieldLabels.keys) {
    final word = _placeFieldWords[field]!;
    if (changes.any((c) => c.field == field) && !words.contains(word)) {
      words.add(word);
    }
  }
  final what = switch (words.length) {
    0 => 'sa fiche',
    1 => words.single,
    _ => '${words.sublist(0, words.length - 1).join(', ')} et ${words.last}',
  };
  String shown(String? v) => (v == null || v.trim().isEmpty) ? '—' : v.trim();
  final ordered = [
    for (final field in kPlaceFieldLabels.keys)
      ...changes.where((c) => c.field == field),
  ];
  return _render(
    subject: '$salonName a modifié $what',
    paragraphs: [
      '$salonName, un salon validé, a modifié $what. Il reste en ligne ; '
          'vous pouvez le suspendre depuis la console.',
      for (final c in ordered)
        '${kPlaceFieldLabels[c.field]} : ${shown(c.before)} → ${shown(c.after)}',
    ],
    button: 'Voir le salon',
    link: adminSalonLink(providerId),
    footer: _adminFooter,
  );
}

SalonValidationEmail _render({
  required String subject,
  required List<String> paragraphs,
  required String button,
  required String link,
  required String footer,
}) {
  final text = [
    ...paragraphs,
    link,
    footer,
    'MyWeli Pro — votre salon, en ligne.',
  ].join('\n\n');
  // A paragraph may hold line breaks (an admin's note): escaped first, then
  // each break becomes a <br> — never the other way round.
  String para(String p) => _text.convert(p).replaceAll('\n', '<br>');
  final body = [
    for (final p in paragraphs)
      '        <p style="margin:0 0 12px;">${para(p)}</p>',
  ].join('\n');
  final html =
      '''
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
$body
        </td></tr>
        <tr><td align="center" style="padding:12px 28px 0;">
          <a href="${_attr.convert(link)}" style="background-color:#1A1A1A;color:#FFFFFF;text-decoration:none;padding:12px 24px;border-radius:8px;font-size:14px;display:inline-block;">${_text.convert(button)}</a>
        </td></tr>
        <tr><td align="center" style="padding:24px 28px 28px;font-size:12px;line-height:18px;color:#8A8A8A;">
          ${_text.convert(footer)}<br><br>
          MyWeli Pro — votre salon, en ligne.<br>
          <a href="https://myweli.com" style="color:#8A8A8A;">myweli.com</a>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>''';
  return (subject: subject, text: text, html: html);
}
