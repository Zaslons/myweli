import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/utils/salon_id.dart';
import '../../models/admin_salon_validation.dart';
import '../../models/salon_validation.dart';
import '../../services/admin/admin_response.dart';
import '../../services/admin/admin_service.dart';
import 'admin_salon_validation_count_provider.dart';
import 'admin_salon_validations_provider.dart';

/// One request of « Salons à valider », and the decision (B0.18 —
/// docs/design/salon-go-live-approval.md §4.3): the salon, its owner, the
/// history; « Valider la mise en ligne » (or « Validation à terminer ») and
/// « Refuser ».
///
/// **After a decision,** the queue's row leaves its tab at once, the
/// sidebar's count re-reads (§4.2), and the detail re-reads quietly so its
/// history is current. **After a failed one,** everything is re-read — the
/// detail, the queue, the count — because a validation can answer 409 AFTER
/// its decision was written (the going-live failed): the request may now read
/// « Validation à terminer ». Only the refusal's input errors (a 400 on the
/// note or the code) change nothing and re-read nothing.
class AdminSalonValidationDetailProvider extends ChangeNotifier {
  AdminSalonValidationDetailProvider({
    AdminService? service,
    this._queue,
    this._count,
  }) : _service = service ?? adminService;

  final AdminService _service;
  final AdminSalonValidationsProvider? _queue;
  final AdminSalonValidationCountProvider? _count;

  bool _isLoading = false;
  String? _error;
  String? _errorCode;
  bool _unavailable = false;
  SalonValidationDetail? _detail;
  String? _actionError;
  String? _actionCode;
  List<String> _actionMissing = const [];

  bool get isLoading => _isLoading;
  String? get error => _error;

  /// The load's failure code — `not_found` is a salon that does not exist
  /// (a link to a deleted salon, a mistyped id): a state of its own on the
  /// screen, where « Réessayer » could never succeed (SYSTEM §12).
  String? get errorCode => _errorCode;

  /// The server predates B0.18 — its route is absent (a calm state, §9.2).
  bool get unavailable => _unavailable;
  SalonValidationDetail? get detail => _detail;

  /// The salon whose decision is out, or null, and the answer it waits for.
  /// One at a time: a decision asked for while another request's is still
  /// out waits for that answer, then is sent — never dropped, never sent
  /// beside it.
  SalonId? _actingOn;
  Future<void>? _settled;

  /// The salon whose decision waits for [_actingOn]'s answer.
  SalonId? _waitingOn;

  /// A decision on THIS request is out, or waiting its turn (the bar's
  /// buttons wait). A decision still out for a request the admin left does
  /// not busy this one's bar until this one asks for its own.
  bool get acting => _id != null && (_actingOn == _id || _waitingOn == _id);

  /// The last decision's failure, worded — shown in the sticky bar (a 409),
  /// or on the dialog's field ([actionCode] `note_required`/`note_too_long`).
  String? get actionError => _actionError;
  String? get actionCode => _actionCode;

  /// A 409 `incomplete`'s steps (`offer` among them for a lapsed offer).
  List<String> get actionMissing => _actionMissing;

  /// Whose detail this is. The provider is app-wide and outlives the screen,
  /// so without it the way to B showed A — A's photos, A's owner, and a
  /// « Valider » acting on B's id — until B answered (B9.8,
  /// docs/design/hygiene-batch9.md §14). The screen shows [detail] only when
  /// [id] is its own.
  SalonId? _id;
  SalonId? get id => _id;

  /// Bumped by every load: only the latest read writes.
  int _seq = 0;

  /// The refusal's input errors — a 400 on what the admin typed. Nothing
  /// changed on the server, so nothing is re-read.
  static const _inputErrors = {
    'invalid_input',
    'invalid_body',
    'note_required',
    'note_too_long',
  };

