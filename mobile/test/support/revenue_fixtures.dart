/// The answers of `GET /providers/{id}/analytics/revenue` and its ledger, as
/// the contract shapes them (docs/api/openapi.yaml `RevenueAnalytics`,
/// `RevenueLedgerPage`) — every nullable field sent as null, never absent
/// (pro-revenue-analytics.md §20.1 item 2). One builder, so the model test,
/// the provider test and the screens' tests read the same body.
library;

Map<String, dynamic> revenueFigures({
  num completedAmount = 1250000,
  int completedCount = 48,
  num? averageTicket = 26042,
  num upcomingAmount = 320000,
  int upcomingCount = 12,
  num pendingAmount = 45000,
  int pendingCount = 3,
  num toCloseAmount = 60000,
  int toCloseCount = 4,
  num noShowAmount = 45000,
  int noShowCount = 3,
  num? noShowRate = 0.0588,
  num cancelledAmount = 30000,
  int cancelledCount = 2,
  bool estimated = false,
}) => {
  'completedAmount': completedAmount,
  'completedCount': completedCount,
  'averageTicket': averageTicket,
  'upcomingAmount': upcomingAmount,
  'upcomingCount': upcomingCount,
  'pendingAmount': pendingAmount,
  'pendingCount': pendingCount,
  'toCloseAmount': toCloseAmount,
  'toCloseCount': toCloseCount,
  'noShowAmount': noShowAmount,
  'noShowCount': noShowCount,
  'noShowRate': noShowRate,
  'cancelledAmount': cancelledAmount,
  'cancelledCount': cancelledCount,
  'estimated': estimated,
};

Map<String, dynamic> revenueRow({
  String? key,
  String? label,
  String state = 'active',
  num share = 0.5,
  num amount = 100000,
  int count = 4,
  num? previousAmount = 90000,
  int previousCount = 4,
  bool estimated = false,
}) => {
  'key': key,
  'label': label,
  'state': state,
  'share': share,
  'current': {
    'completedAmount': amount,
    'completedCount': count,
    'averageTicket': count == 0 ? null : (amount / count).round(),
  },
  'previous': previousAmount == null
      ? null
      : {
          'completedAmount': previousAmount,
          'completedCount': previousCount,
          'averageTicket': previousCount == 0
              ? null
              : (previousAmount / previousCount).round(),
        },
  'estimated': estimated,
};

/// November 2026, in progress on the 25th at 14:30 (Abidjan), compared with
/// October cut at the same point — the spec's own example (§3.5, §4.2).
Map<String, dynamic> revenueAnalyticsJson({
  String period = 'month',
  String from = '2026-11-01',
  String to = '2026-11-30',
  bool inProgress = true,
  String asOf = '2026-11-25T14:30:00.000Z',
  String bucket = 'day',
  String compareMode = 'previous',
  bool everCompleted = true,
  List<Map<String, dynamic>>? groups,
  Map<String, dynamic>? filters,
}) => {
  'period': period,
  'from': from,
  'to': to,
  'inProgress': inProgress,
  'timezone': 'Africa/Abidjan',
  'asOf': asOf,
  'bucket': bucket,
  'comparison': compareMode == 'none'
      ? {
          'mode': 'none',
          'from': null,
          'to': null,
          'likeForLike': false,
          'cutoff': null,
        }
      : {
          'mode': compareMode,
          'from': '2026-10-01',
          'to': '2026-10-31',
          'likeForLike': inProgress,
          'cutoff': inProgress ? '2026-10-25T14:30:00.000Z' : null,
        },
  'filters':
      filters ??
      {
        'artistId': null,
        'serviceId': null,
        'channel': null,
        'label': null,
        'state': null,
      },
  'everCompleted': everCompleted,
  'groups': groups ?? [revenueGroup()],
};

