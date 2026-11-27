import 'dart:async';

import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/revenue_analytics.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';

import 'revenue_fixtures.dart';

/// The 25th of November 2026, 14:30 in Abidjan — the fixtures' `asOf`.
final DateTime kRevenueNow = DateTime.utc(2026, 11, 25, 14, 30);

/// The server's `filters` for [q]: the id echoed, the row's label and state.
Map<String, dynamic> echoFilters(RevenueQuery q) => {
  'artistId': q.artistId,
  'serviceId': q.serviceId,
  'channel': q.channel?.name,
  'label': switch (q.artistId ?? q.serviceId) {
    'artist1' => 'Awa Koné',
    'svc_tresses' => 'Tresses africaines avec rajouts',
    _ => null,
  },
  'state': q.filterAxis == null
      ? null
      : q.artistId == RevenueQuery.kNoArtist
      ? 'unassigned'
      : q.channel == RevenueChannel.online
      ? 'legacy'
      : (q.artistId == 'artist1' ||
            q.serviceId == 'svc_tresses' ||
            q.channel != null)
      ? 'active'
      : 'removed',
};

/// A Pro service whose revenue answers are the contract's own bodies
/// (test/support/revenue_fixtures.dart), and which records every question.
class FakeRevenueService extends MockProService {
  /// The answer to [q] — its filter echoed, as the server echoes it.
  Map<String, dynamic> Function(RevenueQuery q) analytics = (q) =>
      revenueAnalyticsJson(filters: echoFilters(q));
  Map<String, dynamic> Function(RevenueLedgerStatus s, int page) ledger =
      (_, _) => revenueLedgerJson(
        items: [
          revenueLedgerRow(),
          revenueLedgerRow(
            id: 'a2',
            date: '2026-11-24T10:00:00.000Z',
            client: null,
            services: ['Nattes', null],
            artistLabel: null,
            artistState: 'unassigned',
            channel: 'salon',
          ),
        ],
        total: 48,
      );

  /// Set to answer a refusal or a failure instead.
  ApiResponse<RevenueAnalytics>? failure;

  /// Set to hold the next answers until it completes (a slow network).
  Completer<void>? hold;
  final List<RevenueQuery> asked = [];
  final List<({RevenueQuery query, RevenueLedgerStatus status, int page})>
  ledgerAsked = [];

  /// The `asOf` each ledger page was asked with.
  final List<DateTime?> ledgerAsOf = [];

  @override
  Future<ApiResponse<RevenueAnalytics>> getRevenueAnalytics(
    SalonId providerId,
    RevenueQuery query,
  ) async {
    asked.add(query);
    await hold?.future;
    final f = failure;
    if (f != null) return f;
    return ApiResponse.success(RevenueAnalytics.fromJson(analytics(query)));
  }

  @override
  Future<ApiResponse<RevenueLedgerPage>> getRevenueLedger(
    SalonId providerId,
    RevenueQuery query, {
    RevenueLedgerStatus status = RevenueLedgerStatus.completed,
    int page = 1,
    int pageSize = 20,
    DateTime? asOf,
  }) async {
    ledgerAsked.add((query: query, status: status, page: page));
    ledgerAsOf.add(asOf);
    return ApiResponse.success(
      RevenueLedgerPage.fromJson(ledger(status, page)),
    );
  }
}
