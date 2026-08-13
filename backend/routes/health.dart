import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:myweli_backend/src/dependencies.dart';

/// Liveness probe. `GET` → 200 with a small JSON payload; other verbs → 405.
///
/// ## Why it reports `env`
///
/// Once there are two deployments, every check written against this API has to
/// answer "which one am I talking to?" — and until now the only available answer
/// was the *spelling of the hostname*, which is precisely the thing a
/// transposition gets wrong. A service that states its own identity turns that
/// into a question about the target rather than about the string used to reach
/// it. Two callers depend on it:
///
///   · the deploy workflow, which asserts the freshly deployed revision reports
///     the environment it was asked to deploy — so "deployed the staging file
///     onto production" fails loudly instead of succeeding;
///   · the funnel smoke harness, which **writes**, and refuses to run against a
///     target that self-reports `prod` even if the URL looked fine.
///
/// It is not sensitive: `dev | staging | prod` is already inferable from the
/// hostname, and it discloses nothing an unauthenticated caller could act on.
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response.json(
      statusCode: HttpStatus.methodNotAllowed,
      body: {'error': 'method_not_allowed'},
    );
  }
  return Response.json(
    body: {
      'status': 'ok',
      'service': 'myweli-api',
      'env': env.name,
      'time': DateTime.now().toUtc().toIso8601String(),
    },
  );
}
