import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'apple_tokens.dart';

/// Does this Sign in with Apple key cover this client? Asked of Apple itself,
/// before the key is deployed (docs/design/apple-signin-keys.md §5, §9 step
/// 2) — Apple does not document whether a key is refused for a client of
/// another primary App ID, so it is measured.
///
/// The question is a token request with a deliberately invalid code. Apple
/// checks the client first: `invalid_client` means it refused our client
/// secret for that client — this key does not cover it; `invalid_grant` means
/// it accepted the secret and refused only the code — covered. **Anything
/// else is [AppleKeyCoverage.unknown], never a pass.** The probe's own
/// control is to run a key against the OTHER app's client too: if that also
/// answers `invalid_grant`, the oracle does not discriminate.
enum AppleKeyCoverage { covered, notCovered, unknown }

/// One probe's outcome: the client, the verdict, and what Apple answered —
/// the status and Apple's error word only, never a body, a code or a secret.
typedef AppleKeyProbe = ({
  String clientId,
  AppleKeyCoverage coverage,
  String answer,
});

const _appleTokenUrl = 'https://appleid.apple.com/auth/token';

/// A code Apple never issued: the request can only fail, and how it fails is
/// the answer.
const _probeCode = 'myweli-key-probe-not-a-real-code';

Future<AppleKeyProbe> probeAppleKey(
  AppleSignInKey key,
  String clientId, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final c = client ?? http.Client();
  try {
    final res = await c
        .post(
          Uri.parse(_appleTokenUrl),
          body: {
            'client_id': clientId,
            'client_secret': key.clientSecret(clientId),
            'code': _probeCode,
            'grant_type': 'authorization_code',
          },
        )
        .timeout(timeout);
    String? error;
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['error'] is String) {
        error = body['error'] as String;
      }
    } catch (_) {
      // Not JSON: no error word.
    }
    final answer = 'status=${res.statusCode} error=${error ?? '-'}';
    final coverage = switch ((res.statusCode, error)) {
      (400, 'invalid_grant') => AppleKeyCoverage.covered,
      (400, 'invalid_client') => AppleKeyCoverage.notCovered,
      _ => AppleKeyCoverage.unknown,
    };
    return (clientId: clientId, coverage: coverage, answer: answer);
  } catch (e) {
    return (
      clientId: clientId,
      coverage: AppleKeyCoverage.unknown,
      answer: 'no answer (${e.runtimeType})',
    );
  } finally {
    if (client == null) c.close();
  }
}

/// The line the tool prints for [p].
String describeAppleKeyProbe(AppleKeyProbe p) {
  final verdict = switch (p.coverage) {
    AppleKeyCoverage.covered => 'COVERED',
    AppleKeyCoverage.notCovered => 'NOT COVERED',
    AppleKeyCoverage.unknown => 'UNKNOWN',
  };
  return '${p.clientId}: $verdict (${p.answer})';
}
