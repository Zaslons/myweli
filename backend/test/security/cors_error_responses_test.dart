import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/cors.dart';
import 'package:myweli_backend/src/observability/error_reporter.dart';
import 'package:myweli_backend/src/observability/request_middleware.dart';
import 'package:myweli_backend/src/query_sanity.dart';
import 'package:test/test.dart';

class _MockRequestContext extends Mock implements RequestContext {}

/// **An error answered outside CORS reaches the browser as an opaque network
/// failure.** The root chain put `observabilityMiddleware` OUTSIDE
/// `corsMiddleware`: when a handler threw, CORS never got to decorate a
/// response, and observability's 500 went out bare — the admin console (the
/// one browser client that calls the API directly) saw "network error", not
/// `internal_error`. Same for `querySanityMiddleware`'s 400, which sat outside
/// CORS too. The comment above the chain gave this very reason for the order
/// it did not implement. Design: docs/design/backend-cors-error-responses.md.
void main() {
  const allowed = 'https://admin.myweli.com';
  const hostile = 'https://evil.example';

  RequestContext ctx(String uri, {String? origin, String method = 'GET'}) {
    final c = _MockRequestContext();
    final request = Request(
      method,
      Uri.parse('http://localhost$uri'),
      headers: {if (origin != null) 'Origin': origin},
    );
    when(() => c.request).thenReturn(request);
    // observabilityMiddleware provides a RequestId into the context — stubbed
    // to the same context so the chain composes (observability_test.dart's
    // shape). Without the RIGHT type here every request dies in the harness
    // with a TypeError and a « 500 » proves nothing.
    when(() => c.provide<RequestId>(any())).thenReturn(c);
    return c;
  }

  setUpAll(() {
    registerFallbackValue((RequestContext _) => const RequestId('fallback'));
  });

  /// The root chain's edge, in the order routes/_middleware.dart declares
  /// (the source-order test below pins that this IS that order): the LAST
  /// `.use` is outermost.
  final reported = <Object>[];
  Handler edge(Handler inner) => inner
      .use(querySanityMiddleware())
      .use(observabilityMiddleware(() => _Recording(reported)))
      .use(corsMiddleware(() => const [allowed]));

  setUp(reported.clear);

  Future<Response> boom(RequestContext _) async =>
      throw StateError('a handler bug');

  group('an error answered by the edge carries the CORS headers', () {
    test('a thrown handler → 500 internal_error, readable by the allowed '
        'origin', () async {
      final res = await edge(boom)(ctx('/providers', origin: allowed));
      expect(res.statusCode, HttpStatus.internalServerError);
      expect(await res.body(), contains('internal_error'));
      // OUR error reached the edge — not a harness fault posing as one.
      expect(reported.single, isA<StateError>());
      expect(res.headers['Access-Control-Allow-Origin'], allowed);
      expect(res.headers['Access-Control-Allow-Credentials'], 'true');
    });

    test("query sanity's 400 → readable by the allowed origin", () async {
      final res = await edge((_) async => Response(body: 'never'))(
        ctx('/providers?q=%00', origin: allowed),
      );
      expect(res.statusCode, HttpStatus.badRequest);
      expect(res.headers['Access-Control-Allow-Origin'], allowed);
    });

    test('the request id is exposed — the id a user quotes is readable in '
        'the browser', () async {
      final res = await edge(boom)(ctx('/providers', origin: allowed));
      expect(res.headers['X-Request-Id'], isNotEmpty);
      expect(
        res.headers['Access-Control-Expose-Headers'],
        contains('X-Request-Id'),
      );
    });

    test(
      'a disallowed origin still gets NO CORS headers, error or not',
      () async {
        final res = await edge(boom)(ctx('/providers', origin: hostile));
        expect(res.statusCode, HttpStatus.internalServerError);
        expect(res.headers.containsKey('Access-Control-Allow-Origin'), isFalse);
        expect(
          res.headers.containsKey('Access-Control-Expose-Headers'),
          isFalse,
        );
      },
    );
  });

  /// The review of this change: CORS reads `request.method` to spot a
  /// preflight, and dart_frog's getter THROWS for a verb outside its enum
  /// (PROPFIND, TRACE, a made-up one). Outermost, nothing catches it: shelf's
  /// last-resort handler answers a bare text/plain 500 and logs the method,
  /// the path AND the query string with a stack trace — no request id, no
  /// envelope, no report. Inside observability it was a JSON 500.
  group('an unsupported verb does not escape the chain', () {
    for (final verb in ['PROPFIND', 'TRACE']) {
      test('$verb passes inward — never a throw out of CORS', () async {
        final res = await edge((_) async => Response(body: 'ok'))(
          ctx('/providers?token=secret', origin: allowed, method: verb),
        );
        expect(res.statusCode, isNot(HttpStatus.internalServerError));
        expect(res.headers['X-Request-Id'], isNotEmpty);
        expect(res.headers['Access-Control-Allow-Origin'], allowed);
      });
    }
  });

  group('routes/_middleware.dart — the order this test assumes', () {
    final src = File('routes/_middleware.dart')
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    final cors = src.indexOf('.use(corsMiddleware(');
    final obs = src.indexOf('.use(observabilityMiddleware(');
    final sanity = src.indexOf('.use(querySanityMiddleware(');
    final door = src.indexOf('.use(originFrontDoorMiddleware(');

    test('CORS is OUTERMOST — the last `.use` in the chain', () {
      expect(cors, isNonNegative);
      expect(
        src.lastIndexOf('.use('),
        cors,
        reason:
            'dart_frog: the LAST .use wraps everything. Anything outside '
            'CORS answers the browser without CORS headers — an opaque '
            'network error instead of the error',
      );
    });

    test('observability and query sanity are INSIDE it', () {
      expect(obs, allOf(isNonNegative, lessThan(cors)));
      expect(sanity, allOf(isNonNegative, lessThan(obs)));
    });

    test('the front door stays inside CORS and observability', () {
      expect(door, allOf(isNonNegative, lessThan(sanity)));
    });
  });
}

/// Records what reaches the reporter, so a 500 is proven to be the handler's.
class _Recording implements ErrorReporter {
  _Recording(this.errors);
  final List<Object> errors;

  @override
  Future<void> report(
    Object error,
    StackTrace stackTrace, {
    String? requestId,
    String? method,
    String? path,
  }) async => errors.add(error);
}
