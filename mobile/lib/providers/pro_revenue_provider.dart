import 'package:flutter/foundation.dart';

import '../core/access/pro_access_guard.dart';
import '../core/access/pro_salon_scope.dart';
import '../core/constants/failure_messages.dart';
import '../core/di/dependency_injection.dart';
import '../core/utils/salon_id.dart';
import '../models/api_response.dart';
import '../models/revenue_analytics.dart';
import '../services/interfaces/pro_service_interface.dart';

/// The figures one screen shows — « Revenus », or one of its details
/// (docs/design/pro-revenue-analytics.md §4.2, §4.8). **Keyed to its query**
/// (SYSTEM §12.1, « a detail's data is keyed to its id »): [analytics] is
/// the answer to [query] and never another's, so a period change shows the
/// skeleton, not the previous period's numbers under the new label (§4.11).
@immutable
class RevenueView {
  const RevenueView({
    required this.query,
    this.analytics,
    this.isLoading = false,
    this.loadError,
    this.refused = false,
    this.currency,
  });

  final RevenueQuery query;
  final RevenueAnalytics? analytics;
  final bool isLoading;

  /// The load's own failure (`AppErrorView`), null when it is a refusal.
  final String? loadError;

  /// The server said 403: « Réservé au propriétaire », no retry (§4.11).
  final bool refused;

  /// The currency group the owner chose (§4.11), null = the first.
  final String? currency;

  /// The group on screen.
  RevenueGroup? get group => analytics?.groupFor(currency);

  RevenueView _copy({
    RevenueQuery? query,
    RevenueAnalytics? analytics,
    bool clearAnalytics = false,
    bool? isLoading,
    String? loadError,
    bool clearError = false,
    bool? refused,
    String? currency,
    bool clearCurrency = false,
  }) => RevenueView(
    query: query ?? this.query,
    analytics: clearAnalytics ? null : (analytics ?? this.analytics),
    isLoading: isLoading ?? this.isLoading,
    loadError: clearError ? null : (loadError ?? this.loadError),
    refused: refused ?? this.refused,
    currency: clearCurrency ? null : (currency ?? this.currency),
  );
}

/// The bookings behind one figure (§4.9), a page of [pageSize] at a time.
@immutable
class RevenueLedgerView {
  const RevenueLedgerView({
    required this.query,
    required this.status,
    this.asOf,
    this.pageSize = 20,
    this.items = const [],
    this.total = 0,
    this.page = 0,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.loadError,
    this.moreError,
    this.refused = false,
  });

  final RevenueQuery query;
  final RevenueLedgerStatus status;

  /// The figures' `asOf`, so « À clôturer » lists what the banner counted.
  final DateTime? asOf;
  final int pageSize;
  final List<RevenueLedgerRow> items;
  final int total;

  /// The last page read; 0 = none yet.
  final int page;
  final bool isLoading;
  final bool isLoadingMore;
  final String? loadError;

  /// « Afficher plus » failed: the rows stay, the error sits under them.
  final String? moreError;
  final bool refused;

  bool get loaded => page > 0;
  bool get hasMore => items.length < total;
}

/// « Revenus » state (§9.2): the owner's comparison choice for the session,
/// and one [RevenueView] / [RevenueLedgerView] per screen. Replaces
/// `ProEarningsProvider`.
///
/// **A late answer is dropped** — each view carries a request number, the
/// booking hub's `slotsRequestId` pattern (§4.11): an older period's answer
/// arriving after a newer one's request is ignored. **A salon switch** drops
/// everything and every answer in flight ([resetForSalonSwitch]).
class ProRevenueProvider extends ChangeNotifier implements SalonScoped {
  ProRevenueProvider({ProServiceInterface? service})
    : _service = service ?? serviceLocator.proService;

  final ProServiceInterface _service;

  /// « Comparé à » — persists for the session, not on disk (§4.3).
  RevenueCompare get compare => _compare;
  RevenueCompare _compare = RevenueCompare.previous;

  final Map<String, RevenueView> _views = {};
  final Map<String, RevenueLedgerView> _ledgers = {};
  final Map<String, int> _requests = {};

  /// Which salon this state belongs to — moved by [resetForSalonSwitch]
  /// only (pro-account-scope.md §2.2).
  int _scope = 0;

  /// The view of [key], or null before its first load.
  RevenueView? view(String key) => _views[key];

  /// The ledger of [key], or null before its first load.
  RevenueLedgerView? ledger(String key) => _ledgers[key];

  int _next(String key) => _requests[key] = (_requests[key] ?? 0) + 1;

  bool _current(String key, int request, int scope) =>
      scope == _scope && _requests[key] == request;

  static bool _isRefusal(String? code) =>
      code == 'forbidden' || code == 'not_a_member';

  /// The owner chose another comparison: it holds for every screen until
  /// the session ends. The screen reloads its own view with it.
  void setCompare(RevenueCompare compare) {
    if (_compare == compare) return;
    _compare = compare;
    notifyListeners();
  }

