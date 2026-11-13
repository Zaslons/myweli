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
///
/// **Said in the log, one line per channel** (§5.2, « Ce que dit le
/// journal »): every decision writes exactly three lines, push, feed and
/// e-mail in that order, so a query on any one channel sees every decision —
///
///     salon_notice kind=refused provider=p_1 channel=email outcome=failed error=resend_500
///
/// `outcome` is `sent`, `undelivered` (push only: no device took it),
/// `skipped` (with a `reason`) or `failed` (with an `error`: a provider's
/// code, or a thrown error's TYPE, never its message). Only ids, codes,
/// counts and types: never the note, the address, the salon's name, the
/// title or body, or a token (BACKEND §3.6). The proposed alert matches
/// `channel=email outcome=failed`: keep those two fields side by side.
class SalonDecisionNotifier {
  SalonDecisionNotifier(
    this._members,
    this._providers,
    this._push,
    this._notifications, {
    required EmailProvider email,
    void Function(String)? log,
  }) : _email = email,
       _log = log ?? print;

  final MembershipRepository _members;
  final ProvidersRepository _providers;
  final PushService _push;
  final NotificationsRepository _notifications;

  /// Required, not defaulted, as `SalonNotifier`'s: a forgotten wiring must
  /// not quietly leave the salons without the app with nothing.
  final EmailProvider _email;
  final void Function(String) _log;

  static const feedType = 'salonValidation';

  /// The channels, in the order they are tried and logged.
  static const channels = ['push', 'feed', 'email'];

  static String routeFor(String providerId) =>
      '/pro/onboarding?salon=${Uri.encodeComponent(providerId)}';

  /// Validated and live. [trialEndsAt] — the salon's trial end when it runs
  /// on one — is named in the e-mail only.
  Future<void> approved(String providerId, {DateTime? trialEndsAt}) => _notify(
    providerId,
    kind: 'approved',
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
    kind: 'refused',
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
    required String kind,
    required String event,
    required String Function(String salonName) title,
    required String pushBody,
    required String feedBody,
    required SalonValidationEmail Function(String salonName, String? tz) email,
  }) async {
    void say(String channel, String outcome) => _say(
      'salon_notice kind=$kind provider=$providerId '
      'channel=$channel outcome=$outcome',
    );

    final Member? owner;
    final Map<String, dynamic>? salon;
    try {
      owner = await _owner(providerId);
      salon = owner == null ? null : await _providers.byId(providerId);
    } catch (e) {
      // Best effort: nothing to tell them with. Nothing was sent, on any
      // channel — so each channel says so.
      for (final c in channels) {
        say(c, 'failed reason=lookup error=${e.runtimeType}');
      }
      return;
    }
    if (owner == null) {
      for (final c in channels) {
        say(c, 'skipped reason=no_owner');
      }
      return;
    }
    final salonName = (salon?['name'] as String?) ?? 'votre salon';
    final tz = salon?['timezone'] as String?;
    final accountId = owner.accountId!;
    final route = routeFor(providerId);
    final heading = title(salonName);

    try {
      // By kind: a browser's count never stands for « the app reached
      // them » (web-pro-browser-push §4, Q1). 0 and 0 is no device, or a
      // provider refusal, which `PushService` logs on its own line.
      final d = await _push.sendToUserByKind(
        accountId,
        title: heading,
        body: pushBody,
        data: {'event': event, 'providerId': providerId, 'route': route},
      );
      say(
        'push',
        '${d.app + d.web > 0 ? 'sent' : 'undelivered'} '
            'app=${d.app} web=${d.web}',
      );
    } catch (e) {
      say('push', 'failed error=${e.runtimeType}');
    }
    try {
      await _notifications.add(
        userId: accountId,
        type: feedType,
        title: heading,
        body: feedBody,
        route: route,
      );
      say('feed', 'sent');
    } catch (e) {
      say('feed', 'failed error=${e.runtimeType}');
    }
    final to = owner.emailOrNull;
    if (to == null) {
      say('email', 'skipped reason=no_address');
      return;
    }
    try {
      final mail = email(salonName, tz);
      final r = await _email.send(
        // WARM: a decision about the salon's own listing, to its owner.
        classification: EmailClass.warm,
        to: to,
        subject: mail.subject,
        text: mail.text,
        html: mail.html,
      );
      say('email', r.ok ? 'sent' : 'failed error=${errorCode(r.error)}');
    } catch (e) {
      say('email', 'failed error=${e.runtimeType}');
    }
  }

  /// A provider's `error` as it may be logged: a code (`unroutable`,
  /// `send_budget_exhausted`, `resend_422`, `resend_unreachable`). Anything
  /// else — free text that could carry an address, or a space that would
  /// forge a field of the line — is `unknown`.
  static String errorCode(String? error) =>
      error != null && RegExp(r'^[a-z0-9_]{1,64}$').hasMatch(error)
      ? error
      : 'unknown';

  /// The log never fails the decision: it is already written.
  void _say(String line) {
    try {
      _log(line);
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
