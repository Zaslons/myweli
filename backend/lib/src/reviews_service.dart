import 'dart:math';

import 'appointments/appointment_repository.dart';
import 'auth/auth_repository.dart';
import 'privacy/anonymized_identity.dart';
import 'providers_repository.dart';
import 'reviews_repository.dart';
import 'security/identity_limits.dart';
import 'security/rate_limiter.dart';
import 'storage/storage_service.dart';
import 'upload_verification_service.dart';

/// Outcome of a review write; [review] is the stored DTO on success.
typedef ReviewResult = ({bool ok, String? error, Map<String, dynamic>? review});

/// A page of reviews.
typedef ReviewPage = ({
  List<Map<String, dynamic>> items,
  int total,
  int page,
  int pageSize,
});

/// Consumer reviews (design: docs/design/consumer-reviews.md). A review is **of
/// a completed appointment the caller owns** — the server derives provider,
/// artist, service, reviewer, and `verified` from that appointment, so the
/// client can only set rating/text/photos. Each submit recomputes the
/// provider's and the attributed artist's rating/reviewCount.
class ReviewsService {
  ReviewsService(
    this._reviews,
    this._appointments,
    this._providers,
    this._auth, {
    List<String> allowedImageOrigins = const [],
    UploadVerificationService? verifier,
    String? publicBaseUrl,
    RateLimiter? limiter,
    IdentityLimits limits = kDefaultIdentityLimits,
  }) : _allowedImageOrigins = allowedImageOrigins,
       _verifier = verifier,
       _publicBaseUrl = publicBaseUrl,
       _limiter = limiter,
       _limits = limits;

  /// Per-identity rate limit (T65). Null means no limit; the composition root
  /// always supplies one, and a source test proves it.
  final RateLimiter? _limiter;
  final IdentityLimits _limits;

  final ReviewsRepository _reviews;
  final AppointmentRepository _appointments;
  final ProvidersRepository _providers;
  final AuthRepository _auth;

  /// Claim-time size check (T61). Review photos carry URLs, not keys, so the
  /// key is derived from [_publicBaseUrl] — legal ONLY because the origin
  /// allowlist above has already rejected anything not under it.
  final UploadVerificationService? _verifier;
  final String? _publicBaseUrl;
  final List<String> _allowedImageOrigins;

  static const _maxText = 1000;
  static const _maxPhotos = 6;
  static const _maxUrlLength = 2048;
  final _rng = Random();

