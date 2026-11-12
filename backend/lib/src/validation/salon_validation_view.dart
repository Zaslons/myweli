import '../subscription/salon_subscription_service.dart';
import 'salon_validation_dto.dart';
import 'salon_validation_repository.dart';

/// The salon side's `validation` (docs/design/salon-go-live-approval.md
/// §3.5) — what `GET /me/provider` carries beside `account`, `provider` and
/// `membership`, and each « Mes salons » entry of `GET /me/salons`: one
/// read path, so the switcher and « Configuration » can never disagree.
///
/// [statusById] maps each salon id to its `providers.status` now (null
/// reads `active`, as everywhere a seeded document has no status). The
/// answer holds an entry only for a salon that asked at least once (or was
/// validated by the backfill); a salon absent from it never asked, and the
/// caller writes `null`.
///
/// `offerLive` is added only for a validated salon that is not live now
/// (`approved` while `status` is not `active`): it tells « Plus en ligne :
/// impayé » from « Remettre en ligne » (§6.1). One `getMany` for every row;
/// the offer is read only for those few salons. No repository (a legacy
/// construction) and the offer stays unsaid.
///
/// **Who reads what.** The full view — `offerLive` and the admin's note —
/// goes only to a caller who holds `salon.publish` in that salon
/// ([publisherOf]: the owner, the audience of the go-live card and of the
/// decision's notice, §5.2, §6.2). Every other member reads the state, its
/// times and the refusal's code, enough for the switcher's line: `offerLive`
/// says whether the offer lapsed (« impayé »), billing state readable
/// otherwise only with `subscription.manage`; and the note is addressed to
/// the owner.
Future<Map<String, Map<String, dynamic>>> salonValidationViews(
  SalonValidationRepository validations,
  SalonSubscriptionService? subscriptions,
  Map<String, String?> statusById, {
  required Set<String> publisherOf,
}) async {
  if (statusById.isEmpty) return const {};
  final rows = await validations.getMany(statusById.keys);
  final views = <String, Map<String, dynamic>>{};
  for (final MapEntry(key: id, value: v) in rows.entries) {
    final publisher = publisherOf.contains(id);
    final notLive = (statusById[id] ?? 'active') != 'active';
    final offerLive =
        publisher && v.state == ValidationStates.approved && notLive
        ? await subscriptions?.hasLiveOffer(id)
        : null;
    views[id] = salonValidationJson(
      v,
      offerLive: offerLive,
      withNote: publisher,
    );
  }
  return views;
}
