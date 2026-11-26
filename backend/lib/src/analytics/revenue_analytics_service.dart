import '../access/capabilities.dart';
import '../access/membership_service.dart';
import '../appointments/appointment_repository.dart';
import '../clients/clients_repository.dart';
import '../providers_repository.dart';
import 'revenue_aggregator.dart';
import 'revenue_period.dart';

/// Outcome of a revenue read: the response JSON, or the machine code of the
/// refusal (`forbidden`, `not_found`, `invalid_input`, `range_too_long`).
typedef RevenueResult = ({bool ok, String? error, Map<String, dynamic>? data});

/// A revenue request, as the route parsed it (syntax only: the bounds need
/// the salon's today, so the service checks them).
class RevenueQuery {
  const RevenueQuery({
    required this.kind,
    this.compare = RevenueCompareMode.previous,
    this.date,
    this.from,
    this.to,
    this.filters = const RevenueFilters(),
  });

  final RevenuePeriodKind kind;
  final RevenueCompareMode compare;
  final DateTime? date;
  final DateTime? from;
  final DateTime? to;
  final RevenueFilters filters;
}

/// The ledger's `asOf` is accepted only this far back (§7.2): long enough for
/// an owner who left the screen open, short enough that a stale link cannot
/// replay an old « À clôturer » list.
const Duration kRevenueAsOfWindow = Duration(hours: 24);

/// The revenue endpoints' answers are one owner's money: never stored by a
/// cache, shared or not (§7.1).
const Map<String, String> kRevenueNoStore = {
  'Cache-Control': 'private, no-store',
};

/// The largest ledger page (§7.2).
const int kRevenueLedgerMaxPageSize = 50;

