import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/observability/error_reporter.dart';
import 'package:myweli_backend/src/observability/request_middleware.dart';

/// Runs [route] behind [observabilityMiddleware] — the outermost edge every
/// real request crosses — so whatever the route THROWS is answered the way
/// production answers it. Not a test file itself (no `_test` suffix).
///
/// Route tests call `onRequest` directly, which is right for what a route
/// returns and blind to what it throws: a `body['x'] as String?` on
/// `{"x": 5}` threw past every such test while production answered 500.
/// A wrong JSON type is now a `BodyFieldTypeError`, which only the middleware
/// turns into `400 invalid_body` (docs/design/phone-leftovers.md §3) — so a
/// test of that answer has to go through it.
///
/// [context] must be a mocktail mock: its `provide` is stubbed to return
/// itself so the chain composes, as in `observability_test.dart`.
Future<Response> observed(
  Handler route,
  RequestContext context, {
  ErrorReporter Function()? reporter,
}) async {
  registerFallbackValue((RequestContext _) => const RequestId('fallback'));
  when(() => context.provide<RequestId>(any())).thenReturn(context);
  return route.use(
    observabilityMiddleware(reporter ?? () => const NoopErrorReporter()),
  )(context);
}
