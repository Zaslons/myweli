import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dart_frog/dart_frog.dart';

import '../responses.dart';
import 'idempotency_store.dart';

/// `8–128` of `[A-Za-z0-9_-]`: a UUID fits, a header full of junk does not.
/// The contract's `IdempotencyKey` pattern is this string, character for
/// character (test/contract/idempotency_key_contract_test.dart).
const String kIdempotencyKeyPattern = r'^[A-Za-z0-9_-]{8,128}$';
final RegExp _validKey = RegExp(kIdempotencyKeyPattern);

/// The fingerprint of a request body: the same key with ANOTHER body is a
/// client bug (`422 idempotency_key_reused`), never a retry to replay.
String fingerprintOf(String body) =>
    sha256.convert(utf8.encode(body)).toString();

/// Runs a creating POST at most once per `Idempotency-Key`
/// (docs/design/write-idempotency.md §3).
///
/// - **No key** → [run], exactly as before keys existed; the store is not
///   even read.
/// - A malformed key → `400 invalid_idempotency_key`, nothing run.
/// - The key's write succeeded before → its answer, replayed (same status,
///   same body), with `Idempotent-Replayed: true`. Nothing runs again: no
///   second booking, no second salon notification, no second e-mail.
/// - The same request still running → `409 request_in_progress`.
/// - The key used for another body → `422 idempotency_key_reused`.
/// - Otherwise [run]: a 2xx is kept with the key; anything else — a refusal,
///   or a throw — frees it, so a new try starts afresh.
///
/// Scoped to [accountId] (the session's `sub`) and the exact route with its
/// ids and query: another account's same key is its own write.
///
/// **Fails open**, like the rate limiter: a store error is one log line and
/// the write runs unprotected — every one of the four writes needs the same
/// database a few lines later anyway, so refusing would only add an outage.
Future<Response> idempotent(
  RequestContext context, {
  required String accountId,
  required Future<Response> Function() run,
  void Function(String) log = print,
}) async {
  final key = context.request.headers['idempotency-key'];
  if (key == null) return run();
  if (!_validKey.hasMatch(key)) {
    return jsonError(HttpStatus.badRequest, 'invalid_idempotency_key');
  }

  final uri = context.request.uri;
  final route = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
  final store = context.read<IdempotencyStore>();
  final fingerprint = fingerprintOf(await context.request.body());

  final IdempotencyClaim claim;
  try {
    claim = await store.claim(
      accountId: accountId,
      route: route,
      key: key,
      fingerprint: fingerprint,
    );
  } catch (e) {
    log('idempotency_unavailable step=claim type=${e.runtimeType}');
    return run();
  }

  switch (claim) {
    case ClaimReplay(:final status, :final body):
      return Response(
        statusCode: status,
        body: body,
        headers: {
          HttpHeaders.contentTypeHeader: ContentType.json.toString(),
          'idempotent-replayed': 'true',
        },
      );
    case ClaimInProgress():
      return jsonError(HttpStatus.conflict, 'request_in_progress');
    case ClaimMismatch():
      return jsonError(
        HttpStatus.unprocessableEntity,
        'idempotency_key_reused',
      );
    case ClaimReserved():
      break;
  }

  Future<void> release() async {
    try {
      await store.release(accountId: accountId, route: route, key: key);
    } catch (e) {
      // The claim stays « in progress » until it counts as abandoned
      // (kIdempotencyAbandonedAfter): a retry meanwhile hears 409.
      log('idempotency_unavailable step=release type=${e.runtimeType}');
    }
  }

  final Response response;
  try {
    response = await run();
  } catch (_) {
    await release();
    rethrow;
  }

  final ok = response.statusCode >= 200 && response.statusCode < 300;
  if (!ok) {
    await release();
    return response;
  }
  // Read once to keep it, then handed on as a FRESH body: the original's
  // stream is spent, and the server would otherwise write nothing.
  final body = await response.body();
  try {
    await store.complete(
      accountId: accountId,
      route: route,
      key: key,
      status: response.statusCode,
      body: body,
    );
  } catch (e) {
    // The write is done and its answer goes out. The claim stays « in
    // progress », so a retry of a LOST answer hears 409 until it counts as
    // abandoned — never a second write: releasing here would allow one.
    log('idempotency_unavailable step=complete type=${e.runtimeType}');
  }
  return response.copyWith(body: body);
}