  Future<void> load(SalonId id) async {
    if (id != _id) {
      _id = id;
      _detail = null;
    }
    // A read shows the request as it is now: the last decision's answer — a
    // 409's sentence, its way to the salon's page — was about what was read
    // before, and could contradict this read (« Rafraîchir » after the fix,
    // the same request opened again). The re-read right after a decision
    // keeps it: that is [_refresh], not this.
    _clearAction();
    final seq = ++_seq;
    _isLoading = true;
    _error = null;
    _errorCode = null;
    _unavailable = false;
    notifyListeners();
    final res = await _service.salonValidationDetail(id);
    // Another read was asked for while this one was out: its answer is no
    // longer anybody's.
    if (seq != _seq || id != _id) return;
    _unavailable = res.routeMissing;
    if (res.success && res.data != null) {
      _detail = res.data;
    } else if (!res.routeMissing) {
      _error = res.error ?? 'Erreur lors du chargement';
      _errorCode = res.code;
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Re-reads the detail without the loading state — after a decision, under
  /// the bar's sentence. A failure keeps what is shown; a load started
  /// meanwhile wins.
  Future<void> _refresh(SalonId id) async {
    final seq = _seq;
    final res = await _service.salonValidationDetail(id);
    if (seq != _seq || id != _id) return;
    if (res.success && res.data != null) {
      _detail = res.data;
      notifyListeners();
    }
  }

  /// « Valider la mise en ligne », or « Validation à terminer »: sends the
  /// state this detail READ as `from` (§3.2). False without a request when
  /// there is nothing to validate here ([SalonValidationDetail.canApprove]),
  /// or when [id] is not this detail's.
  Future<bool> approve(SalonId id) => _decide(
    id,
    ready: (d) => d.canApprove,
    send: (d) => _service.approveSalonValidation(id, from: d.approveFrom!),
    outcome: (approval) => (approval.validation, approval.salonStatus),
  );

  /// « Refuser » with a code from §4.3's list and, for `other`, a note
  /// (≤ 500 code points, counted as the server counts them). An input the
  /// server would refuse is refused here first, on the field, with the
  /// server's own code and sentence — the server still checks it again. A
  /// request that is no longer pending as read (decided meanwhile) answers
  /// `validation_not_pending`, the server's own code: the dialog closes as
  /// a conflict, and the bar says why.
  Future<bool> refuse(SalonId id, {required String code, String? note}) async {
    final invalid = refusalInputError(code: code, note: note ?? '');
    if (invalid != null) {
      if (id != _id) return false;
      _actionCode = invalid;
      _actionError = AdminService.sentenceFor(invalid);
      _actionMissing = const [];
      notifyListeners();
      return false;
    }
    return _decide(
      id,
      ready: (d) => d.canRefuse,
      notReady: 'validation_not_pending',
      send: (_) => _service.refuseSalonValidation(id, code: code, note: note),
      outcome: (validation) => (validation, null),
    );
  }

  /// One decision on [id]. Waits first for another request's decision still
  /// out; then sends [send] when this detail is [id]'s and [ready] — both read
  /// AFTER the wait, since the admin may have left, or the detail moved on.
  /// Not ready: false, with [notReady]'s sentence in the bar when given.
  Future<bool> _decide<T extends Object>(
    SalonId id, {
    required bool Function(SalonValidationDetail d) ready,
    required Future<AdminResponse<T>> Function(SalonValidationDetail d) send,
    required (SalonValidation?, String?) Function(T data) outcome,
    String? notReady,
  }) async {
    while (_settled != null) {
      // Not this screen's request, or its own decision is already out or
      // waiting: nothing more to send.
      if (id != _id || acting) return false;
      _waitingOn = id;
      notifyListeners();
      await _settled;
      if (_waitingOn == id) _waitingOn = null;
    }
    final d = _detail;
    if (id != _id || d == null || !ready(d)) {
      if (id == _id && d != null && notReady != null) {
        _actionCode = notReady;
        _actionError = AdminService.sentenceFor(notReady);
        _actionMissing = const [];
      }
      notifyListeners();
      return false;
    }
    final settled = Completer<void>();
    _actingOn = id;
    _settled = settled.future;
    _clearAction();
    notifyListeners();
    try {
      final res = await send(d);
      final data = res.data;
      if (res.success && data != null) {
        final (validation, salonStatus) = outcome(data);
        if (id == _id && _detail != null) {
          _detail = _detail!.decided(validation, salonStatus: salonStatus);
        }
        _queue?.applyDecision(id, validation);
        unawaited(_count?.load());
        unawaited(_refresh(id));
        return true;
      }
      if (id == _id) {
        _actionCode = res.code;
        _actionError = res.error ?? 'Action impossible';
        _actionMissing = res.missing;
      }
      if (!_inputErrors.contains(res.code)) {
        unawaited(_refresh(id));
        unawaited(_queue?.load());
        unawaited(_count?.load());
      }
      return false;
    } finally {
      _actingOn = null;
      _settled = null;
      settled.complete();
      notifyListeners();
    }
  }

  /// The bar's sentence was read, or the dialog reopened.
  void clearActionError() {
    if (_actionError == null) return;
    _clearAction();
    notifyListeners();
  }

  void _clearAction() {
    _actionError = null;
    _actionCode = null;
    _actionMissing = const [];
  }
}
