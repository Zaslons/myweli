/// **The booking funnel, end to end, against a real server on real Postgres.**
///
/// Q1 — design: `docs/design/backend-q1-funnel-smoke.md`. This closes
/// ROADMAP §1.8's claim that nothing is exercised against a real backend, and
/// de-risks `docs/DEPLOYMENT.md` Phase G before a single account is paid for.
///
/// ## Why this file lives in `tool/`, not `test/`
///
/// The backend CI job runs a bare `dart test`, which collects **only** `test/`.
/// Measured: a marker in `tool/smoke/` is invisible to `dart test` (0 hits over
/// the full 622-test run) and runs when named explicitly. So this harness can be
/// **fail-closed** — no `skip:`, no tag to forget — and still never fire in the
/// unit job. A `skip:` that silently becomes permanent is exactly the failure
/// §21 row 67 records six times over.
///
/// ## What makes it trustworthy
///
/// Every assertion is paired or falsifiable — see the spec's §4. The shapes are
/// not guessed: each request below was executed against a live server on real
/// Postgres while this file was written, and the assertions record what came
/// back, not what the contract hoped for. Three spec claims died that way and
/// are marked ✗-corrected inline.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'smoke_target.dart';

/// Fail-closed and **deny-by-default about which server it may write to** —
/// see `smoke_target.dart` for why that check lives there and not in the
/// workflow that calls this.
final String baseUrl = resolveSmokeBaseUrl(
  Platform.environment['SMOKE_BASE_URL'],
);

/// The JWT secret the server was booted with — needed to MINT the expired-token
/// case (A32), i.e. a token valid in every way except time. Without it that
/// assertion degenerates into "a garbage string is rejected", which A31 already
/// proves.
final String jwtSecret = Platform.environment['JWT_SECRET'] ?? '';

/// `SMOKE_OTP_SECRET` — required only when the target runs `ENV=prod`, which
/// suppresses `devCode` (`auth_repository.dart:224`). Against a dev/CI server
/// this stays empty and nothing changes.
///
/// The identities below all end in `@smoke.test`, and that is now **enforced**
/// server-side: the RFC 2606 reserved TLD is the constraint that stops this
/// secret from being an account-takeover primitive for real addresses.
/// See docs/design/backend-q1b-smoke-seam.md.
final String smokeSecret = Platform.environment['SMOKE_OTP_SECRET'] ?? '';

/// Admin credentials, seeded by `dependencies.dart:750-752` when set. Phase 7
/// needs them; they are fake and non-secret by construction.
final String adminEmail = Platform.environment['ADMIN_EMAIL'] ?? '';
final String adminPassword = Platform.environment['ADMIN_PASSWORD'] ?? '';

/// One nonce per run, so the harness never depends on a pristine database and
/// two runs against the same Postgres cannot collide.
final String nonce = DateTime.now().microsecondsSinceEpoch.toRadixString(36);

/// A per-run E.164 phone. **Derived from digits, never from [nonce]** — that is
/// base36 and carries letters, which the boundary validator rejects as
/// `invalid_input`. The first run of this harness died on exactly that, in a
/// cascade of 33 `LateInitializationError`s behind one real failure.
final String phoneNonce = () {
  final digits = DateTime.now().microsecondsSinceEpoch.toString();
  return '+22507${digits.substring(digits.length - 8)}';
}();

/// The booking day, computed **once**. A run straddling midnight must not use
/// two different days. +7 clears the 60-minute minimum notice by a wide margin
/// and sits far inside the 365-day horizon.
final DateTime bookingDay = DateTime.now().toUtc().add(const Duration(days: 7));
String get bookingDate =>
    '${bookingDay.year.toString().padLeft(4, '0')}-'
    '${bookingDay.month.toString().padLeft(2, '0')}-'
    '${bookingDay.day.toString().padLeft(2, '0')}';

/// The anti-vacuity guard (spec §4.4). Every assertion bumps this; the final
/// test asserts the total. If an early phase throws and a later `setUp` quietly
/// swallows it, the count is short and the run is red — a suite cannot pass by
/// not running.
int steps = 0;

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------

typedef Res = ({
  int status,
  Map<String, dynamic> json,
  String raw,
  String request,
});

final http.Client _client = http.Client();

