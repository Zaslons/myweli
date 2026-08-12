import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/query_sanity.dart';
import 'package:test/test.dart';

class _MockRequestContext extends Mock implements RequestContext {}

/// Control characters in the query string are rejected at the boundary
/// (docs/BACKEND.md §3.4).
///
/// **Found in production, not in review.** `GET /providers?commune=%00`
/// returned 500 — a NUL byte cannot exist in Postgres `text`, so the driver
/// threw while encoding a parameterised query and the exception propagated as
/// an unhandled error. Reachable with no authentication, and every occurrence
/// now costs an error-reporting event, so a scanner spraying malformed
/// parameters would fill the dashboard that exists to be read.
void main() {
  group('hasControlCharacters', () {
    Uri u(String query) => Uri.parse('http://localhost/providers?$query');

    test('the NUL byte that caused the production 500', () {
      // %00 percent-DECODES to U+0000, which is why reading queryParameters
      // rather than the raw string is what catches it.
      expect(hasControlCharacters(u('commune=%00')), isTrue);
    });

    test('other C0 controls too — none is legitimate in a URL query', () {
      for (final encoded in ['%01', '%09', '%0A', '%0D', '%1F']) {
        expect(
          hasControlCharacters(u('commune=$encoded')),
          isTrue,
          reason: 'control %$encoded should be rejected',
        );
      }
    });

    test('a control character in the KEY is caught as well', () {
      expect(hasControlCharacters(u('comm%00une=cocody')), isTrue);
    });

    test('repeated parameters are all checked, not just the first', () {
      // `queryParameters` keeps only the last value per key; `queryParametersAll`
      // keeps them all, which is why the implementation uses it.
      expect(hasControlCharacters(u('c=cocody&c=%00')), isTrue);
      expect(hasControlCharacters(u('c=%00&c=cocody')), isTrue);
    });

    test('ordinary queries pass, including French and spaces', () {
      // The check must not become a reason legitimate searches fail.
      for (final q in [
        'commune=Cocody',
        'commune=Abobo%20Nord',
        'q=coiffure%20afro',
        'commune=Plateau&sort=rating&page=2',
        'q=Beaut%C3%A9%20Divine', // é
        r'q=%F0%9F%92%87', // an emoji
      ]) {
        expect(hasControlCharacters(u(q)), isFalse, reason: q);
      }
    });

    test('a URI with no query at all is fine', () {
      expect(
        hasControlCharacters(Uri.parse('http://localhost/health')),
        isFalse,
      );
    });
  });

  group('querySanityMiddleware', () {
    RequestContext ctx(String path) {
      final c = _MockRequestContext();
      when(
        () => c.request,
      ).thenReturn(Request.get(Uri.parse('http://localhost$path')));
      return c;
    }

    Future<Response> run(String path, {required Handler inner}) async =>
        inner.use(querySanityMiddleware())(ctx(path));

    test(
      'a control character → 400 invalid_input, and the handler never runs',
      () async {
        var handlerRan = false;
        final res = await run(
          '/providers?commune=%00',
          inner: (_) {
            handlerRan = true;
            return Response.json(body: {'ok': true});
          },
        );
        expect(res.statusCode, HttpStatus.badRequest);
        expect(jsonDecode(await res.body()), {'error': 'invalid_input'});
        expect(
          handlerRan,
          isFalse,
          reason: 'the point is that no handler sees the value at all',
        );
      },
    );

    test('a clean query passes through untouched', () async {
      final res = await run(
        '/providers?commune=Cocody&page=2',
        inner: (_) => Response.json(body: {'ok': true}),
      );
      expect(res.statusCode, HttpStatus.ok);
      expect(jsonDecode(await res.body()), {'ok': true});
    });

    test('no query string is not a rejection', () async {
      final res = await run(
        '/health',
        inner: (_) => Response.json(body: {'status': 'ok'}),
      );
      expect(res.statusCode, HttpStatus.ok);
    });
  });
}