  Future<ReviewResult> submitForAppointment(
    String userId,
    String appointmentId, {
    required Object? rating,
    required Object? text,
    Object? photoUrls,
  }) async {
    // Validate client-supplied fields.
    if (rating is! num ||
        rating < 1 ||
        rating > 5 ||
        rating != rating.toInt()) {
      return (ok: false, error: 'invalid_input', review: null);
    }
    final body = (text as String?)?.trim() ?? '';
    if (body.length > _maxText) {
      return (ok: false, error: 'invalid_input', review: null);
    }
    final photos = <String>[];
    if (photoUrls != null) {
      if (photoUrls is! List || photoUrls.length > _maxPhotos) {
        return (ok: false, error: 'invalid_input', review: null);
      }
      for (final e in photoUrls) {
        if (e is! String) {
          return (ok: false, error: 'invalid_input', review: null);
        }
        final url = e.trim();
        if (url.isEmpty || url.length > _maxUrlLength) {
          return (ok: false, error: 'invalid_input', review: null);
        }
        if (_allowedImageOrigins.isNotEmpty &&
            !_allowedImageOrigins.any(url.startsWith)) {
          return (ok: false, error: 'invalid_input', review: null);
        }
        photos.add(url);
      }
    }

    // Everything above is pure validation of the client's own body — shape,
    // length, origin — and touches no server state. **Promotion does not
    // belong there, and used to.**
    //
    // **Counted here, before the reads.** This is the most expensive surface of
    // the three: submission is an UPSERT, so the one-row-per-appointment
    // constraint bounds review COUNT and not request count, and every call
    // re-runs `recomputeRatings` — two aggregates and a `providers` write on a
    // shared-core instance. Placed before the ownership check for the reason in
    // §4: an attacker chooses whether their attempt succeeds, so they cannot
    // choose whether it is counted.
    if (!await allowUnderLimit(
      _limiter,
      reviewBucket(userId),
      _limits.reviewSubmit,
    )) {
      return (ok: false, error: 'rate_limited', review: null);
    }

    // The appointment is the authority on who/what/which-salon.
    final appt = await _appointments.byId(appointmentId);
    if (appt == null) return (ok: false, error: 'not_found', review: null);
    if (appt['userId'] != userId) {
      return (ok: false, error: 'forbidden', review: null);
    }
    if (appt['status'] != 'completed') {
      return (ok: false, error: 'not_completed', review: null);
    }

    // **This block ran BEFORE the three checks above.** `byId` is not
    // ownership-scoped — the `userId` comparison is the only thing binding the
    // appointment to the caller — so naming any appointment id still reached
    // storage: HEAD, copy, and DELETE of the pending source. The request was
    // then refused, and the objects were left promoted: moved OUT of
    // `pending/`, the one prefix a lifecycle rule collects, referenced by no
    // review that exists. Every refused attempt orphaned up to six objects
    // nothing will ever reclaim, and nothing stops the loop
    // (docs/design/backend-upload-orphans.md §1 — this is that denial of
    // wallet, reachable without owning anything).
    //
    // Storage is now touched only once the caller is proven to own a completed
    // visit. Validation stays above; only the mutation moved.
    //
    // The second half is the claim-vs-save distinction the gallery and KYC
    // already learned: `verifyAndPromote` refuses anything not under
    // `pending/`, which is right for a claim and wrong for a wholesale replace
    // that re-sends urls the server itself issued. `alreadyStored` is THIS
    // appointment's stored photos — read after ownership, so the set can only
    // ever be the caller's own — matched by membership, never by shape.
    if (photos.isNotEmpty && _verifier != null && _publicBaseUrl != null) {
      final existing = await _reviews.reviewByAppointment(appointmentId);
      // Projected, not cast: `photoUrls` arrives as `jsonDecode` output or a
      // driver-decoded jsonb value — `List<dynamic>` either way, so a cast
      // passes in-memory and throws against Postgres.
      final stored = <String>{
        for (final u in (existing?['photoUrls'] as List? ?? const []))
          if (u is String) u,
      };
      final v = await _verifier.promoteNewUrls(
        photos,
        publicBaseUrl: _publicBaseUrl,
        alreadyStored: stored,
        bucket: StorageBucket.public,
      );
      if (!v.ok) return (ok: false, error: v.error, review: null);
      photos
        ..clear()
        ..addAll(v.urls);
    }
    final providerId = appt['providerId'] as String;
    final provider = await _providers.byId(providerId);
    if (provider == null) return (ok: false, error: 'not_found', review: null);

    final serviceName = _serviceName(
      provider,
      (appt['serviceIds'] as List?)?.cast<String>() ?? const [],
    );
    final artistId = appt['artistId'] as String?;
    final artistName = artistId == null
        ? null
        : _nameOf(provider['artists'], artistId);
    final userName =
        (await _auth.userById(userId))?.name ?? anonymousClientLabel;

    final review = {
      'id':
          'review_${DateTime.now().microsecondsSinceEpoch}_${_rng.nextInt(9999)}',
      'appointmentId': appointmentId,
      'providerId': providerId,
      'userId': userId,
      'userName': userName,
      'rating': rating.toInt(),
      'text': body,
      'verified': true,
      'artistId': artistId,
      'artistName': artistName,
      'serviceName': serviceName,
      'photoUrls': photos,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    await _reviews.upsertByAppointment(review);
    await recomputeRatings(providerId);
    return (ok: true, error: null, review: review);
  }

  Future<ReviewPage> list(
    String providerId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final p = page < 1 ? 1 : page;
    final size = pageSize.clamp(1, 50);
    final res = await _reviews.listForProvider(
      providerId,
      page: p,
      pageSize: size,
    );
    return (items: res.items, total: res.total, page: p, pageSize: size);
  }

  /// Recompute the denormalized provider + per-artist ratings from the
  /// **visible** reviews (the repo's aggregates exclude hidden). Public so
  /// moderation can re-run it after a hide/restore.
  Future<void> recomputeRatings(String providerId) async {
    final agg = await _reviews.aggregateProvider(providerId);
    final byArtist = await _reviews.aggregateByArtist(providerId);
    await _providers.updateRatings(
      providerId,
      rating: _round1(agg.rating),
      reviewCount: agg.count,
      artists: {
        for (final e in byArtist.entries)
          e.key: (rating: _round1(e.value.rating), count: e.value.count),
      },
    );
  }

  static double _round1(double v) => (v * 10).round() / 10;

  String _serviceName(Map<String, dynamic> provider, List<String> serviceIds) {
    final services = (provider['services'] as List?) ?? const [];
    final names = <String>[];
    for (final id in serviceIds) {
      final name = _nameOf(services, id);
      if (name != null) names.add(name);
    }
    return names.join(', ');
  }

  String? _nameOf(Object? list, String id) {
    for (final e in (list as List?) ?? const []) {
      final m = e as Map<String, dynamic>;
      if (m['id'] == id) return m['name'] as String?;
    }
    return null;
  }
}