Future<Res> _send(
  String method,
  String path, {
  Object? body,
  String? token,
}) async {
  final req = http.Request(method, Uri.parse('$baseUrl$path'));
  if (body != null) {
    req.headers['content-type'] = 'application/json';
    req.body = jsonEncode(body);
  }
  if (token != null) req.headers['authorization'] = 'Bearer $token';
  // Q1b — lets the harness authenticate against ENV=prod, where `devCode` is
  // suppressed. Sent on every request rather than only the OTP ones: the server
  // ignores it everywhere else, and a per-call opt-in would be one more thing
  // to forget. Unset off-prod, where `devCode` is echoed anyway.
  if (smokeSecret.isNotEmpty) req.headers['x-smoke-secret'] = smokeSecret;
  final streamed = await _client.send(req);
  final res = await http.Response.fromStream(streamed);
  Map<String, dynamic> parsed;
  try {
    final decoded = jsonDecode(res.body);
    parsed = decoded is Map<String, dynamic> ? decoded : {'_list': decoded};
  } catch (_) {
    parsed = const {};
  }
  return (
    status: res.statusCode,
    json: parsed,
    raw: res.body,
    // Kept for the failure line below. A 4xx is very often EXPECTED here (half
    // this suite asserts refusals), so echoing on status alone printed fifteen
    // lines of noise on a green run — the request is dumped only when the
    // status is not the one asserted.
    request: '$method $path ${req.body}',
  );
}

Future<Res> get(String p, {String? token}) => _send('GET', p, token: token);
Future<Res> post(String p, {Object? body, String? token}) =>
    _send('POST', p, body: body, token: token);
Future<Res> put(String p, {Object? body, String? token}) =>
    _send('PUT', p, body: body, token: token);
Future<Res> patch(String p, {Object? body, String? token}) =>
    _send('PATCH', p, body: body, token: token);

/// Asserts the status and prints the **body** when it does not match — a bare
/// "expected 200, got 409" costs a re-run to diagnose; the body usually names
/// the cause outright.
void expectStatus(Res r, int want, String what) {
  steps++;
  expect(
    r.status,
    want,
    reason:
        '$what — expected $want, got ${r.status}.\n'
        '      request:  ${r.request}\n'
        '      response: ${r.raw}',
  );
}

void expectError(Res r, int status, String code, String what) {
  expectStatus(r, status, what);
  steps++;
  expect(r.json['error'], code, reason: '$what — body was ${r.raw}');
}

/// Pull `devCode` off an OTP response, or fail with the reason rather than a
/// null-cast.
///
/// This harness spent its whole life pointed at dev servers, where `devCode` is
/// always present, so `as String` was safe. Against `ENV=prod` it is not: the
/// field is absent unless the Q1b seam is configured on BOTH sides, and a bare
/// null-cast reported that as `type 'Null' is not a subtype of type 'String'`
/// — which says nothing about the actual cause.
String _requireDevCode(Res res, String who) {
  final code = res.json['devCode'];
  if (code is String) return code;
  throw StateError(
    'No devCode in the OTP response for $who. Against ENV=prod this means the '
    'smoke seam is not active: set SMOKE_OTP_SECRET (>=32 chars) on BOTH the '
    'server and this harness, and use an identity ending in `.test`. '
    'See docs/design/backend-q1b-smoke-seam.md.',
  );
}

// ---------------------------------------------------------------------------
// Identities
// ---------------------------------------------------------------------------

/// Sign a consumer in by e-mail OTP. Returns the **nested** session shape
/// (`tokens.accessToken` + `user.id`) that `responses.dart:44-46` records as
/// deliberately different from the pro's flat one.
Future<({String access, String refresh, String userId})> signInConsumer(
  String email,
) async {
  final req = await post('/auth/email/otp/request', body: {'email': email});
  expectStatus(req, 202, 'consumer OTP request ($email)');
  final code = _requireDevCode(req, 'consumer $email');
  final ver = await post(
    '/auth/email/otp/verify',
    body: {'email': email, 'code': code},
  );
  expectStatus(ver, 200, 'consumer OTP verify ($email)');
  final tokens = ver.json['tokens'] as Map<String, dynamic>;
  final user = ver.json['user'] as Map<String, dynamic>;
  return (
    access: tokens['accessToken'] as String,
    refresh: tokens['refreshToken'] as String,
    userId: user['id'] as String,
  );
}