  /// Loads [query] into [key]'s view. The old figures leave at once: the
  /// skeleton shows until this answer lands.
  Future<void> load(SalonId salon, String key, RevenueQuery query) async {
    final scope = _scope;
    final request = _next('view:$key');
    final before = _views[key];
    _views[key] = RevenueView(
      query: query,
      isLoading: true,
      // The chosen currency survives a period change; the server still
      // decides whether that group exists there.
      currency: before?.currency,
    );
    notifyListeners();

    ApiResponse<RevenueAnalytics> res;
    try {
      res = await _service.getRevenueAnalytics(salon, query);
    } catch (_) {
      res = ApiResponse.error(kGenericErrorMessage);
    }
    if (!_current('view:$key', request, scope)) return;
    final view = _views[key]!;
    if (res.success && res.data != null) {
      _views[key] = view._copy(
        analytics: res.data,
        isLoading: false,
        clearError: true,
        refused: false,
      );
    } else {
      ProAccessGuard.report(res.code);
      final refused = _isRefusal(res.code);
      _views[key] = view._copy(
        isLoading: false,
        clearAnalytics: true,
        refused: refused,
        loadError: refused ? null : (res.error ?? kGenericErrorMessage),
        clearError: refused,
      );
    }
    notifyListeners();
  }

  /// « Réessayer »: the same period again (§4.11).
  Future<void> retry(SalonId salon, String key) async {
    final view = _views[key];
    if (view == null) return;
    await load(salon, key, view.query);
  }

  /// The currency switcher (§4.11): another group of the same answer.
  void chooseCurrency(String key, String currency) {
    final view = _views[key];
    if (view == null || view.currency == currency) return;
    _views[key] = view._copy(currency: currency);
    notifyListeners();
  }

  /// The first page of [key]'s ledger.
  Future<void> loadLedger(
    SalonId salon,
    String key,
    RevenueQuery query,
    RevenueLedgerStatus status, {
    DateTime? asOf,
    int pageSize = 20,
  }) async {
    final scope = _scope;
    final request = _next('ledger:$key');
    _ledgers[key] = RevenueLedgerView(
      query: query,
      status: status,
      asOf: asOf,
      pageSize: pageSize,
      isLoading: true,
    );
    notifyListeners();

    ApiResponse<RevenueLedgerPage> res;
    try {
      res = await _service.getRevenueLedger(
        salon,
        query,
        status: status,
        page: 1,
        pageSize: pageSize,
        asOf: asOf,
      );
    } catch (_) {
      res = ApiResponse.error(kGenericErrorMessage);
    }
    if (!_current('ledger:$key', request, scope)) return;
    final base = _ledgers[key]!;
    if (res.success && res.data != null) {
      final page = res.data!;
      _ledgers[key] = RevenueLedgerView(
        query: base.query,
        status: base.status,
        // The page's own instant: « À clôturer » pages after it read the
        // same one, even when the screen was opened without it.
        asOf: base.asOf ?? page.asOf,
        pageSize: base.pageSize,
        items: page.items,
        total: page.total,
        page: 1,
      );
    } else {
      ProAccessGuard.report(res.code);
      final refused = _isRefusal(res.code);
      _ledgers[key] = RevenueLedgerView(
        query: base.query,
        status: base.status,
        asOf: base.asOf,
        pageSize: base.pageSize,
        refused: refused,
        loadError: refused ? null : (res.error ?? kGenericErrorMessage),
      );
    }
    notifyListeners();
  }

  /// « Afficher plus » (§4.9): the next page, appended.
  Future<void> loadMoreLedger(SalonId salon, String key) async {
    final base = _ledgers[key];
    if (base == null ||
        !base.loaded ||
        base.isLoading ||
        base.isLoadingMore ||
        !base.hasMore) {
      return;
    }
    final scope = _scope;
    final request = _next('ledger:$key');
    _ledgers[key] = _ledgerCopy(base, isLoadingMore: true);
    notifyListeners();

    ApiResponse<RevenueLedgerPage> res;
    try {
      res = await _service.getRevenueLedger(
        salon,
        base.query,
        status: base.status,
        page: base.page + 1,
        pageSize: base.pageSize,
        asOf: base.asOf,
      );
    } catch (_) {
      res = ApiResponse.error(kGenericErrorMessage);
    }
    if (!_current('ledger:$key', request, scope)) return;
    final now = _ledgers[key]!;
    if (res.success && res.data != null) {
      _ledgers[key] = _ledgerCopy(
        now,
        items: [...now.items, ...res.data!.items],
        total: res.data!.total,
        page: now.page + 1,
        isLoadingMore: false,
      );
    } else {
      ProAccessGuard.report(res.code);
      _ledgers[key] = _ledgerCopy(
        now,
        isLoadingMore: false,
        moreError: res.error ?? kGenericErrorMessage,
      );
    }
    notifyListeners();
  }

  RevenueLedgerView _ledgerCopy(
    RevenueLedgerView v, {
    List<RevenueLedgerRow>? items,
    int? total,
    int? page,
    bool? isLoadingMore,
    String? moreError,
  }) => RevenueLedgerView(
    query: v.query,
    status: v.status,
    asOf: v.asOf,
    pageSize: v.pageSize,
    items: items ?? v.items,
    total: total ?? v.total,
    page: page ?? v.page,
    isLoadingMore: isLoadingMore ?? v.isLoadingMore,
    moreError: moreError,
  );

  @override
  void resetForSalonSwitch() {
    _scope++;
    _views.clear();
    _ledgers.clear();
    _requests.clear();
    notifyListeners();
  }
}
