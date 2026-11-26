/// The notice sent to an account's previous address after its e-mail changes
/// (B16.3, decision 265, docs/design/account-email-change.md §11 Q6): « the
/// address of your MyWeli account has been changed; if it was not you, write
/// to support ». French copy, the other notices' frame.
///
/// It names neither address: the old inbox already knows its own, and the new
/// one is the account's business — written to someone who may not be its
/// owner any more.
library;

/// The subject.
const String accountEmailChangedSubject =
    'L’adresse de votre compte MyWeli a été changée';

/// The body, the spec's sentence (§11 Q6).
const List<String> _paragraphs = [
  'Bonjour,',
  'L’adresse de votre compte MyWeli a été changée. Vous ne pouvez plus vous '
      'connecter par code avec cette adresse.',
  'Si ce n’est pas vous, écrivez à support@myweli.com.',
  '— L’équipe MyWeli',
];

/// The plain-text part.
String renderAccountEmailChangedText() => _paragraphs.join('\n\n');

/// The HTML part. No variable reaches it: nothing to escape.
String renderAccountEmailChangedHtml() {
  final rows = _paragraphs
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
        MyWeli — Réservation beauté &amp; bien-être en Côte d’Ivoire<br>
        <a href="https://myweli.com" style="color:#8A8A8A;">myweli.com</a>
      </td></tr>
    </table>
  </td></tr>
</table>''';
}
