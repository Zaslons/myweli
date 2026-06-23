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