Map<String, dynamic> revenueGroup({
  String currency = 'XOF',
  Map<String, dynamic>? current,
  Map<String, dynamic>? previous,
  bool withPrevious = true,
  List<Map<String, dynamic>>? series,
  List<Map<String, dynamic>>? byArtist,
  List<Map<String, dynamic>>? byService,
  List<Map<String, dynamic>>? byChannel,
}) => {
  'currency': currency,
  'current': current ?? revenueFigures(),
  'previous': withPrevious
      ? (previous ??
            revenueFigures(
              completedAmount: 1116000,
              completedCount: 46,
              averageTicket: 24261,
              noShowRate: 0.0706,
            ))
      : null,
  'series':
      series ??
      [
        for (var d = 1; d <= 30; d++)
          {
            'start': '2026-11-${d.toString().padLeft(2, '0')}',
            'end': '2026-11-${d.toString().padLeft(2, '0')}',
            'completedAmount': d <= 25
                ? (d % 7 == 0 ? 0 : 20000 + d * 1000)
                : 0,
            'completedCount': d <= 25 ? (d % 7 == 0 ? 0 : 2) : 0,
          },
      ],
  'byArtist':
      byArtist ??
      [
        revenueRow(
          key: 'artist1',
          label: 'Awa Koné',
          share: 0.336,
          amount: 420000,
          count: 16,
          previousAmount: 385000,
          previousCount: 15,
        ),
        revenueRow(
          key: 'artist2',
          label: 'Salimata Ouattara',
          share: 0.304,
          amount: 380000,
          count: 15,
          previousAmount: 380000,
          previousCount: 14,
        ),
        revenueRow(
          key: 'artist_parti',
          label: 'Konan Serge',
          state: 'removed',
          share: 0.2,
          amount: 250000,
          count: 9,
          previousAmount: 300000,
          previousCount: 11,
        ),
        revenueRow(
          key: null,
          state: 'unassigned',
          share: 0.16,
          amount: 200000,
          count: 8,
          previousAmount: 51000,
          previousCount: 6,
        ),
        revenueRow(
          key: 'artist_old',
          state: 'removed',
          share: 0,
          amount: 0,
          count: 0,
          previousAmount: 0,
          previousCount: 0,
        ),
      ],
  'byService':
      byService ??
      [
        revenueRow(
          key: 'svc_tresses',
          label: 'Tresses africaines avec rajouts',
          share: 0.6,
          amount: 750000,
          count: 20,
          estimated: true,
        ),
        revenueRow(
          key: 'svc_nattes',
          label: 'Nattes',
          state: 'removed',
          share: 0.3,
          amount: 375000,
          count: 15,
        ),
        revenueRow(
          key: 'svc_gone',
          state: 'removed',
          share: 0.1,
          amount: 125000,
          count: 5,
          previousAmount: 0,
          previousCount: 0,
        ),
      ],
  'byChannel':
      byChannel ??
      [
        revenueRow(key: 'app', share: 0.4, amount: 500000, count: 20),
        revenueRow(key: 'salon', share: 0.3, amount: 375000, count: 14),
        revenueRow(key: 'web', share: 0.2, amount: 250000, count: 9),
        revenueRow(
          key: 'online',
          state: 'legacy',
          share: 0.1,
          amount: 125000,
          count: 5,
        ),
      ],
};

Map<String, dynamic> revenueLedgerRow({
  String id = 'a1',
  String date = '2026-11-25T14:30:00.000Z',
  String status = 'completed',
  num amount = 35000,
  num totalPrice = 35000,
  String currency = 'XOF',
  String? client = 'Fatou B.',
  List<String?> services = const ['Tresses'],
  String? artistLabel = 'Awa Koné',
  String artistState = 'active',
  String channel = 'app',
  bool estimated = false,
}) => {
  'appointmentId': id,
  'appointmentDate': date,
  'status': status,
  'amount': amount,
  'totalPrice': totalPrice,
  'currency': currency,
  'clientDisplayName': ?client,
  'serviceNames': services,
  'artistLabel': artistLabel,
  'artistState': artistState,
  'channel': channel,
  'estimated': estimated,
};

Map<String, dynamic> revenueLedgerJson({
  List<Map<String, dynamic>>? items,
  int page = 1,
  int pageSize = 20,
  int? total,
  String asOf = '2026-11-25T14:30:00.000Z',
}) {
  final rows = items ?? [revenueLedgerRow()];
  return {
    'items': rows,
    'page': page,
    'pageSize': pageSize,
    'total': total ?? rows.length,
    'asOf': asOf,
  };
}
