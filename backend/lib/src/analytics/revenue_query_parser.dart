import '../appointments/appointment_repository.dart';
import 'revenue_aggregator.dart';
import 'revenue_analytics_service.dart';
import 'revenue_period.dart';

// The boundary of the revenue endpoints: every query parameter checked for
// its syntax before anything is read (docs/design/pro-revenue-analytics.md
// §7.1, §7.2). The bounds that need the salon's today are the service's.

final RegExp _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final RegExp _id = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
final RegExp _int = RegExp(r'^\d{1,6}$');

/// An instant with its offset written out (`Z` or `±hh:mm`): without one,
/// Dart reads it in the server's own zone.
final RegExp _instantWithOffset = RegExp(r'(Z|[+-]\d{2}:?\d{2})$');

/// A strict `YYYY-MM-DD` that names a real day, or null.
DateTime? parseRevenueDate(String? text) {
  if (text == null || !_date.hasMatch(text)) return null;
  final y = int.parse(text.substring(0, 4));
  final m = int.parse(text.substring(5, 7));
  final d = int.parse(text.substring(8, 10));
  final date = DateTime.utc(y, m, d);
  // 2026-02-30 would otherwise roll over to 2 March.
  if (date.year != y || date.month != m || date.day != d) return null;
  return date;
}

T? _enumByName<T extends Enum>(List<T> values, String text) {
  for (final v in values) {
    if (v.name == text) return v;
  }
  return null;
}

/// The query of either endpoint, or null for a 400 `invalid_input`.
RevenueQuery? parseRevenueQuery(Map<String, String> q) {
  final periodText = q['period'];
  if (periodText == null) return null;
  final kind = _enumByName(RevenuePeriodKind.values, periodText);
  if (kind == null) return null;

  var compare = RevenueCompareMode.previous;
  if (q['compare'] case final String text) {
    final mode = _enumByName(RevenueCompareMode.values, text);
    if (mode == null) return null;
    compare = mode;
  }

  DateTime? date;
  DateTime? from;
  DateTime? to;
  if (kind == RevenuePeriodKind.custom) {
    if (q.containsKey('date')) return null;
    from = parseRevenueDate(q['from']);
    to = parseRevenueDate(q['to']);
    if (from == null || to == null) return null;
  } else {
    if (q.containsKey('from') || q.containsKey('to')) return null;
    if (q.containsKey('date')) {
      date = parseRevenueDate(q['date']);
      if (date == null) return null;
    }
  }

  final artistId = q['artistId'];
  if (artistId != null && !_id.hasMatch(artistId)) return null;
  final serviceId = q['serviceId'];
  if (serviceId != null && !_id.hasMatch(serviceId)) return null;
  final channel = q['channel'];
  // Exactly the four names: `Web` is not `web`.
  if (channel != null && !kRevenueChannels.contains(channel)) return null;

  return RevenueQuery(
    kind: kind,
    compare: compare,
    date: date,
    from: from,
    to: to,
    filters: RevenueFilters(
      artistId: artistId,
      serviceId: serviceId,
      channel: channel,
    ),
  );
}

/// The ledger's own parameters, or null for a 400 `invalid_input`.
({RevenueLedgerStatus status, int page, int pageSize, DateTime? asOf})?
parseRevenueLedgerParams(Map<String, String> q) {
  var status = RevenueLedgerStatus.completed;
  if (q['status'] case final String text) {
    final s = _enumByName(RevenueLedgerStatus.values, text);
    if (s == null) return null;
    status = s;
  }
  var page = 1;
  if (q['page'] case final String text) {
    if (!_int.hasMatch(text)) return null;
    page = int.parse(text);
    if (page < 1) return null;
  }
  var pageSize = 20;
  if (q['pageSize'] case final String text) {
    if (!_int.hasMatch(text)) return null;
    pageSize = int.parse(text);
    if (pageSize < 1 || pageSize > kRevenueLedgerMaxPageSize) return null;
  }
  DateTime? asOf;
  if (q['asOf'] case final String text) {
    if (!_instantWithOffset.hasMatch(text)) return null;
    asOf = DateTime.tryParse(text)?.toUtc();
    if (asOf == null) return null;
  }
  return (status: status, page: page, pageSize: pageSize, asOf: asOf);
}
