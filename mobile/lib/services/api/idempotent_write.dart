import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'refreshing_http_client.dart';

/// The header the four creating POSTs carry (docs/design/write-idempotency.md).
const kIdempotencyKeyHeader = 'Idempotency-Key';

/// How long « already running » (409 `request_in_progress`) is waited for
/// before asking again, and how many times.
const kInProgressWait = Duration(milliseconds: 800);
const kMaxInProgressWaits = 3;

/// The wait between « already running » and asking again — a seam for the
/// tests only, so they do not sleep.
@visibleForTesting
Future<void> Function(Duration) idempotencyWait = Future.delayed;

/// Nothing came back is `null`; a gateway answering instead of the server
/// (502/503/504) is the same fact. A 500 is the server's own answer.
bool _lost(http.Response? res) =>
    res == null ||
    res.statusCode == 502 ||
    res.statusCode == 503 ||
    res.statusCode == 504;

/// A created answer the screen can use: a JSON object with its `id`.
bool _complete(http.Response res) {
  try {
    final body = jsonDecode(res.body);
    return body is Map && body['id'] is String;
  } catch (_) {
    return false;
  }
}

String? _code(http.Response res) {
  try {
    final body = jsonDecode(res.body);
    return body is Map ? body['error'] as String? : null;
  } catch (_) {
    return null;
  }
}

/// A creating write under its [key] — one per submission, from a
/// `SubmissionKey` — that can be asked again without risk: the server replays
/// the write it did instead of doing it again (docs/design/write-idempotency.md
/// §4, owner Q2).
///
/// - A lost answer — or a 2xx without a usable body — is asked again ONCE, at
///   once, with the same key, without a word.
/// - « Already running » waits and asks again, [kMaxInProgressWaits] times.
/// - Still nothing: `null` — « nothing answered », said by the caller; the
///   screen's « Réessayer » sends the same key again, and that replays.
/// - A refusal is the answer, as it came.
///
/// No [key] → exactly one call, as before keys existed.
Future<http.Response?> sendIdempotent(
  RefreshingHttpClient authed,
  Future<http.Response> Function(String token, Map<String, String> keyHeader)
  run, {
  required String? key,
}) async {
  if (key == null) return authed.send((t) => run(t, const {}));
  final header = {kIdempotencyKeyHeader: key};
  var askedAgain = false;
  var waits = 0;
  while (true) {
    final res = await authed.send((t) => run(t, header));
    if (_lost(res)) {
      if (askedAgain) return null;
      askedAgain = true;
      continue;
    }
    final answer = res!;
    if (answer.statusCode >= 200 && answer.statusCode < 300) {
      if (_complete(answer)) return answer;
      if (askedAgain) return null;
      askedAgain = true;
      continue;
    }
    if (answer.statusCode == 409 && _code(answer) == 'request_in_progress') {
      if (waits >= kMaxInProgressWaits) return null;
      waits++;
      await idempotencyWait(kInProgressWait);
      continue;
    }
    return answer;
  }
}
