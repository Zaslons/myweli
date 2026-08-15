import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli_backend/src/access/membership_repository.dart';
import 'package:myweli_backend/src/access/membership_service.dart';
import 'package:myweli_backend/src/appointments/appointment_repository.dart';
import 'package:myweli_backend/src/auth/auth_repository.dart';
import 'package:myweli_backend/src/auth/provider_auth_repository.dart';
import 'package:myweli_backend/src/auth/tokens.dart';
import 'package:myweli_backend/src/deposit_service.dart';
import 'package:myweli_backend/src/kyc_service.dart';
import 'package:myweli_backend/src/providers_repository.dart';
import 'package:myweli_backend/src/responses.dart';
import 'package:myweli_backend/src/reviews_repository.dart';
import 'package:myweli_backend/src/reviews_service.dart';
import 'package:myweli_backend/src/storage/storage_service.dart';
import 'package:myweli_backend/src/upload_verification_service.dart';
import 'package:test/test.dart';

import '../routes/appointments/[id]/deposit.dart' as deposit_route;
import '../routes/appointments/[id]/review.dart' as review_route;
import '../routes/me/kyc.dart' as kyc_route;

/// **"Storage blinked" and "your file is wrong" were the same answer.**
///
/// `UploadVerificationService` fails CLOSED on an unreachable bucket — right —
/// but the refusal then travelled as a **400** beside `invalid_input` and
/// `upload_too_large`. A client cannot tell "fix it and resend" from "send
/// exactly that again", and only one of the two is worth retrying.
///
/// The reason this file exists rather than one assertion per route suite:
/// **`resultResponse` is not the choke point it looks like.** Three of the
/// surfaces carry their own `switch`, so a code added to `responses.dart`
/// alone reaches two of five and every existing test still passes. The last
/// section is a source-level pin against exactly that.
void main() {
  final tokens = TokenService(secret: 'test-secret');

  group('the mapping itself', () {
    test('503, the standard envelope, and Retry-After', () async {
      final r = storageUnavailable();
      expect(r.statusCode, HttpStatus.serviceUnavailable);
      expect((await r.json() as Map)['error'], 'storage_unavailable');
      expect(
        r.headers['retry-after'],
        '5',
        reason:
            '503 invites a retry, and each one costs a HEAD against a '
            'bucket that is already failing — say when',
      );
    });

    test('resultResponse routes it, and still 400s everything else', () {
      Response map(String e) => resultResponse(ok: false, error: e, body: null);
      expect(
        map('storage_unavailable').statusCode,
        HttpStatus.serviceUnavailable,
      );
      // The neighbours it used to be indistinguishable from stay 400 — they
      // ARE the caller's problem.
      expect(map('invalid_input').statusCode, HttpStatus.badRequest);
      expect(map('upload_too_large').statusCode, HttpStatus.badRequest);
      expect(map('upload_not_found').statusCode, HttpStatus.badRequest);
      // And the pre-existing arms are untouched.
      expect(map('not_found').statusCode, HttpStatus.notFound);
      expect(map('forbidden').statusCode, HttpStatus.forbidden);
      expect(map('invalid_state').statusCode, HttpStatus.conflict);
    });
  });

  group('every surface that can emit it', () {
    late InMemoryAppointmentRepository appts;
    late InMemoryProviderAuthRepository providerAuth;

    /// A bucket that cannot be reached — the whole point of the code.
    UploadVerificationService verifier() =>
        UploadVerificationService(storage: _UnreachableStorage());

    setUp(() async {
      appts = InMemoryAppointmentRepository();
      providerAuth = InMemoryProviderAuthRepository(
        tokens: tokens,
        isProd: false,
      );
    });

    RequestContext ctx(Request request, void Function(RequestContext) wire) {
      final c = _MockRequestContext();
      when(() => c.request).thenReturn(request);
      when(() => c.read<TokenService>()).thenReturn(tokens);
      wire(c);
      return c;
    }

    Future<void> expect503(Response res, String surface) async {
      expect(
        res.statusCode,
        HttpStatus.serviceUnavailable,
        reason: '$surface still answers "your input is bad" for our outage',
      );
      expect((await res.json() as Map)['error'], 'storage_unavailable');
      expect(res.headers['retry-after'], '5', reason: surface);
    }

    test('POST /appointments/{id}/deposit', () async {
      await appts.create({
        'id': 'a1',
        'userId': 'user_A',
        'providerId': 'provider1',
        'serviceIds': const ['service1'],
        'artistId': null,
        'appointmentDate': DateTime.utc(2030, 6, 10, 9).toIso8601String(),
        'durationMinutes': 60,
        'status': 'pending',
        'totalPrice': 15000,
        'depositAmount': 4500,
        'balanceDue': 10500,
        'createdAt': DateTime.utc(2030).toIso8601String(),
      });
      final svc = DepositService(
        appts,
        MembershipService(InMemoryMembershipRepository(), providerAuth),
        _UnreachableStorage(),
        verifier: verifier(),
      );
      final res = await deposit_route.onRequest(
        ctx(
          Request(
            'POST',
            Uri.parse('http://localhost/appointments/a1/deposit'),
            headers: {
              'Authorization':
                  'Bearer '
                  '${tokens.issueAccessToken(subject: 'user_A', role: 'user').token}',
            },
            body: '{"screenshotKey":"pending/deposit/user_A/x.jpg"}',
          ),
          (c) => when(() => c.read<DepositService>()).thenReturn(svc),
        ),
        'a1',
      );
      await expect503(res, 'deposit');
    });

    test('POST /appointments/{id}/review', () async {
      final providers = InMemoryProvidersRepository();
      await appts.create({
        'id': 'a2',
        'userId': 'user_A',
        'providerId': 'provider1',
        'serviceIds': const ['service1'],
        'artistId': null,
        'appointmentDate': DateTime.utc(2030, 6, 10, 9).toIso8601String(),
        'durationMinutes': 60,
        'status': 'completed',
        'totalPrice': 15000,
        'depositAmount': 0,
        'balanceDue': 15000,
        'createdAt': DateTime.utc(2030).toIso8601String(),
      });
      final svc = ReviewsService(
        InMemoryReviewsRepository(),
        appts,
        providers,
        InMemoryAuthRepository(tokens: tokens, isProd: false),
        allowedImageOrigins: const ['https://cdn.myweli.com'],
        verifier: verifier(),
        publicBaseUrl: 'https://cdn.myweli.com',
      );
      final res = await review_route.onRequest(
        ctx(
          Request(
            'POST',
            Uri.parse('http://localhost/appointments/a2/review'),
            headers: {
              'Authorization':
                  'Bearer '
                  '${tokens.issueAccessToken(subject: 'user_A', role: 'user').token}',
            },
            body:
                '{"rating":5,"text":"ok","photoUrls":'
                '["https://cdn.myweli.com/pending/review/user_A/p.jpg"]}',
          ),
          (c) => when(() => c.read<ReviewsService>()).thenReturn(svc),
        ),
        'a2',
      );
      await expect503(res, 'review');
    });

    test('POST /me/kyc — the resultResponse path', () async {
      final reg = await providerAuth.register(
        email: 'su@test.pro',
        authProvider: 'google',
        googleSub: 'su-sub',
        phoneNumber: '+2250500000041',
        businessName: 'X',
        businessType: 'salon',
      );
      final accountId = reg.provider!.id;
      final svc = KycService(providerAuth, verifier: verifier());
      final res = await kyc_route.onRequest(
        ctx(
          Request(
            'POST',
            Uri.parse('http://localhost/me/kyc'),
            headers: {
              'Authorization':
                  'Bearer '
                  '${tokens.issueAccessToken(subject: accountId, role: 'provider').token}',
            },
            body:
                '{"documents":[{"type":"idCard","fileName":"a.jpg",'
                '"key":"pending/kyc/$accountId/a.jpg"}]}',
          ),
          (c) => when(() => c.read<KycService>()).thenReturn(svc),
        ),
      );
      await expect503(res, 'kyc');
    });
  });

  group('no surface left behind', () {
    test('every route reading a claiming service maps it', () {
      // The pin that makes the rest of this file worth having, and the reason
      // it derives the set instead of listing it: the tests above each name a
      // route, so a NEW upload-claiming surface added later would pass all of
      // them while quietly answering 400 for our own outage.
      //
      // Two steps. Which services can emit the code — the ones that call the
      // verifier at all — then which routes read one of those. A route that
      // does must either delegate to `resultResponse` or name the code in its
      // own switch.
      //
      // Deliberately narrow: routes with a bespoke switch that never touch
      // storage (cancel, arrive, reschedule…) are not offenders, and demanding
      // an arm from them would be noise nobody would keep.
      final claiming = <String>{};
      for (final f in Directory('lib/src').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('upload_verification_service.dart')) continue;
        final src = f.readAsStringSync();
        final claims =
            src.contains('verifyAndPromote(') ||
            src.contains('promoteNewUrls(') ||
            src.contains('promoteNewKeys(');
        if (!claims) continue;
        for (final m in RegExp(
          r'^class (\w+)',
          multiLine: true,
        ).allMatches(src)) {
          claiming.add(m.group(1)!);
        }
      }
      expect(
        claiming,
        isNotEmpty,
        reason:
            'the scan found no claiming service at all — it has drifted, '
            'and an empty set makes the assertion below vacuous',
      );

      // Reading a claiming service is not the same as calling its claiming
      // method — the review LIST routes read `ReviewsService` and never touch
      // storage. Rather than loosen the rule until it catches nothing, the
      // exemption is a DECLARATION, the same shape SYSTEM.md's `clip-ok:`
      // marker takes: a route may opt out with `// no-upload-claim:` and a
      // reason, and an opt-out that stops being true is itself a failure.
      const marker = '// no-upload-claim:';
      final offenders = <String>[];
      final orphanedMarkers = <String>[];
      for (final f in Directory('routes').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync();
        final reads = claiming.any((c) => src.contains('context.read<$c>()'));
        if (!reads) {
          if (src.contains(marker)) orphanedMarkers.add(f.path);
          continue;
        }
        if (src.contains(marker)) continue;
        if (src.contains('resultResponse')) continue;
        if (src.contains('storage_unavailable')) continue;
        offenders.add(f.path);
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'these routes reach a service that can fail with '
            'storage_unavailable and neither delegate to resultResponse nor '
            'name the code, so our outage falls to their 400 default. Add a '
            '`case` returning storageUnavailable(), or declare `$marker` with '
            'a reason if the route genuinely cannot claim.',
      );
      expect(
        orphanedMarkers,
        isEmpty,
        reason:
            'these routes declare `$marker` but no longer read a claiming '
            'service at all. A stale exemption is how the next real one gets '
            'waved through — delete it.',
      );
    });
  });
}

class _MockRequestContext extends Mock implements RequestContext {}

/// Storage that cannot be reached — `objectSize` throws, which is what makes
/// `verify` fail closed with `storage_unavailable`.
class _UnreachableStorage extends FakeStorageService {
  @override
  Future<int?> objectSize({
    required String key,
    required StorageBucket bucket,
  }) async => throw const SocketException('bucket unreachable');
}
