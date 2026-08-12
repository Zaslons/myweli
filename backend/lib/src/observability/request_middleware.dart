import 'dart:async';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:uuid/uuid.dart';

import '../responses.dart';
import 'error_reporter.dart';

/// The request id carried on the wire, in and out.
const kRequestIdHeader = 'X-Request-Id';

const _uuid = Uuid();

/// Gives every request an id, in the context and echoed on the response
/// (docs/BACKEND.md §3.6).
///
/// **This is documented behaviour that did not exist.** BACKEND.md has named a
/// request-id in three places since it was written — §1's middleware list, §2's
/// "log with a request-id, return a generic 500", and §3.6's "structured logs
/// with a request-id" — while `routes/_middleware.dart` was a chain of DI
/// providers and nothing else.
///
/// Reuses the caller's id when there is one, because the load balancer already
/// assigns one and inventing a second makes a single request look like two
/// across the two logs.
/// Gives every request an id and catches whatever a handler throws
/// (docs/BACKEND.md §1, §2, §3.6).
///
/// **This is documented behaviour that did not exist.** BACKEND.md has named a
/// request-id in three places since it was written — §1's middleware list, §2's
/// "log with a request-id, return a generic 500", and §3.6's "structured logs
/// with a request-id" — while `routes/_middleware.dart` was a chain of DI
/// providers and nothing else. An unhandled throw became whatever the framework
/// does by default: no id, no structured log, nothing reported, and no
/// guarantee about what reached the client.
///
/// **One middleware rather than two**, deliberately. Split, the error handler
/// had to read the id back out of the request context, which meant a
/// `try`/`catch` around a diagnostic lookup inside the handler for the error it
/// was diagnosing — and an ordering rule ("request-id must be outermost") that
/// nothing enforced. Here the id is a local: in scope for the success path, the
/// failure path, and the response header of both.
///
/// The id is reused from the caller when present, because the load balancer
/// already assigns one and minting a second makes a single request look like
/// two across the two logs.
///
/// **[reporter] is a callback, not an instance, and that is load-bearing.**
/// dart_frog builds the whole middleware chain *before* the custom entrypoint
/// runs: the generated `server.dart` calls `buildRootHandler()` on one line and
/// `entrypoint.run(...)` — which is where `initializeDatabase()` configures the
/// reporter — on the next. Capturing the instance would freeze the no-op that
/// exists at build time, and every error afterwards would be silently
/// unreported: wired, green, and blind.
Middleware observabilityMiddleware(ErrorReporter Function() reporter) {
  return (handler) {
    return (context) async {
      final incoming = context.request.headers[kRequestIdHeader]?.trim();
      final id = (incoming == null || incoming.isEmpty) ? _uuid.v4() : incoming;
      try {
        final response = await handler
            .use(provider<RequestId>((_) => RequestId(id)))
            .call(context);
        return response.copyWith(
          headers: {...response.headers, kRequestIdHeader: id},
        );
      } catch (error, stackTrace) {
        final method = context.request.method.value;
        // The PATH only — `context.request.uri` carries the query string, and
        // query strings are where secrets end up by accident.
        final path = context.request.uri.path;

        // ignore: avoid_print — structured, and the container log is where an
        // operator actually looks. Deliberately does NOT include the error's
        // toString(): a thrown Postgres exception can carry row values.
        print(
          'ERROR: unhandled_route_error '
          'request_id=$id method=$method path=$path '
          'type=${error.runtimeType}',
        );

        // Fire and forget: a slow or failing reporter must not become the
        // request's latency or its failure mode.
        unawaited(
          reporter().report(
            error,
            stackTrace,
            requestId: id,
            method: method,
            path: path,
          ),
        );

        // The error response carries the id too — it is what a user can quote
        // and an operator can grep for.
        return jsonError(
          HttpStatus.internalServerError,
          'internal_error',
        ).copyWith(headers: {kRequestIdHeader: id});
      }
    };
  };
}

/// The current request's id, provided into context by
/// [observabilityMiddleware].
///
/// A wrapper type rather than a bare `String` so `context.read` cannot collide
/// with any other string the chain provides.
class RequestId {
  const RequestId(this.value);
  final String value;
}
