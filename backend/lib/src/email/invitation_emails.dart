/// Branded team-invitation email (the OTP template family —
/// docs/design/team-access-r2b-invitations.md). French copy.
library;

const String invitationEmailSubjectPrefix = 'Rejoignez';

String invitationEmailSubject(String salonName) =>
    '$invitationEmailSubjectPrefix « $salonName » sur MyWeli Pro';

/// The invitable roles' plain-French labels (the invite sheet uses the same
/// wording — module doc §5.1).
String roleLabelFr(String role) => switch (role) {
  'manager' => 'Manager',
  'reception' => 'Réception',
  'staff' => 'Collaborateur',
  _ => role,
};

String _roleSummaryFr(String role) => switch (role) {
  'manager' =>
    'Gère les rendez-vous, le catalogue et les disponibilités du salon.',
  'reception' => 'Accueil : tout le planning et le fichier clients.',
  'staff' => 'Voit uniquement son propre planning.',
  _ => '',
};

String renderInvitationEmailText(String salonName, String role) =>
    '« $salonName » vous invite à rejoindre son équipe sur MyWeli Pro en '
    'tant que ${roleLabelFr(role)}.\n'
    '${_roleSummaryFr(role)}\n\n'
    'Pour accepter : téléchargez MyWeli Pro et connectez-vous avec CETTE '
    'adresse e-mail — votre invitation vous attend.\n\n'
    'L’invitation est valable 7 jours.\n\n'
    'MyWeli Pro — votre salon, en ligne. https://myweli.com';

String renderInvitationEmailHtml(String salonName, String role) {
  final label = roleLabelFr(role);
  final summary = _roleSummaryFr(role);
  return '''
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F6F7F9;padding:24px 0;">
  <tr><td align="center">
    <table role="presentation" width="440" cellpadding="0" cellspacing="0" style="background:#FFFFFF;border-radius:12px;padding:32px;font-family:Arial,Helvetica,sans-serif;">
      <tr><td align="center" style="padding-bottom:24px;">
        <img src="https://myweli.com/brand/myweli_lockup_horizontal_black.png" alt="MyWeli" height="34" style="display:block;">
      </td></tr>
      <tr><td style="font-size:16px;line-height:24px;color:#1A1A1A;padding-bottom:8px;" align="center">
        <strong>« $salonName »</strong> vous invite à rejoindre son équipe
      </td></tr>
      <tr><td style="font-size:14px;line-height:20px;color:#1A1A1A;padding-bottom:4px;" align="center">
        en tant que <strong>$label</strong>
      </td></tr>
      <tr><td style="font-size:13px;line-height:19px;color:#8A8A8A;padding-bottom:24px;" align="center">
        $summary
      </td></tr>
      <tr><td style="font-size:14px;line-height:21px;color:#1A1A1A;padding-bottom:24px;" align="center">
        Téléchargez <strong>MyWeli Pro</strong> et connectez-vous avec cette
        adresse e-mail — votre invitation vous attend.
      </td></tr>
      <tr><td align="center" style="padding-bottom:24px;">
        <a href="https://myweli.com" style="background:#1A1A1A;color:#FFFFFF;text-decoration:none;padding:12px 24px;border-radius:8px;font-size:14px;display:inline-block;">Ouvrir MyWeli Pro</a>
      </td></tr>
      <tr><td style="font-size:12px;line-height:18px;color:#8A8A8A;" align="center">
        L’invitation est valable 7 jours. Si vous n’attendiez pas cette
        invitation, ignorez cet e-mail — rien ne sera créé sans votre accord.<br>
        <a href="https://myweli.com" style="color:#8A8A8A;">myweli.com</a>
      </td></tr>
    </table>
  </td></tr>
</table>''';
}