/// Register a salon and return its **salon** id.
///
/// ✗-corrected: the spec asserted `provider.status == "draft"` on this
/// response. There is no `status` key on it — the `provider` object here is the
/// pro ACCOUNT DTO (`authProvider`, `verificationStatus`, `kycDocs`). The salon
/// document, and its status, live behind `GET /me/provider` → `.provider`.
Future<({String salonId, String accountId, String access})> registerSalon(
  String label,
) async {
  final email = 'pro-$label-$nonce@smoke.test';
  final req = await post(
    '/auth/provider/email/otp/request',
    body: {'email': email},
  );
  expectStatus(req, 202, 'pro OTP request ($label)');
  final code = _requireDevCode(req, 'pro $email');

  // A6 — verify BEFORE any salon exists must refuse, and must not consume the
  // code: T35 (login never auto-creates a salon) and the
  // register-right-after-a-failed-login path both depend on it
  // (`provider_auth_repository.dart:363-375`).
  final early = await post(
    '/auth/provider/email/otp/verify',
    body: {'email': email, 'code': code},
  );
  expectError(early, 404, 'provider_not_found', 'pro login with no salon');

  final reg = await post(
    '/auth/provider/register',
    body: {
      'businessName': 'Smoke $label $nonce',
      'businessType': 'salon',
      // Digits, never [nonce] — that is base36 and produced `+22507hl18e6la`,
      // which `isValidE164` rejects (`validators.dart:7`). The first two runs
      // of this harness died on it, behind a cascade of 33
      // `LateInitializationError`s: one real failure, thirty-three symptoms.
      'phoneNumber': label == 'main'
          ? phoneNonce
          : '${phoneNonce.substring(0, phoneNonce.length - 1)}9',
      'address': 'Rue du Smoke, Cocody',
      'areaId': 'cocody',
      'email': email,
      'code': code, // the code the failed login did NOT consume
    },
  );
  expectStatus(reg, 201, 'pro register ($label)');
  final p = reg.json['provider'] as Map<String, dynamic>;
  steps++;
  expect(
    p['providerId'],
    isNot(equals(p['id'])),
    reason:
        'the account id and the salon id must differ — every /providers/{id}/… '
        'path takes the SALON id, and the account id answers 403',
  );
  return (
    salonId: p['providerId'] as String,
    accountId: p['id'] as String,
    access: reg.json['accessToken'] as String,
  );
}

/// `HH:mm` → the wire date-time the server normalises to. The web half of this
/// PR exists because this conversion was missing there.
String wireTime(String hhmm) => '2024-01-01T$hhmm:00.000Z';

