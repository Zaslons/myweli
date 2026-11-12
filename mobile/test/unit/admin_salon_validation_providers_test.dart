import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/salon_validation.dart';
import 'package:myweli/providers/admin/admin_auth_provider.dart';
import 'package:myweli/providers/admin/admin_dashboard_provider.dart';
import 'package:myweli/providers/admin/admin_provider_detail_provider.dart';
import 'package:myweli/providers/admin/admin_providers_provider.dart';
import 'package:myweli/providers/admin/admin_salon_validation_count_provider.dart';
import 'package:myweli/providers/admin/admin_salon_validation_detail_provider.dart';
import 'package:myweli/providers/admin/admin_salon_validations_provider.dart';
import 'package:myweli/services/admin/admin_service.dart';
import 'package:myweli/services/interfaces/session_store.dart';

import '../support/admin_salon_validation_fixtures.dart';

/// docs/design/salon-go-live-approval.md §4.1–§4.4, §8.2 — the console's
/// state for « Salons à valider »: the queue (tabs, 50 per page, a row that
/// leaves at once), the detail (the B9.8 stale-detail guard, the decisions,
/// the re-reads after a 409 that may have written), the sidebar's count
/// (silent on a server from before B0.18), and « Lever la suspension » on
/// the two servers it answers from (§9.2).
void main() {
  late InMemorySessionStore store;

  setUp(() async {
    store = InMemorySessionStore();
    await store.save(jsonEncode({'token': 't', 'refreshToken': 'r'}));
  });

  AdminService svc(MockClient c) =>
      AdminService(client: c, baseUrl: 'http://x', store: store);

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);

  /// The older server's answer to a route it does not have.
  final routeNotFound = http.Response('Route not found', 404);

  final p1 = SalonId('provider_1');

  group('AdminSalonValidationsProvider — the queue', () {
    test('« En attente » first, 50 per page; previous/next follow the '
        'total', () async {
      final asked = <Map<String, String>>[];
      final q = AdminSalonValidationsProvider(
        service: svc(
          MockClient((req) async {
            asked.add(req.url.queryParameters);
            final page = int.parse(req.url.queryParameters['page']!);
            return json(queuePage(total: 120, page: page));
          }),
        ),
      );
      expect(q.tab, SalonValidationState.pending);
      await q.load();
      expect(asked.single, {'state': 'pending', 'page': '1', 'pageSize': '50'});
      expect(q.total, 120);
      expect(q.items, hasLength(1));
      expect(q.hasPrev, isFalse);
      expect(q.hasNext, isTrue);

      q.nextPage();
      await pumpEventQueue();
      expect(asked.last['page'], '2');
      expect(q.hasPrev, isTrue);
      expect(q.hasNext, isTrue);

      q.nextPage();
      await pumpEventQueue();
      expect(asked.last['page'], '3');
      expect(q.hasNext, isFalse, reason: '3 × 50 ≥ 120');
      q.nextPage();
      await pumpEventQueue();
      expect(asked, hasLength(3), reason: 'no page 4');

      q.prevPage();
      await pumpEventQueue();
      expect(asked.last['page'], '2');
    });

    test('a tab starts at page 1, and only its own answer lands', () async {
      final pending = Completer<http.Response>();
      final q = AdminSalonValidationsProvider(
        service: svc(
          MockClient((req) {
            final state = req.url.queryParameters['state'];
            if (state == 'pending') return pending.future;
            return Future.value(
              json(
                queuePage(
                  total: 3,
                  items: [queueItem(id: 'provider_9', state: state!)],
                ),
              ),
            );
          }),
        ),
      );
      unawaited(q.load());
      q.setTab(SalonValidationState.refused);
      await pumpEventQueue();
      expect(q.tab, SalonValidationState.refused);
      expect(q.page, 1);
      expect(q.items.single.providerId, 'provider_9');

      pending.complete(json(queuePage(total: 1)));
      await pumpEventQueue();
      expect(
        q.items.single.providerId,
        'provider_9',
        reason: '« En attente »\'s late answer, under « Refusés »',
      );
      expect(q.total, 3);
    });

    test('the older server: a calm « unavailable », never an error', () async {
      final q = AdminSalonValidationsProvider(
        service: svc(MockClient((_) async => routeNotFound)),
      );
      await q.load();
      expect(q.unavailable, isTrue);
      expect(q.error, isNull);
      expect(q.items, isEmpty);
      expect(q.isLoading, isFalse);
    });

    test('a failure is an error — and not « unavailable »', () async {
      final q = AdminSalonValidationsProvider(
        service: svc(MockClient((_) async => http.Response('{}', 503))),
      );
      await q.load();
      expect(q.unavailable, isFalse);
      expect(q.error, 'Une erreur est survenue.');
    });

    test('after a decision the row leaves its tab at once, with the '
        'total', () async {
      final q = AdminSalonValidationsProvider(
        service: svc(
          MockClient(
            (_) async => json(
              queuePage(
                total: 2,
                items: [
                  queueItem(),
                  queueItem(id: 'provider_2', name: 'Salon Deux'),
                ],
              ),
            ),
          ),
        ),
      );
      await q.load();
      q.applyDecision(
        p1,
        SalonValidation.fromJson(validationJson(state: 'refused')),
      );
      expect(q.items.map((r) => r.providerId), ['provider_2']);
      expect(q.total, 1);

      q.applyDecision(SalonId('provider_404'), null);
      expect(q.items, hasLength(1), reason: 'not on this page: nothing');
    });

    test('« Validation à terminer » finished under « Validés » stays, '
        'updated', () async {
      final q = AdminSalonValidationsProvider(
        service: svc(
          MockClient(
            (_) async => json(queuePage(items: [queueItem(state: 'approved')])),
          ),
        ),
      );
      q.setTab(SalonValidationState.approved);
      await pumpEventQueue();
      expect(q.items.single.validation.isFinishing, isTrue);
      q.applyDecision(
        p1,
        SalonValidation.fromJson(
          validationJson(state: 'approved', wentLive: true),
        ),
      );
      expect(q.items, hasLength(1));
      expect(q.items.single.validation.wentLive, isTrue);
      expect(q.total, 1);
    });

    test('a page emptied by decisions steps back one page', () async {
      final asked = <String>[];
      final q = AdminSalonValidationsProvider(
        service: svc(
          MockClient((req) async {
            final page = req.url.queryParameters['page']!;
            asked.add(page);
            return json(
              queuePage(
                total: 51,
                page: int.parse(page),
                items: [if (page == '2') queueItem() else queueItem(id: 'x')],
              ),
            );
          }),
        ),
      );
      await q.load();
      q.nextPage();
      await pumpEventQueue();
      expect(q.page, 2);
      q.applyDecision(p1, null);
      await pumpEventQueue();
      expect(q.page, 1);
      expect(asked, ['1', '2', '1']);
    });
  });

  group('AdminSalonValidationDetailProvider — the request', () {
    // docs/design/hygiene-batch9.md §14 (B9.8): the provider is app-wide and
    // outlives the screen — the way to B must never show A, nor act on it.
    test('the way to B drops A; a late answer for A is nobody\'s', () async {
      final a = Completer<http.Response>();
      final b = Completer<http.Response>();
      var firstA = true;
      final p = AdminSalonValidationDetailProvider(
        service: svc(
          MockClient((req) {
            if (req.url.path == '/admin/salons/a/validation') {
              if (firstA) {
                firstA = false;
                return Future.value(json(detailJson(id: 'a', name: 'A')));
              }
              return a.future;
            }
            return b.future;
          }),
        ),
      );
      await p.load(SalonId('a'));
      expect(p.detail?.salon.name, 'A');

      unawaited(p.load(SalonId('a')));
      unawaited(p.load(SalonId('b')));
      expect(p.id, 'b');
      expect(p.detail, isNull, reason: 'A, on B\'s screen');
      expect(await p.approve(SalonId('a')), isFalse, reason: 'not B\'s id');

      a.complete(json(detailJson(id: 'a', name: 'A')));
      await pumpEventQueue();
      expect(p.detail, isNull, reason: 'A\'s late answer, written under B');

      b.complete(http.Response('{}', 503));
      await pumpEventQueue();
      expect(p.detail, isNull);
      expect(p.error, isNotNull, reason: 'a failed B is an error, not A');
    });

    test('the older server: « unavailable », not an error', () async {
      final p = AdminSalonValidationDetailProvider(
        service: svc(MockClient((_) async => routeNotFound)),
      );
      await p.load(p1);
      expect(p.unavailable, isTrue);
      expect(p.error, isNull);
    });

    test('an unknown salon is « Introuvable. »', () async {
      final p = AdminSalonValidationDetailProvider(
        service: svc(
          MockClient((_) async => json({'error': 'not_found'}, 404)),
        ),
      );
      await p.load(p1);
      expect(p.unavailable, isFalse);
      expect(p.error, 'Introuvable.');
    });

    /// One console: the queue (on « En attente »), the count and the detail,
    /// over one server whose answers [route] decides.
    Future<
      ({
        AdminSalonValidationsProvider queue,
        AdminSalonValidationCountProvider count,
        AdminSalonValidationDetailProvider detail,
        List<String> asked,
      })
    >
    console(Future<http.Response> Function(http.Request req) route) async {
      final asked = <String>[];
      final service = svc(
        MockClient((req) {
          asked.add('${req.method} ${req.url.path}?${req.url.query}');
          return route(req);
        }),
      );
      final queue = AdminSalonValidationsProvider(service: service);
      final count = AdminSalonValidationCountProvider(service: service);
      final detail = AdminSalonValidationDetailProvider(
        service: service,
        queue: queue,
        count: count,
      );
      await queue.load();
      await count.load();
      await detail.load(p1);
      asked.clear();
      return (queue: queue, count: count, detail: detail, asked: asked);
    }

    test('« Valider »: sends the state it READ; the row leaves at once, the '
        'count and the detail re-read', () async {
      var decided = false;
      Object? sent;
      final c = await console((req) async {
        if (req.method == 'POST') {
          sent = jsonDecode(req.body);
          decided = true;
          return json({
            'salonStatus': 'active',
            'validation': validationJson(state: 'approved', wentLive: true),
          });
        }
        if (req.url.path == '/admin/salon-validations') {
          final one = req.url.queryParameters['pageSize'] == '1';
          return json(
            queuePage(total: decided ? 0 : 1, items: one ? [] : null),
          );
        }
        return json(
          detailJson(
            salonStatus: decided ? 'active' : 'draft',
            validation: decided
                ? validationJson(state: 'approved', wentLive: true)
                : null,
          ),
        );
      });
      expect(c.count.count, 1);
      expect(c.queue.items, hasLength(1));

      expect(await c.detail.approve(p1), isTrue);
      expect(sent, {'from': 'pending'});
      expect(c.queue.items, isEmpty, reason: 'the row leaves at once');
      expect(c.queue.total, 0);
      expect(c.detail.detail!.validation!.state, SalonValidationState.approved);
      expect(c.detail.detail!.salon.status, 'active');
      expect(c.detail.actionError, isNull);
      await pumpEventQueue();
      expect(c.count.count, 0);
      expect(c.asked, [
        'POST /admin/salons/provider_1/validation/approve?',
        'GET /admin/salon-validations?state=pending&pageSize=1',
        'GET /admin/salons/provider_1/validation?',
      ]);
    });

    test('a 409 after the decision was written: the sentence in the bar, '
        'and the detail, the queue and the count all re-read — the request '
        'now reads « Validation à terminer »', () async {
      var decided = false;
      final c = await console((req) async {
        if (req.method == 'POST') {
          decided = true; // step 2 won, the going-live did not
          return json({
            'error': 'incomplete',
            'missing': ['offer'],
          }, 409);
        }
        if (req.url.path == '/admin/salon-validations') {
          return json(queuePage(total: decided ? 0 : 1));
        }
        return json(
          detailJson(
            validation: decided
                ? validationJson(
                    state: 'approved',
                    decidedAt: '2026-11-12T10:00:00.000Z',
                  )
                : null,
          ),
        );
      });
      expect(await c.detail.approve(p1), isFalse);
      expect(c.detail.actionCode, 'incomplete');
      expect(c.detail.actionMissing, ['offer']);
      expect(
        c.detail.actionError,
        'L’offre du salon n’est plus active : marquez-la payée, puis validez.',
      );
      await pumpEventQueue();
      expect(c.detail.detail!.isFinishing, isTrue);
      expect(c.detail.detail!.approveFrom, SalonValidationState.approved);
      expect(c.detail.actionError, isNotNull, reason: 'the bar keeps it');
      expect(c.count.count, 0);
      expect(
        c.asked,
        containsAll(<String>[
          'GET /admin/salons/provider_1/validation?',
          'GET /admin/salon-validations?state=pending&page=1&pageSize=50',
          'GET /admin/salon-validations?state=pending&pageSize=1',
        ]),
      );
    });

    test('« Validation à terminer » sends `from: approved`', () async {
      Object? sent;
      final c = await console((req) async {
        if (req.method == 'POST') {
          sent = jsonDecode(req.body);
          return json({'salonStatus': 'active', 'validation': null});
        }
        if (req.url.path == '/admin/salon-validations') {
          return json(queuePage());
        }
        return json(detailJson(validation: validationJson(state: 'approved')));
      });
      expect(c.detail.detail!.isFinishing, isTrue);
      expect(await c.detail.approve(p1), isTrue);
      expect(sent, {'from': 'approved'});
    });

    test('nothing to validate — a suspended salon, never asked, already '
        'live — sends nothing', () async {
      for (final d in [
        detailJson(salonStatus: 'suspended'),
        detailJson(neverAsked: true),
        detailJson(
          validation: validationJson(state: 'approved', wentLive: true),
        ),
      ]) {
        final c = await console((req) async {
          if (req.url.path == '/admin/salon-validations') {
            return json(queuePage());
          }
          return json(d);
        });
        expect(await c.detail.approve(p1), isFalse);
        expect(c.asked, isEmpty);
      }
    });

    test('« Refuser » only a pending request', () async {
      final c = await console((req) async {
        if (req.url.path == '/admin/salon-validations') {
          return json(queuePage());
        }
        return json(
          detailJson(
            validation: validationJson(
              state: 'refused',
              refusal: {'code': 'photos', 'final': false},
            ),
          ),
        );
      });
      expect(c.detail.detail!.canRefuse, isFalse);
      expect(await c.detail.refuse(p1, code: 'photos'), isFalse);
      expect(c.asked, isEmpty);
    });

    test('the note is capped in CODE POINTS of the trimmed note, as the '
        'server counts it — not UTF-16 units, not graphemes', () async {
      Object? sent;
      final c = await console((req) async {
        if (req.method == 'POST') {
          sent = jsonDecode(req.body);
          return json({
            'validation': validationJson(
              state: 'refused',
              refusal: {'code': 'other', 'final': false},
            ),
          });
        }
        if (req.url.path == '/admin/salon-validations') {
          return json(queuePage());
        }
        return json(detailJson());
      });
      // 👍🏽 is one grapheme, two code points, four UTF-16 units.
      final at500 = '  ${'👍🏽' * 250}  ';
      expect(at500.trim().length, 1000);
      expect(refusalNoteLength(at500), 500);
      expect(await c.detail.refuse(p1, code: 'other', note: at500), isTrue);
      expect(sent, {'code': 'other', 'note': at500.trim()});
    });

    test('a refusal the server would refuse is refused here first, on the '
        'field, and nothing is sent', () async {
      final c = await console((req) async {
        if (req.url.path == '/admin/salon-validations') {
          return json(queuePage());
        }
        return json(detailJson());
      });
      expect(await c.detail.refuse(p1, code: 'other', note: '   '), isFalse);
      expect(c.detail.actionCode, 'note_required');
      expect(
        c.detail.actionError,
        'Une note est obligatoire pour le motif « Autre ».',
      );

      expect(
        await c.detail.refuse(p1, code: 'photos', note: 'é' * 501),
        isFalse,
      );
      expect(c.detail.actionCode, 'note_too_long');
      expect(c.detail.actionError, 'La note dépasse 500 caractères.');

      expect(await c.detail.refuse(p1, code: 'nope'), isFalse);
      expect(c.detail.actionCode, 'invalid_input');
      expect(c.asked, isEmpty);
    });

    test('the server\'s own 400 on the note re-reads nothing', () async {
      final c = await console((req) async {
        if (req.method == 'POST') return json({'error': 'note_too_long'}, 400);
        if (req.url.path == '/admin/salon-validations') {
          return json(queuePage());
        }
        return json(detailJson());
      });
      expect(await c.detail.refuse(p1, code: 'photos', note: 'ok'), isFalse);
      expect(c.detail.actionCode, 'note_too_long');
      await pumpEventQueue();
      expect(c.asked, ['POST /admin/salons/provider_1/validation/refuse?']);
    });

    test('« Refuser » succeeds: the row leaves « En attente » at once, the '
        'count re-reads', () async {
      var decided = false;
      final c = await console((req) async {
        if (req.method == 'POST') {
          decided = true;
          return json({
            'validation': validationJson(
              state: 'refused',
              refusal: {'code': 'outside_ci', 'final': true},
            ),
          });
        }
        if (req.url.path == '/admin/salon-validations') {
          return json(queuePage(total: decided ? 0 : 1));
        }
        return json(detailJson());
      });
      expect(await c.detail.refuse(p1, code: 'outside_ci'), isTrue);
      expect(c.queue.items, isEmpty);
      expect(c.detail.detail!.validation!.refusal!.isFinal, isTrue);
      await pumpEventQueue();
      expect(c.count.count, 0);
    });

    test('a decision still out for A does not busy B\'s bar, and blocks a '
        'second one', () async {
      final answer = Completer<http.Response>();
      final p = AdminSalonValidationDetailProvider(
        service: svc(
          MockClient((req) {
            if (req.method == 'POST') return answer.future;
            final id = req.url.pathSegments[2];
            return Future.value(json(detailJson(id: id)));
          }),
        ),
      );
      await p.load(SalonId('a'));
      final first = p.approve(SalonId('a'));
      expect(p.acting, isTrue);
      await p.load(SalonId('b'));
      expect(p.acting, isFalse, reason: 'B\'s bar');
      expect(await p.approve(SalonId('b')), isFalse, reason: 'one at a time');
      answer.complete(json({'salonStatus': 'active', 'validation': null}));
      expect(await first, isTrue);
      expect(p.detail!.salon.id, 'b', reason: 'A\'s answer never lands on B');
    });
  });

  group('AdminSalonValidationCountProvider — the sidebar\'s count', () {
    test('reads the pending tab\'s total', () async {
      final c = AdminSalonValidationCountProvider(
        service: svc(MockClient((_) async => json(queuePage(total: 4)))),
      );
      await c.load();
      expect(c.count, 4);
    });

    test('silent: the older server, an error, a 2xx it cannot read — no '
        'badge, never an error', () async {
      for (final res in [
        routeNotFound,
        http.Response('{}', 503),
        json({'error': 'forbidden'}, 403),
        json({'items': <Object>[]}),
      ]) {
        var first = true;
        final c = AdminSalonValidationCountProvider(
          service: svc(
            MockClient((_) async {
              if (first) {
                first = false;
                return json(queuePage(total: 2));
              }
              return res;
            }),
          ),
        );
        await c.load();
        expect(c.count, 2);
        await c.load();
        expect(c.count, isNull, reason: '${res.statusCode} ${res.body}');
      }
    });

    test('loads at sign-in — a restored session, a login — and clears at '
        'sign-out; nothing while signed out', () async {
      var reads = 0;
      final service = svc(
        MockClient((req) async {
          if (req.url.path == '/admin/auth/login') {
            return json({'accessToken': 't2', 'refreshToken': 'r2'});
          }
          reads++;
          return json(queuePage(total: 3));
        }),
      );
      final auth = AdminAuthProvider(service: service);
      final c = AdminSalonValidationCountProvider(service: service, auth: auth);
      await c.load();
      expect(reads, 0, reason: 'still restoring: not signed in');

      await auth.restore();
      await pumpEventQueue();
      expect(reads, 1);
      expect(c.count, 3);

      await auth.logout();
      expect(c.count, isNull);
      await c.load();
      expect(reads, 1, reason: 'signed out');

      expect(await auth.login('a@myweli.com', 'pw'), isTrue);
      await pumpEventQueue();
      expect(reads, 2);
      expect(c.count, 3);
      c.dispose();
    });

    test('an answer that lands after the sign-out is dropped', () async {
      final late = Completer<http.Response>();
      final service = svc(MockClient((_) => late.future));
      final auth = AdminAuthProvider(service: service);
      final c = AdminSalonValidationCountProvider(service: service, auth: auth);
      await auth.restore();
      await auth.logout();
      late.complete(json(queuePage(total: 9)));
      await pumpEventQueue();
      expect(c.count, isNull);
    });
  });

  group('« Lever la suspension » — two servers (§9.2)', () {
    Map<String, dynamic> salonRow(String status) => {
      'id': 'provider_1',
      'name': 'Beauté Divine',
      'status': status,
    };

    test('the list takes only the returned status — never a `reason` key; '
        'the count re-reads', () async {
      for (final (answer, status, live, legacy) in [
        (
          {'status': 'draft', 'reason': 'offer_not_live'},
          'draft',
          false,
          false,
        ),
        ({'status': 'active', 'reason': null}, 'active', true, false),
        (salonRow('active'), 'active', true, true),
      ]) {
        var countReads = 0;
        final service = svc(
          MockClient((req) async {
            if (req.url.path == '/admin/providers') {
              return json({
                'items': [salonRow('suspended')],
                'total': 1,
              });
            }
            if (req.url.path == '/admin/salon-validations') {
              countReads++;
              return json(queuePage(total: 1));
            }
            return json(answer);
          }),
        );
        final count = AdminSalonValidationCountProvider(service: service);
        final list = AdminProvidersProvider(
          service: service,
          validationCount: count,
        );
        await list.load();
        expect(await list.restore(p1), isTrue);
        final row = list.items.single;
        expect(row['status'], status);
        expect(row.containsKey('reason'), isFalse);
        expect(row['name'], 'Beauté Divine');
        expect(list.lastRestore!.isLive, live);
        expect(list.lastRestore!.legacy, legacy);
        await pumpEventQueue();
        expect(countReads, 1);
      }
    });

    test('the detail takes only the returned status; a 409 not_suspended '
        'is worded and leaves no outcome behind', () async {
      var answer = json({'status': 'draft', 'reason': 'unknown_prior'});
      final p = AdminProviderDetailProvider(
        service: svc(
          MockClient((req) async {
            if (req.method == 'GET') return json(salonRow('suspended'));
            return answer;
          }),
        ),
      );
      await p.load(p1);
      expect(await p.restore(p1), isTrue);
      expect(p.provider!['status'], 'draft');
      expect(p.provider!.containsKey('reason'), isFalse);
      expect(p.lastRestore!.reason, 'unknown_prior');

      answer = json({'error': 'not_suspended'}, 409);
      expect(await p.restore(p1), isFalse);
      expect(p.actionError, 'Ce salon n’est pas suspendu.');
      expect(p.lastRestore, isNull);
    });

    test('a suspension re-reads the count too', () async {
      var countReads = 0;
      final service = svc(
        MockClient((req) async {
          if (req.url.path == '/admin/salon-validations') {
            countReads++;
            return json(queuePage());
          }
          if (req.method == 'GET') return json(salonRow('active'));
          return json(salonRow('suspended'));
        }),
      );
      final p = AdminProviderDetailProvider(
        service: service,
        validationCount: AdminSalonValidationCountProvider(service: service),
      );
      await p.load(p1);
      expect(await p.suspend(p1, 'raison'), isTrue);
      await pumpEventQueue();
      expect(countReads, 1);
    });
  });

  group('the dashboard\'s « Salons à valider » (§4.1)', () {
    Future<AdminDashboardProvider> dashboard(Map<String, dynamic> p) async {
      final d = AdminDashboardProvider(
        service: svc(MockClient((_) async => json({'providers': p}))),
      );
      await d.load();
      return d;
    }

    test('the overview\'s pendingValidation', () async {
      final d = await dashboard({
        'active': 3,
        'suspended': 0,
        'pendingValidation': 5,
      });
      expect(d.pendingValidation, 5);
    });

    test('absent on the older server: null — never a claimed « 0 »', () async {
      final d = await dashboard({'active': 3, 'suspended': 0});
      expect(d.pendingValidation, isNull);
    });
  });
}
