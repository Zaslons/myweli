import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

import 'responses.dart';

/// Rejects control characters in the query string, at the boundary
/// (docs/BACKEND.md §3.4).
///
/// ## The bug this closes
///
/// `GET /providers?commune=%00` returned **500**. Not injection — `commune`
/// goes into a parameterised query — but a **NUL byte cannot exist in Postgres
/// `text`**, so the driver throws while encoding the parameter and the
/// exception propagates as an unhandled error.
///
/// Three reasons that matters more than a stray 500:
///
/// 1. It is reachable by **anyone**, with no authentication.
/// 2. It **burns error-reporting quota**. Every occurrence is now a Sentry
///    event, so a scanner spraying malformed parameters fills the dashboard —
///    and a noisy dashboard stops being read, which defeats the observability
///    it is abusing.
/// 3. §3.4 requires validation at the boundary for every input; this one had
///    none, and the failure surfaced as a server fault rather than a 400.
///
/// ## Why a middleware rather than per-route validation
///
/// The hole is not in `/providers`. It is in **every route that passes a string
/// from the query to Postgres**, which is most of them, and the next one written
/// would have it too. One check at the edge closes the class; per-route checks
/// close instances and then rot.
///
/// ## What it rejects, and what it deliberately does not
///
/// C0 control characters (U+0000–U+001F) in any query **value** or **key**.
/// None is ever legitimate in a URL query: they cannot be typed, carry no
/// meaning to any parameter this API defines, and NUL specifically cannot be
/// stored at all.
///
/// **Bodies are not covered.** A JSON body may legally encode `\\u0000` in a
/// string, and reaching it would mean consuming the request body in middleware
/// and re-providing it, which dart_frog does not make safe. Narrower gap, its
/// own fix, recorded rather than implied — see the design note in
/// docs/BACKEND.md §3.4.
Middleware querySanityMiddleware() {
  return (handler) {
    return (context) async {
      if (hasControlCharacters(context.request.uri)) {
        return jsonError(HttpStatus.badRequest, 'invalid_input');
      }
      return handler(context);
    };
  };
}

/// True when any query key or value contains a C0 control character.
///
/// Takes a [Uri] rather than a request so it is testable without a context —
/// the same reason `boot_config.dart`'s resolvers take raw values.
///
/// Reads `queryParameters`, which is percent-DECODED, so `%00` is seen as the
/// NUL it becomes rather than as the three literal characters it arrives as.
bool hasControlCharacters(Uri uri) {
  if (!uri.hasQuery) return false;
  for (final entry in uri.queryParametersAll.entries) {
    if (_hasControl(entry.key)) return true;
    for (final value in entry.value) {
      if (_hasControl(value)) return true;
    }
  }
  return false;
}

bool _hasControl(String s) {
  for (final rune in s.runes) {
    if (rune <= 0x1F) return true;
  }
  return false;
}
