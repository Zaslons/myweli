import '../access/membership_repository.dart';
import '../email/email_provider.dart';
import '../email/salon_validation_emails.dart';
import '../email/send_budget.dart';
import '../notifications/notifications_repository.dart';
import '../providers_repository.dart';
import '../push/push_service.dart';
import '../salon_time.dart';
import 'salon_validation_copy.dart';

/// The salon's notice on each decision (B0.18 —
/// docs/design/salon-go-live-approval.md §5.2): a push, an in-app feed row
/// and an e-mail, to the OWNER only — the `salon.publish` holder who asked.
/// Not the booking events' member fan-out (`SalonNotifier`): the « four
/// events » sentences shown to every member stay true.
///
/// - **Push:** facts only. Route `/pro/onboarding?salon={id}`, `providerId`
///   (the app switches salon first, R6), event `salon.validation.approved`
///   or `…refused`.
/// - **Feed row:** type `salonValidation` (old clients render it as
///   `general` with its body). On a refusal the body carries the note too:
///   released builds read the reason here.
/// - **E-mail:** class `warm`, only to an address ([Member.emailOrNull]) —
///   a phone-registered owner gets the push and the row and no send.
///
/// Best effort, each channel on its own: a failure never undoes the
/// decision, and never stops the next channel.
class SalonDecisionNotifier {
  SalonDecisionNotifier(
    this._members,
    this._providers,
    this._push,
    this._notifications, {
    required EmailProvider email,
  }) : _email = email;

  final MembershipRepository _members;
  final ProvidersRepository _providers;
  final PushService _push;
  final NotificationsRepository _notifications;

  /// Required, not defaulted, as `SalonNotifier`'s: a forgotten wiring must
  /// not quietly leave the salons without the app with nothing.
  final EmailProvider _email;

  static const feedType = 'salonValidation';

  static String routeFor(String providerId) =>
      '/pro/onboarding?salon=${Uri.encodeComponent(providerId)}';

  /// Validated and live. [trialEndsAt] — the salon's trial end when it runs
  /// on one — is named in the e-mail only.
  Future<void> approved(String providerId, {DateTime? trialEndsAt}) => _notify(
    providerId,
    event: 'salon.validation.approved',
    title: approvedTitle,
    pushBody: kApprovedBody,
    feedBody: kApprovedBody,
    email: (salonName, tz) => renderSalonApprovedEmail(
      salonName: salonName,
      providerId: providerId,
      trialEndsOn: trialEndsAt == null ? null : _day(trialEndsAt, tz),
    ),
  );

  /// Refused with [code] (§4.3) and maybe a [note].
  Future<void> refused(
    String providerId, {
    required String code,
    String? note,
  }) => _notify(
    providerId,
    event: 'salon.validation.refused',
    title: refusedTitle,
    pushBody: refusedPushBody(code, note),
    feedBody: refusalText(code, note),
    email: (salonName, _) => renderSalonRefusedEmail(
      salonName: salonName,
      providerId: providerId,
      code: code,
      note: note,
    ),
  );

  Future<void> _notify(
    String providerId, {
    required String event,
    required String Function(String salonName) title,
    required String pushBody,
    required String feedBody,
    required SalonValidationEmail Function(String salonName, String? tz) email,
  }) async {
    final Member? owner;
    final Map<String, dynamic>? salon;
    try {
      owner = await _owner(providerId);
      salon = owner == null ? null : await _providers.byId(providerId);
    } catch (_) {
      return; // best effort: nobody to tell, or nothing to tell them with.
    }
    if (owner == null) return;
    final salonName = (salon?['name'] as String?) ?? 'votre salon';
    final tz = salon?['timezone'] as String?;
    final accountId = owner.accountId!;
    final route = routeFor(providerId);
    final heading = title(salonName);

    try {
      await _push.sendToUser(
        accountId,
        title: heading,
        body: pushBody,
        data: {'event': event, 'providerId': providerId, 'route': route},
      );
    } catch (_) {}
    try {
      await _notifications.add(
        userId: accountId,
        type: feedType,
        title: heading,
        body: feedBody,
        route: route,
      );
    } catch (_) {}
    final to = owner.emailOrNull;
    if (to == null) return;
    try {
      final mail = email(salonName, tz);
      await _email.send(
        // WARM: a decision about the salon's own listing, to its owner.
        classification: EmailClass.warm,
        to: to,
        subject: mail.subject,
        text: mail.text,
        html: mail.html,
      );
    } catch (_) {}
  }

  /// The salon's active owner linked to an account — the one who asked.
  Future<Member?> _owner(String providerId) async {
    for (final m in await _members.listForProvider(providerId)) {
      if (m.role == 'owner' && m.status == 'active' && m.accountId != null) {
        return m;
      }
    }
    return null;
  }

  /// `dd/MM/yyyy` in the salon's wall clock (multi-pays §3).
  static String _day(DateTime d, String? tz) {
    final w = salonWallClock(d, tz);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(w.day)}/${two(w.month)}/${w.year}';
  }
}
