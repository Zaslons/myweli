import '../access/membership_repository.dart';
import '../email/email_provider.dart';
import '../email/send_budget.dart';
import '../email/subscription_emails.dart';
import '../providers_repository.dart';
import '../push/push_service.dart';
import '../site/site_rebuild_notifier.dart';
import '../validation/salon_validation_repository.dart';
import 'salon_subscription_repository.dart';
import 'salon_subscription_service.dart';

typedef SubscriptionTickResult = ({int notices, int unpublished});

/// The daily subscription walk (docs/design/team-access-r2a-offers.md),
/// driven by `POST /internal/cron/subscriptions` (OIDC-gated, like the
/// reminders cron). Idempotent: every notice fires once per
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
    SiteRebuildNotifier? rebuild,
    SalonValidationRepository? validations,
  }) : _enforce = enforce,
       _rebuild = rebuild ?? NoopSiteRebuildNotifier(),
       _validations = validations;

  final SalonSubscriptionRepository _subscriptions;
  final MembershipRepository _memberships;
  final ProvidersRepository _providers;
  final EmailProvider _email;
  final PushService _push;
  final bool _enforce;
  final SiteRebuildNotifier _rebuild;

  /// R10 (B0.18 — docs/design/salon-go-live-approval.md §3.6): billing
  /// notices go only to salons MyWeli validated that went live. A salon
  /// waiting with a running trial (an offer chosen on the website first)
  /// would otherwise read « Votre salon reste visible pendant 7 jours » — false
  /// for a salon never public. It still sees its countdown in « Mon
  /// abonnement ». Optional so test constructions compile; absent, no notice
  /// is sent (fail closed) — `salon_validation_wiring_test.dart` pins the
  /// composition root.
  final SalonValidationRepository? _validations;

  Future<SubscriptionTickResult> tick(DateTime now) async {
    var notices = 0;
    var unpublished = 0;

    final rows = await _subscriptions.all();
    // ONE read for the whole walk, not one per salon.
    final validated =
        await _validations?.getMany([for (final r in rows) r.providerId]) ??
        const <String, SalonValidation>{};
    bool notifiable(String providerId) {
      final v = validated[providerId];
      return v != null && v.state == ValidationStates.approved && v.wentLive;
    }

    for (final row in rows) {
      final paidCovers = row.paidUntil != null && now.isBefore(row.paidUntil!);
      if (paidCovers) continue;

      // Checked BEFORE the notice is marked sent: a waiting salon's notice
      // is not burnt, so once validated and live it gets the current one.
      final kind = notifiable(row.providerId) ? _kindFor(row, now) : null;
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
          if (notifiable(row.providerId) &&
              await _subscriptions.markNoticeIfNew(
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
    // Once per tick, not per salon: the loop's own `status == 'active'`
    // guard makes the counter exactly "the prebuilt set shrank". Firing
    // inside the loop would lean on the notifier's cooldown to coalesce —
    // semantics this fire should not depend on.
    if (unpublished > 0) {
      await _rebuild.requestRebuild('salon.unpublished');
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
  /// carries both the account id and the email). The e-mail only to an
  /// address ([Member.emailOrNull]): a phone-registered owner's row holds a
  /// phone number there, and gets the push alone.
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

    final to = owner.emailOrNull;
    if (to != null) {
      await _email.send(
        // WARM: a notice to a salon about its own subscription. Starving
        // these is the availability attack the split exists to prevent.
        classification: EmailClass.warm,
        to: to,
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
