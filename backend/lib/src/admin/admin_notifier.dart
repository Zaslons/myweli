import '../email/email_provider.dart';
import '../email/salon_validation_emails.dart';
import '../email/send_budget.dart';

/// The platform owner's inbox (B0.18 — docs/design/salon-go-live-approval.md
/// §5.1): an e-mail to `ADMIN_EMAIL` on each NEW request to go live, and on
/// each save that changes a validated salon's place (Q6). Until this, nothing
/// told the admin anything: the console's count was the only way to learn.
///
/// **Never in the way.** Best effort: a send that fails, throws or is refused
/// by the budget never turns a recorded request or a saved profile into an
/// error, and an unset address does nothing at all. The outcome is logged
/// WITHOUT the address (BACKEND §3: no PII in logs) — the salon id and the
/// result, which is what an operator needs to tell « nothing was sent »
/// from « it was sent and did not arrive ».
class AdminNotifier {
  AdminNotifier(this._email, {String? adminEmail, void Function(String)? log})
    : _to = _addressOrNull(adminEmail),
      _log = log ?? print;

  final EmailProvider _email;

  /// Null when `ADMIN_EMAIL` is unset or is not an address: no-op.
  final String? _to;
  final void Function(String) _log;

  static String? _addressOrNull(String? raw) {
    final v = raw?.trim();
    return (v == null || !v.contains('@')) ? null : v;
  }

  /// §3.1: the owner asked to go live, and THIS call recorded the request
  /// (a double tap records once, so it is e-mailed once).
  Future<void> newSalonRequest({
    required String providerId,
    required String salonName,
    String? commune,
    String? city,
    String? countryCode,
  }) => _send(
    'salon_request',
    providerId,
    () => renderAdminNewRequestEmail(
      providerId: providerId,
      salonName: salonName,
      commune: commune,
      city: city,
      countryCode: countryCode,
    ),
  );

  /// §5.1 (Q6): a save changed a validated salon's pin, address, commune or
  /// phone — one e-mail per save, the old and the new values.
  Future<void> salonPlaceChanged({
    required String providerId,
    required String salonName,
    required List<PlaceChange> changes,
  }) => _send(
    'salon_place_changed',
    providerId,
    () => renderAdminPlaceChangedEmail(
      providerId: providerId,
      salonName: salonName,
      changes: changes,
    ),
  );

  Future<void> _send(
    String kind,
    String providerId,
    SalonValidationEmail Function() render,
  ) async {
    final to = _to;
    if (to == null) {
      _log('admin_notice kind=$kind provider=$providerId outcome=skipped');
      return;
    }
    try {
      final mail = render();
      final r = await _email.send(
        // WARM: an authenticated pro's own action about their own salon —
        // and a request must never be starved by anonymous OTP traffic.
        classification: EmailClass.warm,
        to: to,
        subject: mail.subject,
        text: mail.text,
        html: mail.html,
      );
      _log(
        'admin_notice kind=$kind provider=$providerId '
        'outcome=${r.ok ? 'sent' : 'failed error=${r.error}'}',
      );
    } catch (e) {
      _log(
        'admin_notice kind=$kind provider=$providerId outcome=failed '
        'error=${e.runtimeType}',
      );
    }
  }
}
