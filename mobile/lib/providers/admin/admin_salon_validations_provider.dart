import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/utils/salon_id.dart';
import '../../models/admin_salon_validation.dart';
import '../../models/salon_validation.dart';
import '../../services/admin/admin_service.dart';

/// « Salons à valider » — the queue (B0.18,
/// docs/design/salon-go-live-approval.md §4.2): three tabs, « En attente »
/// (oldest request first) · « Refusés » · « Validés », [pageSize] per page
/// with previous/next (the audit log's pattern).
///
/// **Before the backend deploy** (§9.2) the route answers 404: [unavailable]
/// is then true and [error] null — the screen shows a calm, explicit state,
/// never an error.
class AdminSalonValidationsProvider extends ChangeNotifier {
  AdminSalonValidationsProvider({AdminService? service})
    : _service = service ?? adminService;

  final AdminService _service;

  static const pageSize = 50;

  /// The tabs, in the order the console shows them.
  static const tabs = [
    SalonValidationState.pending,
    SalonValidationState.refused,
    SalonValidationState.approved,
  ];

  bool _isLoading = false;
  String? _error;
  bool _unavailable = false;
  List<SalonValidationQueueItem> _items = const [];
  int _page = 1;
  int _total = 0;
  SalonValidationState _tab = SalonValidationState.pending;

  bool get isLoading => _isLoading;
  String? get error => _error;

  /// The server predates B0.18 — its route is absent.
  bool get unavailable => _unavailable;
  List<SalonValidationQueueItem> get items => _items;
  int get page => _page;
  int get total => _total;
  SalonValidationState get tab => _tab;
  bool get hasPrev => _page > 1;
  bool get hasNext => _page * pageSize < _total;

  /// Bumped by every load: a tab or a page asked for while a read was out
  /// makes that read's answer nobody's — « Refusés » never lands under
  /// « En attente ».
  int _seq = 0;

  Future<void> load() => _read(quiet: false);

  /// One read of the tab's page. [quiet] keeps what is shown while it is out
  /// — no loading state, and a failure changes nothing: the re-read after a
  /// decision, under rows that are already right but for the one that left.
  Future<void> _read({required bool quiet}) async {
    final seq = ++_seq;
    final tab = _tab;
    final page = _page;
    if (!quiet) {
      _isLoading = true;
      _error = null;
      notifyListeners();
    }
    final res = await _service.salonValidationQueue(
      state: tab,
      page: page,
      pageSize: pageSize,
    );
    if (seq != _seq) return;
    final data = res.data;
    if (res.success && data != null) {
      // A page past the last: requests were decided meanwhile (by another
      // admin, or refused salons asked again), and the provider keeps its
      // page across visits. The last page that holds some is read instead —
      // never « Aucun salon en attente » while the total says otherwise.
      if (data.items.isEmpty && page > 1 && data.total > 0) {
        final last = (data.total - 1) ~/ pageSize + 1;
        if (last < page) {
          _page = last;
          return _read(quiet: quiet);
        }
      }
      _unavailable = false;
      _items = data.items;
      _total = data.total;
    } else if (!quiet) {
      _unavailable = res.routeMissing;
      _items = const [];
      _total = 0;
      _error = res.routeMissing
          ? null
          : (res.error ?? 'Erreur lors du chargement');
    }
    _isLoading = false;
    notifyListeners();
  }

  void setTab(SalonValidationState tab) {
    assert(tabs.contains(tab), 'not a tab');
    if (_tab == tab) return;
    _tab = tab;
    _page = 1;
    _items = const [];
    _total = 0;
    load();
  }

  void nextPage() {
    if (!hasNext) return;
    _page++;
    load();
  }

  void prevPage() {
    if (!hasPrev) return;
    _page--;
    load();
  }

  /// A decision answered for [id] (§4.2: « the row leaves the tab at
  /// once »). [now] is the validation it returned: a row whose state still
  /// belongs to this tab stays, updated — « Validation à terminer » finished
  /// under « Validés » is still validated — and any other leaves, with the
  /// total. Nothing to do when the row is not on this page.
  ///
  /// A page emptied this way past the first steps back one page, so the tab
  /// never reads « Aucun salon » while earlier pages hold some. A page with
  /// more after it is re-read quietly: on the server the next request has
  /// moved up into it, and without the re-read « Suivant » would skip it —
  /// or, its total lowered, not be offered at all.
  void applyDecision(SalonId id, SalonValidation? now) {
    final i = _items.indexWhere((r) => r.providerId == id);
    if (i < 0) return;
    if (now != null && now.state == _tab) {
      _items = List.unmodifiable([
        for (final r in _items) r.providerId == id ? r.withValidation(now) : r,
      ]);
      notifyListeners();
      return;
    }
    _items = List.unmodifiable([
      for (final r in _items)
        if (r.providerId != id) r,
    ]);
    final before = _total;
    _total = _total > 0 ? _total - 1 : 0;
    if (_items.isEmpty && _page > 1) {
      _page--;
      load();
      return;
    }
    notifyListeners();
    if (before > _page * pageSize) unawaited(_read(quiet: true));
  }
}
