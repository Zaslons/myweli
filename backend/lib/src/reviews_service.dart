import 'dart:math';

import 'appointments/appointment_repository.dart';
import 'auth/auth_repository.dart';
import 'providers_repository.dart';
import 'reviews_repository.dart';

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
  }) : _allowedImageOrigins = allowedImageOrigins;

  final ReviewsRepository _reviews;
  final AppointmentRepository _appointments;
  final ProvidersRepository _providers;
  final AuthRepository _auth;
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

    // The appointment is the authority on who/what/which-salon.
    final appt = await _appointments.byId(appointmentId);
    if (appt == null) return (ok: false, error: 'not_found', review: null);
    if (appt['userId'] != userId) {
      return (ok: false, error: 'forbidden', review: null);
    }
    if (appt['status'] != 'completed') {
      return (ok: false, error: 'not_completed', review: null);
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
    final userName = (await _auth.userById(userId))?.name ?? 'Client';

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
    await _recompute(providerId);
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

  /// Recompute the denormalized provider + per-artist ratings from reviews.
  Future<void> _recompute(String providerId) async {
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
