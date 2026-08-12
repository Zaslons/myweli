import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/boot_config.dart';
import 'package:myweli_backend/src/observability/error_reporter.dart';
import 'package:myweli_backend/src/observability/request_middleware.dart';
import 'package:sentry/sentry.dart';
import 'package:test/test.dart';

class _MockRequestContext extends Mock implements RequestContext {}

/// Records what it was asked to report, without a network.
class _RecordingReporter implements ErrorReporter {
  final List<({Object error, String? requestId, String? method, String? path})>
  reported = [];

  @override
  Future<void> report(
    Object error,
    StackTrace stackTrace, {
    String? requestId,
    String? method,
    String? path,
  }) async {
    reported.add((
      error: error,
      requestId: requestId,
      method: method,
      path: path,
    ));
  }
}

void main() {
  /// What must never leave the process
  /// (docs/design/observability-error-reporting.md §4.2).
  ///
  /// **The highest-consequence code in this slice, and the least visible.** If
  /// it is wrong, credentials and PII go to a third party and *nothing in the
  /// system notices* — no test fails, no route breaks, no log line appears. So
  /// the event under test carries one of everything forbidden.
  group('scrubEvent', () {
    SentryEvent loadedEvent() => SentryEvent(
      request: SentryRequest(
        method: 'POST',
        url: 'https://api.myweli.com/auth/verify',
        queryString: 'secret=super-secret-cron-value',
        cookies: 'session=eyJhbGciOi; refresh=opaque-token',
        headers: {
          'Authorization': 'Bearer a-real-access-token',
          'X-Cron-Secret': 'the-production-cron-secret',
          'Content-Type': 'application/json',
        },
        data: {
          'phoneNumber': '+2250707010101',
          'code': '123456',
          'name': 'Awa Koné',
        },
      ),
      user: SentryUser(
        id: 'user-42',
        email: 'awa@example.ci',
        ipAddress: '196.200.1.1',
      ),
      breadcrumbs: [Breadcrumb(message: 'otp requested for +2250707010101')],
    );

    test('the request body never survives', () {
      // Bodies carry OTP codes, phone numbers and names on the auth routes.
      expect(scrubEvent(loadedEvent())!.request!.data, isNull);
    });

    test('headers are emptied, not filtered', () {
      // An allowlist of "safe" headers would need updating every time a new one
      // appears. Content-Type is harmless and still goes.
      expect(scrubEvent(loadedEvent())!.request!.headers, isEmpty);
    });

    test('cookies never survive — the web session is httpOnly on purpose', () {
      expect(scrubEvent(loadedEvent())!.request!.cookies, isNull);
    });

    test('the query string never survives', () {
      // `?secret=` was removed in #352; the class of mistake was not.
      expect(scrubEvent(loadedEvent())!.request!.queryString, isNull);
    });

    test('user, breadcrumbs and extra are cleared', () {
      // Nothing sets these today. They are cleared so the guarantee holds for
      // the code someone writes next year.
      final e = scrubEvent(loadedEvent())!;
      expect(e.user, isNull);
      expect(e.breadcrumbs, isNull);
      // ignore: deprecated_member_use
      expect(e.extra, isNull);
    });

    test('the URL and method DO survive — they are the diagnosis', () {
      final e = scrubEvent(loadedEvent())!;
      expect(e.request!.url, 'https://api.myweli.com/auth/verify');
      expect(e.request!.method, 'POST');
    });

    test('no forbidden value appears anywhere in the serialised event', () {
      // The field-by-field assertions above can each pass while a value leaks
      // through some field nobody thought to check. This asserts on the whole
      // payload, which is what actually goes over the wire.
      final json = jsonEncode(scrubEvent(loadedEvent())!.toJson());
      for (final forbidden in [
        'a-real-access-token',
        'the-production-cron-secret',
        'super-secret-cron-value',
        '+2250707010101',
        '123456',
        'Awa Koné',
        'awa@example.ci',
        '196.200.1.1',
        'eyJhbGciOi',
      ]) {
        expect(
          json.contains(forbidden),
          isFalse,
          reason: '"$forbidden" reached the serialised event',
        );
      }
    });

    test('an event with no request is passed through untouched', () {
      expect(scrubEvent(SentryEvent()), isNotNull);
    });
  });

  group('initErrorReporter', () {
    test('no DSN → the no-op, so dev and CI need no setup', () async {
      final r = await initErrorReporter(
        dsn: null,
        environment: Env.dev,
        release: null,
      );
      expect(r, isA<NoopErrorReporter>());
    });

    test('a blank DSN counts as unset', () async {
      for (final dsn in ['', '   ']) {
        expect(
          await initErrorReporter(
            dsn: dsn,
            environment: Env.prod,
            release: 'abc123',
          ),
          isA<NoopErrorReporter>(),
          reason: 'a platform injecting an empty value must not half-configure',
        );
      }
    });
  });

  group('observabilityMiddleware', () {
    setUpAll(() {
      registerFallbackValue((RequestContext _) => const RequestId('fallback'));
    });

    /// The repo's established shape for exercising a middleware
    /// (`web_m1_test.dart`), with `provide` stubbed to return the same context
    /// so the chain composes.
    RequestContext ctx(
      String path, {
      String? incomingId,
      String method = 'GET',
    }) {
      final c = _MockRequestContext();
      when(() => c.request).thenReturn(
        Request(
          method,
          Uri.parse('http://localhost$path'),
          headers: incomingId == null ? null : {kRequestIdHeader: incomingId},
        ),
      );
      when(() => c.provide<RequestId>(any())).thenReturn(c);
      return c;
    }

    Future<Response> run(
      Handler handler,
      RequestContext context, {
      required ErrorReporter Function() reporter,
    }) async => handler.use(observabilityMiddleware(reporter))(context);

    test(
      'a throwing handler returns the standard envelope, not a trace',
      () async {
        final res = await run(
          (_) => throw StateError('boom: secret-value-in-message'),
          ctx('/providers?page=2'),
          reporter: _RecordingReporter.new,
        );
        expect(res.statusCode, HttpStatus.internalServerError);
        final body = await res.body();
        expect(jsonDecode(body), {'error': 'internal_error'});
        // BACKEND.md §2 has required "never leak internals" from the start,
        // enforced by nothing until now.
        expect(body.contains('secret-value-in-message'), isFalse);
        expect(body.toLowerCase().contains('stateerror'), isFalse);
      },
    );

    test('the failure response still carries the request id', () async {
      // It is what a user can quote and an operator can grep for.
      final res = await run(
        (_) => throw Exception('x'),
        ctx('/providers'),
        reporter: _RecordingReporter.new,
      );
      expect(res.headers[kRequestIdHeader], isNotEmpty);
    });

    test('the error is reported with the id and the route', () async {
      final reporter = _RecordingReporter();
      await run(
        (_) => throw Exception('x'),
        ctx('/providers?page=2', method: 'POST'),
        reporter: () => reporter,
      );
      expect(reporter.reported, hasLength(1));
      final r = reporter.reported.single;
      expect(r.requestId, isNotEmpty);
      expect(r.method, 'POST');
      // The PATH only — a query string is where secrets end up by accident.
      expect(r.path, '/providers');
    });

    test(
      'the reporter is resolved PER ERROR, not when the chain is built',
      () async {
        // Regression test for a bug this slice shipped and then fixed. dart_frog
        // builds the middleware chain BEFORE the custom entrypoint runs
        // `initializeDatabase()`, so capturing the reporter instance froze the
        // no-op that existed at build time — a system that looked wired and
        // reported nothing.
        ErrorReporter current = const NoopErrorReporter();
        final handler = ((RequestContext _) => throw Exception(
          'x',
        )).use(observabilityMiddleware(() => current));

        // Swapped AFTER the chain was built — exactly what boot does.
        final real = _RecordingReporter();
        current = real;

        await handler(ctx('/x'));
        expect(
          real.reported,
          hasLength(1),
          reason: 'the chain must read the reporter that exists at error time',
        );
      },
    );

    test(
      'a successful response passes through, with the id attached',
      () async {
        final res = await run(
          (_) => Response.json(body: {'ok': true}),
          ctx('/health'),
          reporter: _RecordingReporter.new,
        );
        expect(res.statusCode, HttpStatus.ok);
        expect(jsonDecode(await res.body()), {'ok': true});
        expect(res.headers[kRequestIdHeader], isNotEmpty);
      },
    );

    test(
      'reuses the caller id — the load balancer already assigned one',
      () async {
        // Minting a second makes one request look like two across the two logs.
        final res = await run(
          (_) => Response.json(body: {'ok': true}),
          ctx('/health', incomingId: 'lb-generated-id-123'),
          reporter: _RecordingReporter.new,
        );
        expect(res.headers[kRequestIdHeader], 'lb-generated-id-123');
      },
    );

    test('a blank incoming id is treated as absent', () async {
      final res = await run(
        (_) => Response.json(body: {'ok': true}),
        ctx('/health', incomingId: '   '),
        reporter: _RecordingReporter.new,
      );
      expect(res.headers[kRequestIdHeader]?.trim(), isNotEmpty);
      expect(res.headers[kRequestIdHeader], isNot('   '));
    });
  });
}
