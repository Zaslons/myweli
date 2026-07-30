import '../../models/api_response.dart';
import '../../models/locality.dart';

/// The locality reference tree (multi-pays MP2 —
/// docs/design/multi-pays-end-version.md §2): countries → operator catalog +
/// cities → areas. Read-only, seeded server-side; fetched once and cached by
/// `LocalityProvider`.
abstract class LocalityServiceInterface {
  Future<ApiResponse<List<LocalityCountry>>> getLocalities();
}