/// The salon's revenue analytics — docs/design/pro-revenue-analytics.md §7,
/// §9.1. Owner-only: `finances.view` on the salon, checked before any read
/// (threat T85); the ledger's client names also need `clients.view`.
///
/// Every definition is in [resolveRevenuePeriod] (the calendar) and
/// [aggregateRevenue] (the figures); this service only reads, gates and
/// shapes.
class RevenueAnalyticsService {
  RevenueAnalyticsService(
    this._members,
    this._appointments,
    this._providers,
    this._clients, {
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final MembershipService _members;
  final AppointmentRepository _appointments;
  final ProvidersRepository _providers;
  final ClientsRepository _clients;
  final DateTime Function() _now;

  /// `GET /providers/{id}/analytics/revenue`.
  Future<RevenueResult> revenue(
    String accountId,
    String providerId,
    RevenueQuery query,
  ) async {
    if (!await _members.can(accountId, providerId, Cap.financesView)) {
      return (ok: false, error: 'forbidden', data: null);
    }
    final salon = await _providers.byId(providerId);
    if (salon == null) return (ok: false, error: 'not_found', data: null);
    final resolved = _resolve(query, salon, _now().toUtc());
    final period = resolved.period;
    if (period == null) return (ok: false, error: resolved.error, data: null);

    final current = await _appointments.revenueRows(
      providerId,
      period.startUtc,
      period.endUtc,
    );
    final compareStart = period.compareStartUtc;
    final compareEnd = period.compareEndUtc;
    final previous = (compareStart == null || compareEnd == null)
        ? null
        : await _appointments.revenueRows(providerId, compareStart, compareEnd);

    return (
      ok: true,
      error: null,
      data: aggregateRevenue(
        period: period,
        currentRows: current,
        previousRows: previous,
        catalogue: RevenueCatalogue.fromSalon(salon),
        filters: query.filters,
        salonCurrency: (salon['currency'] as String?) ?? 'XOF',
        everCompleted: await _appointments.hasCompleted(providerId),
      ),
    );
  }

  /// `GET /providers/{id}/analytics/revenue/appointments`.
  ///
  /// [asOf] is the figures' own `asOf`, so « À clôturer » lists exactly the
  /// bookings the banner counted; accepted within [kRevenueAsOfWindow] and
  /// not in the future, absent → now.
  Future<RevenueResult> ledger(
    String accountId,
    String providerId,
    RevenueQuery query, {
    required RevenueLedgerStatus status,
    required int page,
    required int pageSize,
    DateTime? asOf,
  }) async {
    if (!await _members.can(accountId, providerId, Cap.financesView)) {
      return (ok: false, error: 'forbidden', data: null);
    }
    final now = _now().toUtc();
    final at = asOf?.toUtc() ?? now;
    if (at.isAfter(now) || now.difference(at) > kRevenueAsOfWindow) {
      return (ok: false, error: 'invalid_input', data: null);
    }
    if (page < 1 || pageSize < 1 || pageSize > kRevenueLedgerMaxPageSize) {
      return (ok: false, error: 'invalid_input', data: null);
    }
    final salon = await _providers.byId(providerId);
    if (salon == null) return (ok: false, error: 'not_found', data: null);
    final resolved = _resolve(query, salon, at);
    final period = resolved.period;
    if (period == null) return (ok: false, error: resolved.error, data: null);

    final filters = query.filters;
    final result = await _appointments.revenueLedger(
      providerId,
      fromUtc: period.startUtc,
      toUtcExclusive: period.endUtc,
      status: status,
      asOf: at,
      limit: pageSize,
      offset: (page - 1) * pageSize,
      artistId: filters.artistId,
      serviceId: filters.serviceId,
      channel: filters.channel,
    );

    // Field-gated on clients.view (§7.2, §10): without it, no name at all.
    final names = await _members.can(accountId, providerId, Cap.clientsView)
        ? await _clientNames(providerId, result.items)
        : null;
    final catalogue = RevenueCatalogue.fromSalon(salon);
    return (
      ok: true,
      error: null,
      data: {
        'items': [
          for (final row in result.items)
            _ledgerRow(row, catalogue, filters.serviceId, names),
        ],
        'page': page,
        'pageSize': pageSize,
        'total': result.total,
        'asOf': at.toIso8601String(),
      },
    );
  }

  RevenuePeriodResult _resolve(
    RevenueQuery q,
    Map<String, dynamic> salon,
    DateTime asOf,
  ) => resolveRevenuePeriod(
    kind: q.kind,
    compare: q.compare,
    asOf: asOf,
    tzName: salon['timezone'] as String?,
    date: q.date,
    from: q.from,
    to: q.to,
  );

  /// The page's client names in one read — never `enrichForProvider`, which
  /// reads the salon's whole history on every call. Resolved as the journal
  /// does (`ClientsService._resolveClient`): an online booking by its
  /// `userId`, a salon-entered one by its phone.
  Future<({Map<String, String> byUserId, Map<String, String> byPhone})>
  _clientNames(String providerId, List<Map<String, dynamic>> rows) {
    final userIds = <String>{};
    final phones = <String>{};
    for (final r in rows) {
      final uid = r['userId'];
      if (uid is String && uid != 'manual') {
        userIds.add(uid);
      } else if (r['clientPhone'] case final String phone
          when phone.isNotEmpty) {
        phones.add(phone);
      }
    }
    return _clients.displayNamesFor(
      providerId,
      userIds: userIds,
      phones: phones,
    );
  }

  Map<String, dynamic> _ledgerRow(
    Map<String, dynamic> row,
    RevenueCatalogue catalogue,
    String? serviceId,
    ({Map<String, String> byUserId, Map<String, String> byPhone})? names,
  ) {
    final lines = revenueLinesOf(row, catalogue);
    final total = (row['totalPrice'] as num).toDouble();
    var amount = total;
    var estimated = false;
    if (serviceId != null) {
      amount = 0;
      for (final l in lines) {
        if (l.serviceId != serviceId) continue;
        amount += l.amount;
        estimated = estimated || l.estimated;
      }
    }
    final currency = (row['currency'] as String?) ?? 'XOF';

    final artistKey = revenueArtistKeyOf(row);
    String? artistLabel;
    String artistState;
    if (artistKey == null) {
      artistState = 'unassigned';
    } else if (catalogue.artistNames.containsKey(artistKey)) {
      artistState = 'active';
      artistLabel = catalogue.artistNames[artistKey];
    } else {
      artistState = 'removed';
      final kept = row['artistNameKept'];
      artistLabel = (kept is String && kept.isNotEmpty) ? kept : null;
    }

    String? clientName;
    if (names != null) {
      final uid = row['userId'];
      clientName = (uid is String && uid != 'manual')
          ? names.byUserId[uid]
          : names.byPhone[row['clientPhone']];
    }

    return {
      'appointmentId': row['id'],
      'appointmentDate': row['appointmentDate'],
      'status': row['status'],
      'amount': roundToCurrency(amount, currency),
      'totalPrice': total,
      'currency': currency,
      // ABSENT, not null, without clients.view or a resolved client.
      if (clientName != null) 'clientDisplayName': clientName,
      'serviceNames': [
        for (final l in lines)
          catalogue.serviceNames.containsKey(l.serviceId)
              ? catalogue.serviceNames[l.serviceId]
              : l.keptName,
      ],
      'artistLabel': artistLabel,
      'artistState': artistState,
      'channel': revenueChannelOf(row),
      'estimated': estimated,
    };
  }
}