void main() {
  // Shared across phases: the funnel is one story, not 47 independent cases.
  late String salon; // the salon that goes live
  late String proToken;
  late String bystanderSalon; // a second salon, left DRAFT on purpose
  late String bystanderToken;
  late String consumerToken;
  late String consumerId;
  late String consumerRefresh;
  late String otherConsumerToken;
  late String serviceId;
  late String slot0;
  late String appointmentId;

  // **Ask the target what it is, before writing anything to it.**
  //
  // `resolveSmokeBaseUrl` already refuses production by URL, but that is a check
  // on the *spelling* of the target — it cannot see an IP literal, a CNAME, a
  // tunnel, or a staging-looking hostname pointed at the production service. So
  // the second layer asks the server, which answers with the `ENV` it actually
  // booted with. Two layers because the consequence is writing real rows to the
  // real marketplace, and neither layer alone covers the other's blind spot.
  setUpAll(() async {
    final r = await get('/health');
    if (r.status != 200) {
      throw StateError(
        'Refusing to start: $baseUrl/health returned ${r.status}. This harness '
        'writes, and will not do so against a server it cannot identify.',
      );
    }
    final reported = r.json['env'];
    if (reported == null) {
      throw StateError(
        'Refusing to run: $baseUrl/health does not report `env`. Either it is '
        'not this API, or it predates the field this check depends on — and a '
        'check that silently degrades to "no check" is the thing this harness '
        'exists to avoid.',
      );
    }
    if (!permittedEnvs.contains(reported)) {
      throw StateError(
        'Refusing to run: $baseUrl SELF-REPORTS ENV=$reported. The URL passed '
        'the target check, so this is a permitted-looking address pointed at a '
        'forbidden deployment — exactly the case a hostname rule cannot see. '
        'See smoke_target.dart for why production is a deliberate edit rather '
        'than a flag.',
      );
    }
  });

  tearDownAll(() => _client.close());

  // -------------------------------------------------------------------------
  group('Phase 0 — the platform answers', () {
    test('A1 /health is ok, and says which deployment answered', () async {
      final r = await get('/health');
      expectStatus(r, 200, 'A1 /health');
      steps++;
      expect(r.json['status'], 'ok');
      // The field `setUpAll` above gates on. Asserted here too so that removing
      // it from the route breaks a visible test rather than silently turning
      // the identity check into a no-op.
      expect(r.json['env'], isIn(const ['dev', 'staging']));
    });

    test('A2 /providers returns the seeded catalogue', () async {
      final r = await get('/providers');
      expectStatus(r, 200, 'A2 /providers');
      steps++;
      expect(
        r.json.keys,
        containsAll(['items', 'page', 'pageSize', 'total']),
        reason: 'the list envelope is part of the contract (BACKEND.md §2)',
      );
      final items = r.json['items'] as List;
      steps++;
      expect(
        items.any((e) => (e as Map)['id'] == 'provider1'),
        isTrue,
        reason:
            'migrations + seed did not run on a real Postgres, or the '
            'discovery filter hides live salons — a blank home screen',
      );
    });

    test('A2b a SEEDED salon is readable by DETAIL, not just by list', () async {
      // **Added by the mutation ledger, which then explained itself.** Flipping
      // `isPublicSalon` to the SHOW form (`salon['status'] == 'active'`) leaves
      // this suite green, and that is CORRECT rather than a gap: against
      // Postgres the two spellings are behaviourally identical.
      //
      // `providers.status` is `NOT NULL DEFAULT 'active'` (measured: 0 of 4
      // seeded rows null), and `postgres_providers_repository.dart:669` folds
      // `?? 'active'` on top of that. So a document from this repository always
      // carries one of `active | draft | suspended`, and HIDE and SHOW agree on
      // all three. They diverge on exactly one input — a fourth status invented
      // later, where HIDE fails OPEN and SHOW fails closed — which no code path
      // can currently produce.
      //
      // The NULL trap `hiddenSalonStatuses` is written for is real, but it
      // lives in the IN-MEMORY repository, whose seeds carry no `status` key at
      // all. That is the environment `backend/test/salon_visibility_test.dart`
      // runs in, and it remains the guard. **No end-to-end assertion can cover
      // it**, and the spec's §8 says so rather than implying otherwise.
      //
      // The assertion earns its place regardless: nothing else in this suite
      // reads a SEEDED salon by detail, only through `/providers`, which
      // filters in the repository (`postgres_providers_repository.dart:35`)
      // rather than through the predicate.
      final r = await get('/providers/provider1');
      expectStatus(r, 200, 'A2b seeded salon detail read');
      steps++;
      expect(r.json['id'], 'provider1');
    });

    test('A3 /localities carries the multi-pays tree', () async {
      final r = await get('/localities');
      expectStatus(r, 200, 'A3 /localities');
      steps++;
      expect(r.raw, contains('"code":"CI"'));
      steps++;
      expect(r.raw, contains('"id":"cocody"'));
    });

    test('A4 the SMS door is SHUT under production auth config', () async {
      // The assertion this whole slice was worth writing for. CI used to run
      // with `AUTH_METHODS` unset, and `auth_methods.dart:21` makes `phone` a
      // DEFAULT — so the old smoke's only auth assertion exercised a door
      // `render.yaml:58` documents as dormant, at $0.49/segment, and never
      // touched the e-mail door production actually serves.
      final r = await post(
        '/auth/otp/request',
        body: {'phoneNumber': '+2250700000009'},
      );
      expectError(r, 404, 'auth_method_disabled', 'A4 phone OTP must be off');
    });
  });

  // -------------------------------------------------------------------------
  group('Phase 1 — a salon is born, and is invisible while it is a draft', () {
    test('A5–A7 register, and the login-before-salon refusal', () async {
      final s = await registerSalon('main');
      salon = s.salonId;
      proToken = s.access;
    });

    test('A7b the salon document says draft', () async {
      final r = await get('/me/provider', token: proToken);
      expectStatus(r, 200, 'A7b /me/provider');
      final doc = r.json['provider'] as Map<String, dynamic>;
      steps++;
      expect(doc['status'], 'draft');
      steps++;
      expect(doc['id'], salon, reason: '/me/provider resolves by account');
    });

    test('A8 a draft salon is not publicly readable', () async {
      final r = await get('/providers/$salon');
      // T51: missing and hidden must be indistinguishable, or the 404 becomes
      // an enumeration oracle.
      expectError(r, 404, 'not_found', 'A8 draft detail read');
    });

    test('A9 …and not through /availability either', () async {
      final r = await get('/availability?providerId=$salon&date=$bookingDate');
      // Deliberately a DIFFERENT vocabulary from A8 — the browse route answers
      // to anyone, so naming the state there would leak it.
      expectError(r, 404, 'provider_not_found', 'A9 draft availability');
    });

    test('A10 the consumer session is the NESTED shape', () async {
      final c = await signInConsumer('client-$nonce@smoke.test');
      consumerToken = c.access;
      consumerId = c.userId;
      consumerRefresh = c.refresh;
      steps++;
      expect(consumerToken, isNotEmpty);
    });

    test('A11 a draft salon refuses client bookings', () async {
      final r = await post(
        '/appointments',
        token: consumerToken,
        body: {
          'providerId': salon,
          'serviceIds': ['nope'],
          'appointmentDateTime': '${bookingDate}T09:00:00.000Z',
        },
      );
      // Also pins guard ORDER: the salon refusal is answered before service
      // validation, which is why a bogus service id still yields this code.
      expectError(r, 409, 'provider_not_published', 'A11 draft booking');
    });
  });

  // -------------------------------------------------------------------------
  group('Phase 2 — the go-live gate, from the inside', () {
    test('A12 an empty salon is refused, with the FULL missing set', () async {
      final r = await post('/providers/$salon/publish', token: proToken);
      expectStatus(r, 409, 'A12 publish an empty salon');
      steps++;
      expect(r.json['error'], 'incomplete');
      steps++;
      // SET equality, not `contains`: a silently dropped check is the failure
      // mode, and `contains` cannot see it.
      expect(
        (r.json['missing'] as List).cast<String>().toSet(),
        {'profile', 'location', 'services', 'photos', 'availability', 'offer'},
        reason: 'the go-live checklist must stay server-authoritative',
      );
    });

    test('A13 profile + location persist', () async {
      final r = await patch(
        '/providers/$salon',
        token: proToken,
        body: {
          'description': 'Salon de la fumée, Cocody.',
          'latitude': 5.35,
          'longitude': -3.99,
        },
      );
      expectStatus(r, 200, 'A13 patch profile');
      steps++;
      expect(r.json['latitude'], closeTo(5.35, 0.0001));
    });

    test('A14 three services, and the server owns their ids', () async {
      for (var i = 0; i < 3; i++) {
        final r = await post(
          '/providers/$salon/services',
          token: proToken,
          body: {
            'id': 'client-chosen-$i', // must be ignored
            'name': 'Coupe $i',
            'price': 5000,
            'durationMinutes': 30,
            'category': 'coiffure',
            // ✗-corrected: the spec also sent `active: false` and asserted the
            // server ignored it. It does NOT — `active` is client-settable by
            // design (`provider_catalog_service.dart:80`, `?? true`), so a pro
            // can stage a service before offering it. The invented assertion
            // starved `publishGate`, which counts only ACTIVE services, and
            // reddened three later phases. What IS server-owned is the id.
          },
        );
        expectStatus(r, 201, 'A14 create service $i');
        steps++;
        expect(
          r.json['id'],
          isNot('client-chosen-$i'),
          reason: 'the server must own service ids, not the client',
        );
        steps++;
        expect(
          r.json['active'],
          isTrue,
          reason:
              'the DEFAULT must be active — a salon that publishes three '
              'services and finds none of them bookable has no recourse',
        );
        if (i == 0) serviceId = r.json['id'] as String;
      }
      // `publishGate` needs THREE (`salon_provisioning_service.dart:114`).
    });

    test('A15 three photos', () async {
      final r = await put(
        '/providers/$salon/gallery',
        token: proToken,
        body: {
          'imageUrls': [
            'https://cdn.stub/a.jpg',
            'https://cdn.stub/b.jpg',
            'https://cdn.stub/c.jpg',
          ],
        },
      );
      expectStatus(r, 200, 'A15 gallery');
      steps++;
      expect((r.json['imageUrls'] as List).length, 3);
    });

    test(
      'A16 hours persist, and the A14d keys survive the allow-list',
      () async {
        final schedule = <String, List<Map<String, Object>>>{
          for (var d = 0; d < 7; d++)
            '$d': [
              {
                'startTime': wireTime('09:00'),
                'endTime': wireTime('18:00'),
                'isAvailable': true,
              },
            ],
        };
        final r = await put(
          '/providers/$salon/availability',
          token: proToken,
          body: {
            'weeklySchedule': schedule,
            'bufferMinutes': 0,
            'blockedDates': <String>[],
          },
        );
        expectStatus(r, 200, 'A16 availability');

        // Re-GET, not the PUT's echo: `replaceAvailability` builds from an
        // ALLOW-LIST, so an unnamed key is dropped with no error and the PUT
        // still answers 200 (`provider_catalog_service.dart:279-291`).
        final back = await get(
          '/providers/$salon/availability',
          token: proToken,
        );
        expectStatus(back, 200, 'A16 re-GET availability');
        steps++;
        expect((back.json['weeklySchedule'] as Map).length, 7);
        steps++;
        expect(back.json['bookingHorizonDays'], 365);
        steps++;
        expect(back.json['minimumNoticeMinutes'], 60);
      },
    );

    test('A17 only the OFFER is left', () async {
      final r = await post('/providers/$salon/publish', token: proToken);
      expectStatus(r, 409, 'A17 publish without an offer');
      steps++;
      expect(
        (r.json['missing'] as List).cast<String>(),
        ['offer'],
        reason: 'the pricing pivot must be the last door, not an optional one',
      );
    });

    test('A18 the trial starts', () async {
      final r = await put(
        '/providers/$salon/subscription',
        token: proToken,
        body: {'tier': 'pro'},
      );
      expectStatus(r, 200, 'A18 subscription');
      steps++;
      expect(r.json['status'], 'trial');
      steps++;
      expect(
        DateTime.parse(r.json['trialEndsAt'] as String).isAfter(DateTime.now()),
        isTrue,
      );
    });

    test('A19 the salon goes live', () async {
      final r = await post('/providers/$salon/publish', token: proToken);
      expectStatus(r, 200, 'A19 publish');
      steps++;
      expect(r.json['status'], 'active');
    });

    test('A20 …and the public door opens (the pair for A8)', () async {
      final r = await get('/providers/$salon');
      expectStatus(r, 200, 'A20 public detail read');
      steps++;
      expect(r.json['id'], salon);
      // A8 and A20 falsify each other: a server that 404s everything passes A8
      // and fails this; one that 200s everything does the reverse.
    });

    test('A21 …and discovery agrees with the detail gate', () async {
      final r = await get('/providers?q=Smoke%20main%20$nonce');
      expectStatus(r, 200, 'A21 discovery search');
      steps++;
      expect(
        (r.json['items'] as List).any((e) => (e as Map)['id'] == salon),
        isTrue,
        reason:
            'the list filter and the detail gate are two spellings of one '
            'rule; when they disagree a salon is linkable but unfindable',
      );
    });
  });

  // -------------------------------------------------------------------------
  group('Phase 3 — the consumer books', () {
    test('A22 slots exist for an open, published, in-horizon day', () async {
      final r = await get(
        '/availability?providerId=$salon&date=$bookingDate&serviceIds=$serviceId',
      );
      expectStatus(r, 200, 'A22 availability');
      final slots = (r.json['slots'] as List).cast<String>();
      steps++;
      expect(
        slots,
        isNotEmpty,
        reason:
            'an empty slots array is a 200 by design — the funnel would be '
            'dead with no error anywhere',
      );
      steps++;
      expect(DateTime.tryParse(slots.first), isNotNull);
      slot0 = slots.first;
    });

    test('A23 the booking is created, and the SERVER prices it', () async {
      final r = await post(
        '/appointments',
        token: consumerToken,
        body: {
          'providerId': salon,
          'serviceIds': [serviceId],
          'appointmentDateTime': slot0,
          'totalPrice': 1, // must be ignored — server authority
        },
      );
      expectStatus(r, 201, 'A23 book');
      steps++;
      expect(r.json['status'], 'pending');
      steps++;
      expect(
        r.json['totalPrice'],
        5000,
        reason:
            'asserted against a price the client never sent — this is the '
            'server-authority proof, not a formatting check',
      );
      steps++;
      expect(r.json['balanceDue'], 5000);
      steps++;
      expect(r.json['userId'], consumerId);
      // ✗-corrected: the spec asserted `currency == "XOF"`. The appointment DTO
      // carries `currency: null` — the salon holds the currency, the booking
      // does not. Recorded in the spec rather than asserted falsely here.
      appointmentId = r.json['id'] as String;
    });

    test('A24 the engine sees its own write', () async {
      final r = await get(
        '/availability?providerId=$salon&date=$bookingDate&serviceIds=$serviceId',
      );
      expectStatus(r, 200, 'A24 availability after booking');
      steps++;
      expect(
        (r.json['slots'] as List).cast<String>(),
        isNot(contains(slot0)),
        reason: 'the same slot is sellable twice — two clients, one chair',
      );
    });

    test('A25 the same slot cannot be booked again', () async {
      final r = await post(
        '/appointments',
        token: consumerToken,
        body: {
          'providerId': salon,
          'serviceIds': [serviceId],
          'appointmentDateTime': slot0,
        },
      );
      expectError(r, 409, 'slot_unavailable', 'A25 double-book');
    });
  });

  // -------------------------------------------------------------------------
  group('Phase 4 — the salon answers', () {
    test('A26 the pro sees it, resolved from the token', () async {
      final r = await get('/appointments', token: proToken);
      expectStatus(r, 200, 'A26 pro agenda');
      final items = (r.json['items'] as List).cast<Map<String, dynamic>>();
      steps++;
      expect(
        items.any((e) => e['id'] == appointmentId && e['status'] == 'pending'),
        isTrue,
        reason: 'no salon id was sent — it must come from the memberships',
      );
    });

    test('A27 accept confirms it', () async {
      final r = await post(
        '/appointments/$appointmentId/accept',
        token: proToken,
      );
      expectStatus(r, 200, 'A27 accept');
      steps++;
      expect(r.json['status'], 'confirmed');
    });

    test('A28 …and the lifecycle is a state machine, not a setter', () async {
      final r = await post(
        '/appointments/$appointmentId/accept',
        token: proToken,
      );
      expectError(r, 409, 'invalid_state', 'A28 re-accept');
    });

    test('A29 the enrichment survives a real Postgres round-trip', () async {
      final r = await get('/appointments/$appointmentId', token: consumerToken);
      expectStatus(r, 200, 'A29 consumer detail');
      steps++;
      expect(r.json['status'], 'confirmed');
      steps++;
      expect(
        r.json['providerName'],
        contains('Smoke main'),
        reason:
            "PR1c/Decision C: the client's own card must name the salon it "
            'booked, hydrated by the server rather than side-fetched',
      );
      steps++;
      expect(r.json['providerPhone'], isNotNull);
    });
  });

  // -------------------------------------------------------------------------
  group('Phase 5 — the refusals (BACKEND.md §5 required list)', () {
    test('A30 missing auth', () async {
      final r = await get('/appointments');
      expectStatus(r, 401, 'A30 no Authorization header');
    });

    test('A31 invalid token', () async {
      final r = await get('/appointments', token: 'not-a-token');
      expectStatus(r, 401, 'A31 garbage bearer');
    });

    test('A32 expired token — valid in every way except time', () async {
      steps++;
      expect(
        jwtSecret,
        isNotEmpty,
        reason:
            'JWT_SECRET must reach the harness, or this degenerates into A31',
      );
      final jwt = JWT({
        'sub': consumerId,
        'role': 'user',
        'iat':
            DateTime.now()
                .subtract(const Duration(hours: 2))
                .millisecondsSinceEpoch ~/
            1000,
        'exp':
            DateTime.now()
                .subtract(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000,
      });
      final token = jwt.sign(SecretKey(jwtSecret));
      final r = await get('/appointments', token: token);
      expectStatus(r, 401, 'A32 expired but correctly signed');
    });

    test('A33 replayed refresh revokes the FAMILY', () async {
      final first = await post(
        '/auth/refresh',
        body: {'refreshToken': consumerRefresh},
      );
      expectStatus(first, 200, 'A33 first refresh');
      final child = first.json['refreshToken'] as String;

      final replay = await post(
        '/auth/refresh',
        body: {'refreshToken': consumerRefresh},
      );
      expectStatus(replay, 401, 'A33 replay');

      // The one that matters: the CHILD must be dead too, or the family was
      // not revoked and a stolen token still buys a session
      // (`postgres_auth_repository.dart:287-290`).
      final afterRevoke = await post(
        '/auth/refresh',
        body: {'refreshToken': child},
      );
      expectStatus(afterRevoke, 401, 'A33 child after family revoke');
    });

    test('A34 OTP lockout', () async {
      final email = 'lock-$nonce@smoke.test';
      final req = await post('/auth/email/otp/request', body: {'email': email});
      expectStatus(req, 202, 'A34 lockout setup');
      final right = req.json['devCode'] as String;
      // Derived from the right code so it can never accidentally be correct —
      // 1 in 900 000 is not zero, and CI runs a lot.
      final wrong = '${(int.parse(right[0]) + 1) % 10}${right.substring(1)}';

      var locked = false;
      for (var i = 0; i < 6; i++) {
        final r = await post(
          '/auth/email/otp/verify',
          body: {'email': email, 'code': wrong},
        );
        if (r.json['error'] == 'otp_locked') locked = true;
      }
      steps++;
      expect(
        locked,
        isTrue,
        reason:
            'no lockout after 6 wrong codes — the OTP is brute-forceable '
            '(maxAttempts = 5, postgres_auth_repository.dart:18)',
      );
    });

    test('A35 cross-tenant consumer → 403, not 404', () async {
      final other = await signInConsumer('other-$nonce@smoke.test');
      otherConsumerToken = other.access;
      final r = await get(
        '/appointments/$appointmentId',
        token: otherConsumerToken,
      );
      expectStatus(r, 403, "A35 consumer B reads consumer A's booking");
    });

    test('A36 cross-tenant pro → 403, and scope beats state', () async {
      final b = await registerSalon('bystander');
      bystanderSalon = b.salonId;
      bystanderToken = b.access;
      final r = await post(
        '/appointments/$appointmentId/accept',
        token: bystanderToken,
      );
      // Already confirmed, so a state-first guard would answer 409. It must
      // answer 403: "not yours" must not leak "already done"
      // (`pro_appointment_service.dart:143-147`).
      expectStatus(r, 403, 'A36 bystander pro accepts');
    });
  });

  // -------------------------------------------------------------------------
  group('Phase 6 — the consumer leaves', () {
    test('A37 cancel', () async {
      final r = await post(
        '/appointments/$appointmentId/cancel',
        token: consumerToken,
      );
      expectStatus(r, 200, 'A37 cancel');
      steps++;
      expect(r.json['status'], 'cancelled');
    });

    test('A38 …and the slot comes back', () async {
      final r = await get(
        '/availability?providerId=$salon&date=$bookingDate&serviceIds=$serviceId',
      );
      expectStatus(r, 200, 'A38 availability after cancel');
      steps++;
      expect(
        (r.json['slots'] as List).cast<String>(),
        contains(slot0),
        reason:
            "a cancelled booking still holds the chair — the salon's day "
            'fills with ghosts (slot_service.dart skips cancelled)',
      );
    });

    test('A39 terminal states are terminal', () async {
      final r = await post(
        '/appointments/$appointmentId/cancel',
        token: consumerToken,
      );
      expectError(r, 409, 'invalid_state', 'A39 re-cancel');
    });
  });

  // -------------------------------------------------------------------------
  group('Phase 7 — the salon is suspended', () {
    late String adminToken;

    test('A41 staff can log in', () async {
      steps++;
      expect(
        adminEmail,
        isNotEmpty,
        reason: 'ADMIN_EMAIL must reach the harness for Phase 7',
      );
      final r = await post(
        '/admin/auth/login',
        body: {'email': adminEmail, 'password': adminPassword},
      );
      expectStatus(r, 200, 'A41 admin login');
      adminToken = r.json['accessToken'] as String;
    });

    test('A42 suspend', () async {
      final r = await post(
        '/admin/providers/$salon/suspend',
        token: adminToken,
        body: {'reason': 'Q1 smoke'},
      );
      expectStatus(r, 200, 'A42 suspend');
    });

    test('A43 a suspended salon leaves the public read', () async {
      final r = await get('/providers/$salon');
      // Same 404 as A8, reached from the other direction: never-published vs
      // live-then-stopped must be indistinguishable to a stranger.
      expectError(r, 404, 'not_found', 'A43 suspended detail read');
    });

    test('A44 the client is told SUSPENDED, not not-published', () async {
      final r = await post(
        '/appointments',
        token: consumerToken,
        body: {
          'providerId': salon,
          'serviceIds': [serviceId],
          'appointmentDateTime': slot0,
        },
      );
      expectError(
        r,
        409,
        'provider_suspended',
        'A44 booking a suspended salon',
      );
    });

    test(
      'A45 …and a draft one is still told NOT PUBLISHED (the pair)',
      () async {
        final r = await post(
          '/appointments',
          token: consumerToken,
          body: {
            'providerId': bystanderSalon,
            'serviceIds': ['whatever'],
            'appointmentDateTime': slot0,
          },
        );
        // Without this, a server answering one code for everything passes A44.
        expectError(
          r,
          409,
          'provider_not_published',
          'A45 booking a draft salon',
        );
      },
    );

    test(
      'A46 Decision A — a SUSPENDED salon may not write its own calendar',
      () async {
        final r = await post(
          '/providers/$salon/appointments',
          token: proToken,
          body: {
            'serviceIds': [serviceId],
            'appointmentDateTime': slot0,
            'clientName': 'Walk In',
          },
        );
        expectError(r, 409, 'provider_suspended', 'A46 manual on suspended');
      },
    );

    test(
      'A47 …but a DRAFT salon owns its calendar (the half that matters)',
      () async {
        // `salon_visibility.dart:74-78` — « bookManual deliberately does NOT call
        // this ». Asserted until now only against an in-memory repository. If
        // this reddens, someone folded draft and suspended together and took the
        // calendar away from every salon still onboarding.
        final svc = await post(
          '/providers/$bystanderSalon/services',
          token: bystanderToken,
          body: {'name': 'Coupe', 'price': 3000, 'durationMinutes': 30},
        );
        expectStatus(svc, 201, 'A47 bystander service');
        final r = await post(
          '/providers/$bystanderSalon/appointments',
          token: bystanderToken,
          body: {
            'serviceIds': [svc.json['id']],
            'appointmentDateTime': '${bookingDate}T14:00:00.000Z',
            'clientName': 'Walk In',
          },
        );
        expectStatus(r, 201, 'A47 manual on a DRAFT salon must succeed');
      },
    );
  });

  // -------------------------------------------------------------------------
  test('A48 the suite actually ran (anti-vacuity)', () {
    // A suite cannot pass by not running. If an early phase throws and the rest
    // never execute, this is short and the run is red.
    expect(
      steps,
      greaterThanOrEqualTo(60),
      reason:
          'only $steps assertions executed — phases were skipped or swallowed',
    );
  });
}
