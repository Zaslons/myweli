import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every API service wired on the PROVIDER session must refresh on the
/// PROVIDER endpoint (docs/design/session-refresh.md).
///
/// DI only builds the real services when `USE_API_BACKEND` is on, which no
/// test sets — so this reads the wiring instead. On 2026-10-11 the Pro push
/// registration rode the provider session with the default consumer
/// `/auth/refresh`: the server refused the provider token, the client ended
/// the session, and every salon owner was signed out on a cold start after
/// the access token expired.
void main() {
  const providerPath = "refreshPath: '/auth/provider/refresh'";
  const providerStore = "SecureSessionStore(key: 'myweli_provider_session')";

  final calls = _apiCalls(
    _code(File('lib/core/di/dependency_injection.dart').readAsStringSync()),
  );

  test('a service on the provider session (sessionStore:) names the provider '
      'refresh path', () {
    final onProvider = calls.entries
        .where((c) => c.value.contains('sessionStore: $providerStore'))
        .toList();
    // notifications, push registration, image upload, logo upload
    expect(onProvider.length, greaterThanOrEqualTo(4));
    for (final c in onProvider) {
      expect(c.value, contains(providerPath), reason: c.key);
    }
  });

  test('a service on the consumer session never names the provider path', () {
    final onConsumer = calls.entries.where(
      (c) => c.value.contains('sessionStore: SecureSessionStore()'),
    );
    expect(onConsumer, isNotEmpty);
    for (final c in onConsumer) {
      expect(c.value, isNot(contains(providerPath)), reason: c.key);
    }
  });

  test('a service taking providerSessionStore: refreshes that session on the '
      'provider path inside itself', () {
    final classes = calls.entries
        .where((c) => c.value.contains('providerSessionStore:'))
        .map((c) => c.key.split('#').first)
        .toSet();
    expect(classes.length, greaterThanOrEqualTo(6));
    var refreshingOnProvider = 0;
    for (final name in classes) {
      final source = _code(
        File('lib/services/api/${_snake(name)}.dart').readAsStringSync(),
      );
      // ApiAuthService only persists the provider session; it refreshes the
      // consumer one. What must hold is per client: a RefreshingHttpClient
      // over the provider store names the provider path.
      for (final client in _calls(source, 'RefreshingHttpClient')) {
        if (!client.contains('store: _providerSessionStore')) continue;
        refreshingOnProvider++;
        expect(client, contains(providerPath), reason: name);
      }
    }
    expect(refreshingOnProvider, greaterThanOrEqualTo(6));
  });
}

/// The source with comments removed and whitespace collapsed, so a comment can
/// never satisfy (or fail) a pin, and formatting never matters.
String _code(String src) {
  final out = StringBuffer();
  String? quote;
  for (var i = 0; i < src.length; i++) {
    final c = src[i];
    if (quote != null) {
      out.write(c);
      if (c == '\\' && i + 1 < src.length) {
        out.write(src[++i]);
      } else if (c == quote) {
        quote = null;
      }
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
      out.write(c);
    } else if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        i++;
      }
      out.write('\n');
    } else {
      out.write(c);
    }
  }
  return out
      .toString()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll('( ', '(')
      .replaceAll(RegExp(r',? \)'), ')');
}

/// `ApiXxx(...)` constructor calls → their argument text, keyed
/// `ApiXxx#<n>`.
Map<String, String> _apiCalls(String code) {
  final out = <String, String>{};
  for (final m in RegExp(r'\b(Api[A-Za-z]+)\(').allMatches(code)) {
    out['${m.group(1)}#${out.length}'] = _args(code, m.end);
  }
  return out;
}

/// The argument text of every `name(...)` call in [code].
List<String> _calls(String code, String name) => [
  for (final m in RegExp('\\b$name\\(').allMatches(code)) _args(code, m.end),
];

/// The balanced argument text starting right after an opening parenthesis.
String _args(String code, int start) {
  var depth = 1;
  var i = start;
  while (i < code.length && depth > 0) {
    if (code[i] == '(') depth++;
    if (code[i] == ')') depth--;
    i++;
  }
  return code.substring(start, i - 1);
}

String _snake(String camel) => camel
    .replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}')
    .substring(1);
