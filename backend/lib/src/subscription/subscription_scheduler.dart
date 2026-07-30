import '../access/membership_repository.dart';
import '../email/email_provider.dart';
import '../email/subscription_emails.dart';
import '../providers_repository.dart';
import '../push/push_service.dart';
import 'salon_subscription_repository.dart';
import 'salon_subscription_service.dart';

typedef SubscriptionTickResult = ({int notices, int unpublished});

/// The daily subscription walk (docs/design/team-access-r2a-offers.md),
/// driven by `POST /internal/cron/subscriptions` (CRON_SECRET-gated, like
/// the reminders cron). Idempotent: every notice fires once per
/// (salon, kind) per billing cycle; enforcement flips a salon to `draft`
/// ONLY when [enforce] is on and the grace window has ended — never a data
/// lockout (T51 keeps the journal/data fully usable).
class SubscriptionScheduler {
  SubscriptionScheduler(
    this._subscriptions,
    this._memberships,
    this._providers,
    this._email,
    this._push, {
    required bool enforce,
  }) : _enforce = enforce;

  final SalonSubscriptionRepository _subscriptions;
  final MembershipRepository _memberships;
  final ProvidersRepository _providers;
  final EmailProvider _email;
  final PushService _push;
  final bool _enforce;

  Future<SubscriptionTickResult> tick(DateTime now) async {
    var notices = 0;
    var unpublished = 0;

    for (final row in await _subscriptions.all()) {
      final paidCovers = row.paidUntil != null && now.isBefore(row.paidUntil!);
      if (paidCovers) continue;

      final kind = _kindFor(row, now);
      if (kind != null &&
          await _subscriptions.markNoticeIfNew(row.providerId, kind)) {
        await _notifyOwner(row.providerId, kind);
        notices++;
      }

      // Enforcement: past grace → unpublish (draft; T51 hides it while the
      // journal, existing bookings and data keep working).
      final graceEnd = _anchor(row).add(SalonSubscriptionService.graceLength);
      if (_enforce && row.unpublishedAt == null && !now.isBefore(graceEnd)) {
        final provider = await _providers.byId(row.providerId);
        if (provider != null && provider['status'] == 'active') {
          await _providers.setStatus(row.providerId, 'draft');
          await _subscriptions.update(row.providerId, unpublishedAt: now);
          if (await _subscriptions.markNoticeIfNew(
            row.providerId,
            SubscriptionNotice.unpublished,
          )) {
            await _notifyOwner(row.providerId, SubscriptionNotice.unpublished);
            notices++;
          }
          unpublished++;
        }
      }
    }
    return (notices: notices, unpublished: unpublished);
  }

  /// The most urgent unsent warning for the row at [now] (the notice log
  /// dedupes re-sends; a later kind supersedes an unsent earlier one).
  String? _kindFor(SalonSubscriptionRow row, DateTime now) {
    final anchor = _anchor(row);
    if (now.isBefore(anchor)) {
      final daysLeft = anchor.difference(now).inDays;
      if (daysLeft < 1) return SubscriptionNotice.trialJ1;
      if (daysLeft < 7) return SubscriptionNotice.trialJ7;
      if (daysLeft < 14) return SubscriptionNotice.trialJ14;
      return null;
    }
    final graceEnd = anchor.add(SalonSubscriptionService.graceLength);
    if (now.isBefore(graceEnd)) return SubscriptionNotice.grace;
    return null; // past grace → the enforcement branch owns the messaging
  }

  DateTime _anchor(SalonSubscriptionRow row) =>
      row.paidUntil != null && row.paidUntil!.isAfter(row.trialEndsAt)
      ? row.paidUntil!
      : row.trialEndsAt;

  /// Email + best-effort push to the salon's OWNER (the membership row
  /// carries both the account id and the email).
  Future<void> _notifyOwner(String providerId, String kind) async {
    final members = await _memberships.listForProvider(providerId);
    Member? owner;
    for (final m in members) {
      if (m.role == 'owner' && m.status == 'active') {
        owner = m;
        break;
      }
    }
    if (owner == null) return;

    final provider = await _providers.byId(providerId);
    final salonName = (provider?['name'] as String?) ?? 'votre salon';

    if (owner.email.isNotEmpty) {
      await _email.send(
        to: owner.email,
        subject: subscriptionNoticeSubject(kind),
        text: renderSubscriptionNoticeText(kind, salonName),
        html: renderSubscriptionNoticeHtml(kind, salonName),
      );
    }
    final accountId = owner.accountId;
    if (accountId != null) {
      await _push.sendToUser(
        accountId,
        title: subscriptionNoticeSubject(kind),
        body: 'Ouvrez MyWeli Pro pour les détails.',
        data: {'type': 'subscription', 'kind': kind},
      );
    }
  }
}
