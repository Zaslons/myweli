import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/auth/auth_methods.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/email_change_service.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/email/account_email_emails.dart';
import 'package:myweli_backend/src/email/email_provider.dart';
import 'package:myweli_backend/src/email/send_budget.dart';
import 'package:myweli_backend/src/security/rate_limiter.dart';
import 'package:test/test.dart';

import '../../routes/me/email/otp/request.dart' as request_route;
import '../../routes/me/email/otp/verify.dart' as verify_route;
import '../contract/openapi_shape.dart';

class _Ctx extends Mock implements RequestContext {}

class _RecordingEmail implements EmailProvider {
  final List<({String to, String subject, EmailClass cls})> sent = [];
  String? answer; // an error to answer with, e.g. 'send_budget_exhausted'

  @override
  Future<EmailSendResult> send({
    required String to,
    required String subject,
    required String text,
    required EmailClass classification,
    String? html,
  }) async {
    sent.add((to: to, subject: subject, cls: classification));
    return answer == null
        ? (ok: true, providerMessageId: 'm1', error: null)
        : (ok: false, providerMessageId: null, error: answer);
  }
}

/// `POST /me/email/otp/request` and `/verify`, through the real routes over
/// the in-memory twin and the real [EmailChangeService]
/// (docs/design/account-email-change.md §3.1, §8.2). The rules themselves
/// are the contract's, on both twins (`account_email_contract.dart`).
void main() {
  final tokens = TokenService(secret: 'test-secret');
  late InMemoryAuthRepository auth;
  late _RecordingEmail mail;
  late EmailChangeService service;
  var methods = const AuthMethods(AuthMethods.defaults);
  var n = 0;
  String address(String who) => '$who.${n++}@routes.test';

  setUp(() {
    auth = InMemoryAuthRepository(tokens: tokens, echoDevCode: true);
    mail = _RecordingEmail();
    service = EmailChangeService(auth, mail, limiter: InMemoryRateLimiter());
    methods = const AuthMethods(AuthMethods.defaults);
  });

  String tok(String sub, {String role = 'user'}) =>
      tokens.issueAccessToken(subject: sub, role: role).token;

  Future<({int status, Map<String, dynamic> body})> call(
    Future<Response> Function(RequestContext) route,
    String path, {
    String? token,
    Object? body,
    String method = 'POST',
    String? rawBody,
  }) async {
    final c = _Ctx();
    when(() => c.request).thenReturn(
      Request(
        method,
        Uri.parse('http://localhost$path'),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'content-type': 'application/json',
        },
        body: rawBody ?? (body == null ? null : jsonEncode(body)),
      ),
    );
    when(() => c.read<TokenService>()).thenReturn(tokens);
    when(() => c.read<AuthMethods>()).thenReturn(methods);
    when(() => c.read<EmailChangeService>()).thenReturn(service);
    final res = await route(c);
    final text = await res.body();
    return (
      status: res.statusCode,
      body: text.isEmpty
          ? <String, dynamic>{}
          : (jsonDecode(text) as Map).cast<String, dynamic>(),
    );
  }

  Future<({int status, Map<String, dynamic> body})> request(
    String userId,
    Object? body, {
    String role = 'user',
  }) => call(
    request_route.onRequest,
    '/me/email/otp/request',
    token: tok(userId, role: role),
    body: body,
  );

  Future<({int status, Map<String, dynamic> body})> verify(
    String userId,
    Object? body,
  ) => call(
    verify_route.onRequest,
    '/me/email/otp/verify',
    token: tok(userId),
    body: body,
  );

  Future<AuthUser> google(String email) async => (await auth.loginWithSocial(
    provider: 'google',
    sub: 'g-${n++}',
    email: email,
    emailVerified: true,
  )).user!;

  Future<AuthUser> byCode(String email) async => (await auth.verifyEmailOtp(
    email,
    (await auth.requestEmailOtp(email)).devCode!,
  )).user!;

  group('POST /me/email/otp/request', () {
    test('202: a code to the new address, COLD; no second code for a '
        'Google account', () async {
      final a = await google(address('a'));
      final x = address('x');
      final res = await request(a.id, {'email': x});
      expect(res.status, HttpStatus.accepted);
      expect(res.body['expiresInSeconds'], 300);
      expect(res.body['currentCodeSent'], isFalse);
      expect(res.body['devCode'], isA<String>(), reason: 'dev echoes it');
      expect(res.body.containsKey('currentDevCode'), isFalse);
      expect(mail.sent.single.to, x);
      expect(mail.sent.single.cls, EmailClass.cold, reason: 'typed address');
    });

    test('202: an e-mail-code account also gets a code at its current '
        'address, WARM (decision 265)', () async {
      final current = address('cur');
      final a = await byCode(current);
      final x = address('x');
      final res = await request(a.id, {'email': x});
      expect(res.status, HttpStatus.accepted);
      expect(res.body['currentCodeSent'], isTrue);
      expect(res.body['currentDevCode'], isA<String>());
      expect(mail.sent.map((m) => m.to), [x, current]);
      expect(mail.sent.last.cls, EmailClass.warm, reason: 'its own address');
    });

    test('the same answer whether or not the address has an account '
        '(T32)', () async {
      final a = await google(address('a'));
      final taken = address('taken');
      await byCode(taken);
      final free = address('free');
      final r1 = await request(a.id, {'email': taken});
      final r2 = await request(a.id, {'email': free});
      expect(r1.status, r2.status);
      expect(
        r1.body.keys.toSet(),
        r2.body.keys.toSet(),
        reason: 'no field tells a taken address from a free one',
      );
      expect(r1.body['currentCodeSent'], r2.body['currentCodeSent']);
    });

    test('the same answer for an e-mail-code account too, the second code '
        'included (T32)', () async {
      final a = await byCode(address('cur'));
      final taken = address('taken');
      await byCode(taken);
      final r1 = await request(a.id, {'email': taken});
      final r2 = await request(a.id, {'email': address('free')});
      expect(r1.status, r2.status);
      expect(r1.body.keys.toSet(), r2.body.keys.toSet());
      expect(r1.body['currentCodeSent'], isTrue);
      expect(r2.body['currentCodeSent'], isTrue);
    });

    test('the current address\'s resend budget spent: still 202 — its live '
        'code still works (review)', () async {
      final current = address('cur');
      final a = await byCode(current);
      for (var i = 0; i < 4; i++) {
        expect((await request(a.id, {'email': address('x$i')})).status, 202);
      }
      mail.sent.clear();
      final res = await request(a.id, {'email': address('x4')});
      expect(res.status, HttpStatus.accepted, reason: 'not a 429 after a send');
      expect(res.body['currentCodeSent'], isTrue);
      expect(res.body.containsKey('currentDevCode'), isFalse);
      expect(
        mail.sent.map((m) => m.to),
        isNot(contains(current)),
        reason: 'no new code to the current address: its budget is spent',
      );
    });

    test('409 email_unchanged: its own proven address; its own unproven '
        'one is accepted (« Vérifier »)', () async {
      final own = address('own');
      final a = await google(own);
      final res = await request(a.id, {'email': ' ${own.toUpperCase()} '});
      expect(res.status, HttpStatus.conflict);
      expect(res.body['error'], 'email_unchanged');

      final x = address('x');
      auth.plantUnprovenEmailForTest(a.id, x);
      expect((await request(a.id, {'email': x})).status, HttpStatus.accepted);
    });

    test('400 invalid_body · 400 invalid_email', () async {
      final a = await google(address('a'));
      final bad = await call(
        request_route.onRequest,
        '/me/email/otp/request',
        token: tok(a.id),
        rawBody: 'not json',
      );
      expect(bad.status, HttpStatus.badRequest);
      expect(bad.body['error'], 'invalid_body');
      final res = await request(a.id, {'email': 'not-an-address'});
      expect(res.status, HttpStatus.badRequest);
      expect(res.body['error'], 'invalid_email');
      expect(mail.sent, isEmpty);
    });

    test('429 otp_resend_limit: the address\'s resend budget', () async {
      final a = await google(address('a'));
      final x = address('x');
      service = EmailChangeService(auth, mail); // no per-account limit
      for (var i = 0; i < 4; i++) {
        expect((await request(a.id, {'email': x})).status, 202);
      }
      final res = await request(a.id, {'email': x});
      expect(res.status, HttpStatus.tooManyRequests);
      expect(res.body['error'], 'otp_resend_limit');
    });

    test('429 rate_limited: per account, across both routes', () async {
      final a = await google(address('a'));
      service = EmailChangeService(
        auth,
        mail,
        limiter: InMemoryRateLimiter(),
        limit: 2,
        log: (_) {},
      );
      expect((await request(a.id, {'email': address('x')})).status, 202);
      expect(
        (await verify(a.id, {'email': address('y'), 'code': '123456'})).status,
        HttpStatus.badRequest,
        reason: 'the second hit, a wrong code',
      );
      final res = await request(a.id, {'email': address('z')});
      expect(res.status, HttpStatus.tooManyRequests);
      expect(res.body['error'], 'rate_limited');
      // Another account's bucket is its own.
      final b = await google(address('b'));
      expect((await request(b.id, {'email': address('w')})).status, 202);
    });

    test('a declined send gives its resend back', () async {
      final a = await google(address('a'));
      final x = address('x');
      service = EmailChangeService(auth, mail);
      mail.answer = 'send_budget_exhausted';
      for (var i = 0; i < 6; i++) {
        expect(
          (await request(a.id, {'email': x})).status,
          HttpStatus.accepted,
          reason: 'refunded each time, never a lockout',
        );
      }
    });

    test('403 account_suspended · 403 forbidden for a pro token · 401 '
        'without one · 404 auth_method_disabled · 405', () async {
      final a = await google(address('a'));
      await auth.setStatus(a.id, 'banned');
      final banned = await request(a.id, {'email': address('x')});
      expect(banned.status, HttpStatus.forbidden);
      expect(banned.body['error'], 'account_suspended');

      final pro = await request('pro_1', {
        'email': address('x'),
      }, role: 'provider');
      expect(pro.status, HttpStatus.forbidden);
      expect(pro.body['error'], 'forbidden');

      final none = await call(
        request_route.onRequest,
        '/me/email/otp/request',
        body: {'email': address('x')},
      );
      expect(none.status, HttpStatus.unauthorized);

      final b = await google(address('b'));
      methods = const AuthMethods({'google', 'apple'}, explicit: true);
      final off = await request(b.id, {'email': address('x')});
      expect(off.status, HttpStatus.notFound);
      expect(off.body['error'], 'auth_method_disabled');

      final get = await call(
        request_route.onRequest,
        '/me/email/otp/request',
        token: tok(b.id),
        method: 'GET',
      );
      expect(get.status, HttpStatus.methodNotAllowed);
      expect(mail.sent, isEmpty);
    });
  });

  group('POST /me/email/otp/verify', () {
    test('200 User: the address set, proven, emailVerified in the body; '
        'a notice to the PROVEN address it replaced', () async {
      final old = address('old');
      final a = await google(old);
      final x = address('x');
      final code = (await request(a.id, {'email': x})).body['devCode'];
      mail.sent.clear();

      final res = await verify(a.id, {'email': x, 'code': code});
      expect(res.status, HttpStatus.ok);
      expect(res.body['id'], a.id);
      expect(res.body['email'], x);
      expect(res.body['emailVerified'], isTrue);
      expect(mail.sent.single.to, old, reason: 'the notice, to the old one');
      expect(mail.sent.single.subject, accountEmailChangedSubject);
      expect(mail.sent.single.cls, EmailClass.warm);
    });

    test('no notice when the replaced address was never proven', () async {
      final a = await google(address('a'));
      auth.plantUnprovenEmailForTest(a.id, address('typed'));
      final x = address('x');
      final code = (await request(a.id, {'email': x})).body['devCode'];
      mail.sent.clear();
      expect((await verify(a.id, {'email': x, 'code': code})).status, 200);
      expect(mail.sent, isEmpty, reason: 'it may be a stranger\'s inbox');
    });

    test('decision 265: the current code is asked for, then taken', () async {
      final current = address('cur');
      final a = await byCode(current);
      final x = address('x');
      final sent = (await request(a.id, {'email': x})).body;
      final without = await verify(a.id, {'email': x, 'code': sent['devCode']});
      expect(without.status, HttpStatus.badRequest);
      expect(without.body['error'], 'current_otp_none');
      final ok = await verify(a.id, {
        'email': x,
        'code': sent['devCode'],
        'currentCode': sent['currentDevCode'],
      });
      expect(ok.status, HttpStatus.ok, reason: '${ok.body}');
      expect(ok.body['email'], x);
    });

    test('409 email_taken, only with the right code', () async {
      final a = await google(address('a'));
      final x = address('x');
      await byCode(x);
      final code = (await request(a.id, {'email': x})).body['devCode'];
      final res = await verify(a.id, {'email': x, 'code': code});
      expect(res.status, HttpStatus.conflict);
      expect(res.body['error'], 'email_taken');
    });

    test('400 invalid_input: not an address, not a code, a malformed '
        'currentCode', () async {
      final a = await google(address('a'));
      for (final body in [
        {'email': 'nope', 'code': '123456'},
        {'email': address('x'), 'code': '12'},
        {'email': address('x'), 'code': '123456', 'currentCode': 'abc'},
      ]) {
        final res = await verify(a.id, body);
        expect(res.status, HttpStatus.badRequest, reason: '$body');
        expect(res.body['error'], 'invalid_input');
      }
    });

    test('409 email_unchanged at the verify too', () async {
      final own = address('own');
      final a = await google(own);
      final res = await verify(a.id, {'email': own, 'code': '123456'});
      expect(res.status, HttpStatus.conflict);
      expect(res.body['error'], 'email_unchanged');
    });

    test('400 invalid_body · 400 current_otp_invalid', () async {
      final current = address('cur');
      final a = await byCode(current);
      final bad = await call(
        verify_route.onRequest,
        '/me/email/otp/verify',
        token: tok(a.id),
        rawBody: '[1,2]',
      );
      expect(bad.status, HttpStatus.badRequest);
      expect(bad.body['error'], 'invalid_body');
      final x = address('x');
      final sent = (await request(a.id, {'email': x})).body;
      final wrong = sent['currentDevCode'] == '111111' ? '222222' : '111111';
      final res = await verify(a.id, {
        'email': x,
        'code': sent['devCode'],
        'currentCode': wrong,
      });
      expect(res.status, HttpStatus.badRequest);
      expect(res.body['error'], 'current_otp_invalid');
    });

    test('429 rate_limited at the verify', () async {
      final a = await google(address('a'));
      service = EmailChangeService(
        auth,
        mail,
        limiter: InMemoryRateLimiter(),
        limit: 1,
        log: (_) {},
      );
      expect(
        (await verify(a.id, {'email': address('x'), 'code': '123456'})).status,
        HttpStatus.badRequest,
      );
      final res = await verify(a.id, {'email': address('x'), 'code': '123456'});
      expect(res.status, HttpStatus.tooManyRequests);
      expect(res.body['error'], 'rate_limited');
    });

    test('400 otp_*: the code refused', () async {
      final a = await google(address('a'));
      final x = address('x');
      final res = await verify(a.id, {'email': x, 'code': '123456'});
      expect(res.status, HttpStatus.badRequest);
      expect(res.body['error'], 'otp_none');
    });

    test("the account is the token's, whatever the body says", () async {
      final a = await google(address('a'));
      final b = await google(address('b'));
      final x = address('x');
      final code = (await request(a.id, {'email': x})).body['devCode'];
      final res = await verify(a.id, {
        'email': x,
        'code': code,
        'userId': b.id,
        'id': b.id,
      });
      expect(res.body['id'], a.id);
      expect((await auth.userById(b.id))!.email, isNot(x));
    });

    test('403 account_suspended · 403 for a pro token · 401 · 404 '
        'auth_method_disabled · 405', () async {
      final a = await google(address('a'));
      await auth.setStatus(a.id, 'banned');
      final banned = await verify(a.id, {
        'email': address('x'),
        'code': '123456',
      });
      expect(banned.status, HttpStatus.forbidden);
      expect(banned.body['error'], 'account_suspended');

      final pro = await call(
        verify_route.onRequest,
        '/me/email/otp/verify',
        token: tok('pro_1', role: 'provider'),
        body: {'email': address('x'), 'code': '123456'},
      );
      expect(pro.status, HttpStatus.forbidden);

      final none = await call(
        verify_route.onRequest,
        '/me/email/otp/verify',
        body: {'email': address('x'), 'code': '123456'},
      );
      expect(none.status, HttpStatus.unauthorized);

      methods = const AuthMethods({'google'}, explicit: true);
      final b = await google(address('b'));
      final off = await verify(b.id, {'email': address('x'), 'code': '1234'});
      expect(off.status, HttpStatus.notFound);
      expect(off.body['error'], 'auth_method_disabled');

      final put = await call(
        verify_route.onRequest,
        '/me/email/otp/verify',
        token: tok(b.id),
        method: 'PUT',
      );
      expect(put.status, HttpStatus.methodNotAllowed);
    });

    test('404 not_found: the account vanished under the token', () async {
      final res = await verify('user_gone', {
        'email': address('x'),
        'code': '123456',
      });
      expect(res.status, HttpStatus.notFound);
    });
  });

  group('the bodies match docs/api/openapi.yaml', () {
    final shape = OpenApiShape();

    test('202 of the request, with and without the second code; 200 User '
        'of the verify, emailVerified included', () async {
      final a = await google(address('a'));
      final x = address('x');
      final sent = await request(a.id, {'email': x});
      expect(
        shape.checkResponse('/me/email/otp/request', 'post', 202, sent.body),
        isEmpty,
      );
      final b = await byCode(address('cur'));
      final both = await request(b.id, {'email': address('y')});
      expect(both.body['currentCodeSent'], isTrue);
      expect(
        shape.checkResponse('/me/email/otp/request', 'post', 202, both.body),
        isEmpty,
      );
      final done = await verify(a.id, {
        'email': x,
        'code': sent.body['devCode'],
      });
      expect(
        shape.checkResponse('/me/email/otp/verify', 'post', 200, done.body),
        isEmpty,
      );
      expect(
        shape.responseSchema('/me/email/otp/verify', 'post', 200),
        isNotNull,
      );
    });

    test('every refusal the routes answer is a documented status', () {
      for (final (path, statuses) in [
        ('/me/email/otp/request', [400, 401, 403, 404, 409, 429]),
        ('/me/email/otp/verify', [400, 401, 403, 404, 409, 429]),
        ('/me', [409]),
      ]) {
        final method = path == '/me' ? 'patch' : 'post';
        final responses = shape.operation(path, method)['responses'] as Map;
        for (final status in statuses) {
          expect(
            responses.containsKey('$status'),
            isTrue,
            reason: '$method $path must document $status',
          );
        }
      }
    });
  });
}
