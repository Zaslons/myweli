import '../reviews_repository.dart';
import '../reviews_service.dart';
import 'audit_log_repository.dart';

/// Outcome of a moderation operation; [data] is the response body on success.
typedef ModerationResult = ({bool ok, String? error, Object? data});

/// Review moderation (design: docs/design/admin-console.md). Consumers **report**
/// a review (it stays visible until a human acts — no auto-hide); an admin then
/// **hides** (excluded from feed + rating), **dismisses** the reports (legit
/// review), or **restores** a hidden one. Every admin decision is audited and
/// re-runs the rating recompute.
class ModerationService {
  ModerationService(this._reviews, this._reviewsService, this._audit);

  final ReviewsRepository _reviews;
  final ReviewsService _reviewsService;
  final AuditLogRepository _audit;

  static const _maxReason = 500;

  /// Consumer flags a review (FR-REV-005). Idempotent per (review, reporter).
  Future<ModerationResult> report(
    String userId,
    String reviewId,
    Object? reason,
  ) async {
    final r = reason is String ? reason.trim() : '';
    if (r.length > _maxReason) {
      return (ok: false, error: 'invalid_input', data: null);
    }
    if (await _reviews.reviewById(reviewId) == null) {
      return (ok: false, error: 'not_found', data: null);
    }
    await _reviews.addReport(reviewId, userId, r);
    return (ok: true, error: null, data: {'status': 'reported'});
  }

  Future<ModerationResult> queue({int page = 1, int pageSize = 20}) async {
    final res = await _reviews.listReportedReviews(
      page: page,
      pageSize: pageSize,
    );
    return (
      ok: true,
      error: null,
      data: {
        'items': res.items,
        'page': page,
        'pageSize': pageSize,
        'total': res.total,
      },
    );
  }

  /// The "Avis masqués" view — currently-hidden reviews (restore entry point).
  Future<ModerationResult> hiddenQueue({
    int page = 1,
    int pageSize = 20,
  }) async {
    final res = await _reviews.listHidden(page: page, pageSize: pageSize);
    return (
      ok: true,
      error: null,
      data: {
        'items': res.items,
        'page': page,
        'pageSize': pageSize,
        'total': res.total,
      },
    );
  }

  Future<ModerationResult> hide(
    String adminId,
    String reviewId,
    Object? reason,
  ) async {
    final updated = await _reviews.setModerationStatus(reviewId, 'hidden');
    if (updated == null) return (ok: false, error: 'not_found', data: null);
    await _reviews.resolveReports(reviewId, adminId);
    await _reviewsService.recomputeRatings(updated['providerId'] as String);
    await _audit.append((
      actorAdminId: adminId,
      action: 'review.hide',
      targetType: 'review',
      targetId: reviewId,
      reason: reason is String && reason.trim().isNotEmpty
          ? reason.trim()
          : null,
      metadata: const {},
    ));
    return (ok: true, error: null, data: updated);
  }

  Future<ModerationResult> restore(String adminId, String reviewId) async {
    final updated = await _reviews.setModerationStatus(reviewId, 'visible');
    if (updated == null) return (ok: false, error: 'not_found', data: null);
    await _reviewsService.recomputeRatings(updated['providerId'] as String);
    await _audit.append((
      actorAdminId: adminId,
      action: 'review.restore',
      targetType: 'review',
      targetId: reviewId,
      reason: null,
      metadata: const {},
    ));
    return (ok: true, error: null, data: updated);
  }

  /// The review is fine — resolve its reports without hiding it.
  Future<ModerationResult> dismissReports(
    String adminId,
    String reviewId,
  ) async {
    if (await _reviews.reviewById(reviewId) == null) {
      return (ok: false, error: 'not_found', data: null);
    }
    await _reviews.resolveReports(reviewId, adminId);
    await _audit.append((
      actorAdminId: adminId,
      action: 'review.dismiss_reports',
      targetType: 'review',
      targetId: reviewId,
      reason: null,
      metadata: const {},
    ));
    return (ok: true, error: null, data: {'status': 'dismissed'});
  }
}
