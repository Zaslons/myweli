import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../routes/health.dart' as health;
import '../routes/index.dart' as index;

class _MockRequestContext extends Mock implements RequestContext {}

void main() {
  late RequestContext context;

  setUp(() => context = _MockRequestContext());

  test('GET /health returns 200 with status ok', () async {
    when(
      () => context.request,
    ).thenReturn(Request.get(Uri.parse('http://localhost/health')));

    final response = health.onRequest(context);

    expect(response.statusCode, HttpStatus.ok);
    final body = await response.json() as Map<String, dynamic>;
    expect(body['status'], 'ok');
    expect(body['service'], 'myweli-api');
    // **The field two other checks depend on**: the deploy workflow asserts the
    // freshly deployed revision reports the environment it was asked to deploy,
    // and the funnel smoke harness — which writes — refuses a target that
    // self-reports `prod`. Both degrade to no-ops if it silently disappears, so
    // its absence has to break something visible. `dev` here because the test
    // process has no `ENV` set, which is the same reason `boot_config.dart`
    // takes raw values as arguments: `Platform.environment` cannot be flipped.
    expect(body['env'], 'dev');
  });

  test('non-GET /health is rejected with 405', () async {
    when(
      () => context.request,
    ).thenReturn(Request.post(Uri.parse('http://localhost/health')));

    final response = health.onRequest(context);

    expect(response.statusCode, HttpStatus.methodNotAllowed);
  });

  test('GET / returns the API banner', () async {
    when(
      () => context.request,
    ).thenReturn(Request.get(Uri.parse('http://localhost/')));

    final response = index.onRequest(context);

    final body = await response.json() as Map<String, dynamic>;
    expect(body['name'], 'myweli-api');
  });
}
