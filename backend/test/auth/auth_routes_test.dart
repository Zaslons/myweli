import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:test/test.dart';

import '../../routes/auth/otp/request.dart' as otp_request;
import '../../routes/auth/otp/verify.dart' as otp_verify;
import '../../routes/auth/refresh.dart' as refresh_route;
import '../../routes/me/index.dart' as me_route;

class _MockRequestContext extends Mock implements RequestContext {}

const _phone = '+2250707010101';
Uri _u(String path) => Uri.parse('http://localhost$path');

void main() {
  late TokenService ts;
  late AuthRepository repo;

  setUp(() {
    ts = TokenService(secret: 'test-secret');
    repo = InMemoryAuthRepository(tokens: ts, isProd: false);
  });

  RequestContext ctx(Request request) {
    final context = _MockRequestContext();
    when(() => context.request).thenReturn(request);
    when(() => context.read<AuthRepository>()).thenReturn(repo);
    when(() => context.read<TokenService>()).thenReturn(ts);
    return context;
  }

  Request post(String path, Object body) =>
      Request.post(_u(path), body: jsonEncode(body));

  Future<Map<String, dynamic>> jsonOf(Response r) async =>
      await r.json() as Map<String, dynamic>;

  test('otp/request: 202 + devCode; bad phone → 400; non-POST → 405', () async {
    final ok = await otp_request.onRequest(
      ctx(post('/auth/otp/request', {'phoneNumber': _phone})),
    );
    expect(ok.statusCode, HttpStatus.accepted);
    expect((await jsonOf(ok))['devCode'], isNotNull);

    final bad = await otp_request.onRequest(
      ctx(post('/auth/otp/request', {'phoneNumber': '123'})),
    );
    expect(bad.statusCode, HttpStatus.badRequest);
    expect((await jsonOf(bad))['error'], 'invalid_phone');

    final wrongVerb = await otp_request.onRequest(
      ctx(Request.get(_u('/auth/otp/request'))),
    );
    expect(wrongVerb.statusCode, HttpStatus.methodNotAllowed);
  });

  test('otp/verify: correct code → 200 tokens + user', () async {
    final code = (await repo.requestOtp(_phone)).devCode!;
    final res = await otp_verify.onRequest(
      ctx(post('/auth/otp/verify', {'phoneNumber': _phone, 'code': code})),
    );
    expect(res.statusCode, HttpStatus.ok);
    final body = await jsonOf(res);
    expect((body['tokens'] as Map)['accessToken'], isNotEmpty);
    expect((body['user'] as Map)['phoneNumber'], _phone);
  });

  test('otp/verify: wrong code → 400 otp_invalid', () async {
    final code = (await repo.requestOtp(_phone)).devCode!;
    final wrong = code == '111111' ? '222222' : '111111';
    final res = await otp_verify.onRequest(
      ctx(post('/auth/otp/verify', {'phoneNumber': _phone, 'code': wrong})),
    );
    expect(res.statusCode, HttpStatus.badRequest);
    expect((await jsonOf(res))['error'], 'otp_invalid');
  });

  test('refresh: replaying a rotated token → 401 refresh_reused', () async {
    final first = (await repo.verifyOtp(
      _phone,
      (await repo.requestOtp(_phone)).devCode!,
    )).tokens!;

    final rotated = await refresh_route.onRequest(
      ctx(post('/auth/refresh', {'refreshToken': first.refreshToken})),
    );
    expect(rotated.statusCode, HttpStatus.ok);

    final reuse = await refresh_route.onRequest(
      ctx(post('/auth/refresh', {'refreshToken': first.refreshToken})),
    );
    expect(reuse.statusCode, HttpStatus.unauthorized);
    expect((await jsonOf(reuse))['error'], 'refresh_reused');
  });

  test('/me without a bearer token → 401', () async {
    final res = await me_route.onRequest(
      ctx(Request('PATCH', _u('/me'), body: jsonEncode({'name': 'x'}))),
    );
    expect(res.statusCode, HttpStatus.unauthorized);
  });

  test('/me PATCH updates the caller, DELETE removes them', () async {
    final session = await repo.verifyOtp(
      _phone,
      (await repo.requestOtp(_phone)).devCode!,
    );
    final access = session.tokens!.accessToken;
    final headers = {'Authorization': 'Bearer $access'};

    final patched = await me_route.onRequest(
      ctx(
        Request(
          'PATCH',
          _u('/me'),
          headers: headers,
          body: jsonEncode({'name': 'Awa'}),
        ),
      ),
    );
    expect(patched.statusCode, HttpStatus.ok);
    expect((await jsonOf(patched))['name'], 'Awa');

    final deleted = await me_route.onRequest(
      ctx(Request('DELETE', _u('/me'), headers: headers)),
    );
    expect(deleted.statusCode, HttpStatus.noContent);
    expect(await repo.userById(session.user!.id), isNull);
  });

  test(
    'a token only ever mutates its own account (ownership by sub)',
    () async {
      final a = await repo.verifyOtp(
        '+2250700000001',
        (await repo.requestOtp('+2250700000001')).devCode!,
      );
      final b = await repo.verifyOtp(
        '+2250700000002',
        (await repo.requestOtp('+2250700000002')).devCode!,
      );

      // A's token patches /me → only A changes; B is untouched.
      await me_route.onRequest(
        ctx(
          Request(
            'PATCH',
            _u('/me'),
            headers: {'Authorization': 'Bearer ${a.tokens!.accessToken}'},
            body: jsonEncode({'name': 'A-only'}),
          ),
        ),
      );

      expect((await repo.userById(a.user!.id))!.name, 'A-only');
      expect((await repo.userById(b.user!.id))!.name, isNull);
    },
  );
}
