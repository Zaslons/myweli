/// The salon's offer row (pricing pivot — docs/design/team-access-r2a-offers.md).
/// A SEPARATE store by design: the public provider payload serializes the
/// whole `data` blob, so billing state must never live there.
library;

class SalonSubscriptionRow {
  SalonSubscriptionRow({
    required this.providerId,
    required this.tier,
    required this.trialEndsAt,
    required this.chosenAt,
    this.paidUntil,
    this.unpublishedAt,
  });

  final String providerId;

  /// `pro` | `business` | `reseau` (see [salonTiers]).
  final String tier;

  /// The ONE trial per salon: set on the first `chooseOffer`, never reset.
  final DateTime trialEndsAt;

  /// Manual billing (« Nous contacter ») — extended only by the audited
  /// admin action.
  final DateTime? paidUntil;

  /// Set when the enforcement cron unpublished the salon for non-payment;
  /// cleared on republish.
  final DateTime? unpublishedAt;

  final DateTime chosenAt;

  SalonSubscriptionRow copyWith({
    String? tier,
    DateTime? paidUntil,
    DateTime? unpublishedAt,
    bool clearUnpublished = false,
  }) => SalonSubscriptionRow(
    providerId: providerId,
    tier: tier ?? this.tier,
    trialEndsAt: trialEndsAt,
    chosenAt: chosenAt,
    paidUntil: paidUntil ?? this.paidUntil,
    unpublishedAt: clearUnpublished
        ? null
        : (unpublishedAt ?? this.unpublishedAt),
  );
}

abstract interface class SalonSubscriptionRepository {
  Future<SalonSubscriptionRow?> byProvider(String providerId);

  /// First offer choice: creates the row and starts the ONE trial.
  Future<SalonSubscriptionRow> create({
    required String providerId,
    required String tier,
    required DateTime trialEndsAt,
  });

  /// Tier switch / paid extension / unpublish bookkeeping.
  Future<SalonSubscriptionRow?> update(
    String providerId, {
    String? tier,
    DateTime? paidUntil,
    DateTime? unpublishedAt,
    bool clearUnpublished = false,
  });

  /// Every row (the daily cron walk — salon counts stay small pre-launch;
  /// paginate when they don't).
  Future<List<SalonSubscriptionRow>> all();

  /// Warning idempotency: true exactly once per (provider, kind).
  Future<bool> markNoticeIfNew(String providerId, String kind);

  /// A payment opens a new cycle — its warnings may fire again later.
  Future<void> clearNotices(String providerId);
}

class InMemorySalonSubscriptionRepository
    implements SalonSubscriptionRepository {
  final Map<String, SalonSubscriptionRow> _rows = {};
  final Set<String> _notices = {};

  @override
  Future<SalonSubscriptionRow?> byProvider(String providerId) async =>
      _rows[providerId];

  @override
  Future<SalonSubscriptionRow> create({
    required String providerId,
    required String tier,
    required DateTime trialEndsAt,
  }) async {
    final row = SalonSubscriptionRow(
      providerId: providerId,
      tier: tier,
      trialEndsAt: trialEndsAt,
      chosenAt: DateTime.now().toUtc(),
    );
    _rows[providerId] = row;
    return row;
  }

  @override
  Future<SalonSubscriptionRow?> update(
    String providerId, {
    String? tier,
    DateTime? paidUntil,
    DateTime? unpublishedAt,
    bool clearUnpublished = false,
  }) async {
    final row = _rows[providerId];
    if (row == null) return null;
    final next = row.copyWith(
      tier: tier,
      paidUntil: paidUntil,
      unpublishedAt: unpublishedAt,
      clearUnpublished: clearUnpublished,
    );
    _rows[providerId] = next;
    return next;
  }

  @override
  Future<List<SalonSubscriptionRow>> all() async => _rows.values.toList();

  @override
  Future<bool> markNoticeIfNew(String providerId, String kind) async =>
      _notices.add('$providerId/$kind');

  @override
  Future<void> clearNotices(String providerId) async =>
      _notices.removeWhere((k) => k.startsWith('$providerId/'));
}
