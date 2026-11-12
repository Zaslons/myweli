import '../../models/api_response.dart';

/// An admin call's answer, typed — [ApiResponse] plus what an error body of
/// the salon-validation routes carries (B0.18 —
/// docs/design/salon-go-live-approval.md §4.3):
///
/// - [missing]: the go-live gate's keys of a 409 `incomplete` (`photos`,
///   `availability`, …, and `offer` for an offer that is no longer live) —
///   [ApiResponse] has no slot for them, and the sentence alone cannot tell
///   the bar which steps to name;
/// - [routeMissing]: the server has no such route — it predates B0.18 (§9.2:
///   the console goes live before the backend). A typed outcome, never the
///   generic « Une erreur est survenue. ».
class AdminResponse<T> extends ApiResponse<T> {
  AdminResponse._({
    required super.success,
    super.data,
    super.error,
    super.code,
    List<String> missing = const [],
  }) : missing = List.unmodifiable(missing);

  factory AdminResponse.ok(T data) =>
      AdminResponse._(success: true, data: data);

  factory AdminResponse.failure(
    String error, {
    String? code,
    List<String> missing = const [],
  }) => AdminResponse._(
    success: false,
    error: error,
    code: code,
    missing: missing,
  );

  /// The gate's keys of a 409 `incomplete`; empty otherwise.
  final List<String> missing;

  /// The route is absent — a server from before B0.18.
  bool get routeMissing => code == kRouteMissingCode;
}

/// The code an admin call answers when the server has no such route. Not a
/// server code: the server before B0.18 answers an unknown route with
/// dart_frog's plain-text 404 (`Route not found`), which carries no `error`.
const kRouteMissingCode = 'route_missing';
