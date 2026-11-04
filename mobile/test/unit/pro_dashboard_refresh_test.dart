import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/access/pro_salon_scope.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/providers/pro_dashboard_provider.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';

/// « Accueil » (docs/design/app-pro-home-journal-fresh.md §2.2–§2.4, owner
/// decisions 9 and 10): a pull always asks the server — quietly when figures
/// are on screen, and on failure they stay with the reason said once; an error
/// with no figures knows whether nothing answered; a salon switch during a
/// load never shows the other salon's figures.
class _Service extends MockProService {
  /// What each salon's server answers: its « today » count.
  final today = <String, int>{'pA': 2, 'pB': 7};
  int calls = 0;

  /// null = the figures; 'network' = nothing answered; 'error' = a refusal;
  /// 'throw' = an exception escapes the service.
  String? failure;

  /// Per salon: while set, that salon's answers wait for it.
  final gates = <String, Completer<void>>{};

  @override
  Future<ApiResponse<DashboardStats>> getDashboardStats(
    SalonId providerId,
  ) async {
    calls++;
    final failure = this.failure;
    final n = today[providerId] ?? 0;
    final gate = gates[providerId];
    if (gate != null) await gate.future;
    if (failure == 'throw') throw Exception('SocketException');
    if (failure == 'network') {
      return ApiResponse.error('Pas de connexion. Réessayez.', code: 'network');
    }
    if (failure == 'error') return ApiResponse.error('Server exploded: 500');
    return ApiResponse.success(
      DashboardStats(
        todayAppointments: n,
        pendingRequests: n,
        totalAppointments: n,
        todayRevenue: n * 5000,
      ),
    );
  }
}

void main() {
  final service = _Service();

  setUpAll(() {
    serviceLocator.proService = service; // late final — one fake for the file
  });

  setUp(() {
    service
      ..today['pA'] = 2
      ..today['pB'] = 7
      ..calls = 0
      ..failure = null
      ..gates.clear();
    ProSalonScope.clear();
  });

  Future<ProDashboardProvider> loaded(SalonId salon) async {
    final p = ProDashboardProvider();
    addTearDown(p.dispose);
    await p.loadDashboardStats(salon);
    return p;
  }

  group('the pull (refresh)', () {
    test(
      'figures on screen: the server is asked, quietly, and its answer replaces them',
      () async {
        final p = await loaded(SalonId('pA'));
        final loading = <bool>[];
        p.addListener(() => loading.add(p.isLoading));
        service.today['pA'] = 3;
        await p.refresh(SalonId('pA'));
        expect(service.calls, 2);
        expect(p.stats!.todayAppointments, 3);
        expect(loading, everyElement(isFalse), reason: 'no full-screen loader');
        expect(p.takeRefreshFailure(), isNull);
      },
    );

    test(
      'nothing answered: the figures STAY, and « Pas de connexion. Réessayez. » is said once',
      () async {
        final p = await loaded(SalonId('pA'));
        service.failure = 'network';
        await p.refresh(SalonId('pA'));
        expect(p.stats!.todayAppointments, 2);
        expect(p.error, isNull);
        expect(p.takeRefreshFailure(), 'Pas de connexion. Réessayez.');
        expect(p.takeRefreshFailure(), isNull, reason: 'said once');
      },
    );

    test(
      'a refusal or an exception: the figures stay, the generic sentence — never the server’s text',
      () async {
        final p = await loaded(SalonId('pA'));
        for (final f in ['error', 'throw']) {
          service.failure = f;
          await p.refresh(SalonId('pA'));
          expect(p.stats!.todayAppointments, 2, reason: f);
          expect(
            p.takeRefreshFailure(),
            'Une erreur est survenue. Réessayez.',
            reason: f,
          );
        }
      },
    );

    test('no figures yet: an ordinary load, with its loader', () async {
      service.failure = 'network';
      final p = await loaded(SalonId('pA'));
      expect(p.stats, isNull);
      service.failure = null;
      final loading = <bool>[];
      p.addListener(() => loading.add(p.isLoading));
      await p.refresh(SalonId('pA'));
      expect(loading.first, isTrue);
      expect(p.stats!.todayAppointments, 2);
    });

    test(
      'entering « Accueil » again still uses what is loaded — only the pull asks',
      () async {
        final p = await loaded(SalonId('pA'));
        await p.loadDashboardStats(SalonId('pA'));
        expect(service.calls, 1);
        await p.refresh(SalonId('pA'));
        expect(service.calls, 2);
      },
    );
  });

  group('the error state without figures', () {
    test(
      'nothing answered → it knows (« Pas de connexion. Réessayez. » under its title)',
      () async {
        service.failure = 'network';
        final p = await loaded(SalonId('pA'));
        expect(p.stats, isNull);
        expect(p.error, isNotNull);
        expect(p.errorIsOffline, isTrue);
      },
    );

    test(
      'a refusal → not offline (the title alone, never the server’s text)',
      () async {
        service.failure = 'error';
        final p = await loaded(SalonId('pA'));
        expect(p.errorIsOffline, isFalse);
      },
    );
  });

  group('a booking changed elsewhere', () {
    test('its salon’s figures are asked for again, quietly', () async {
      final p = await loaded(SalonId('pA'));
      service.today['pA'] = 1;
      p.bookingChanged(
        const BookingChange(
          appointmentId: 'a1',
          providerId: SalonId('pA'),
          kind: BookingChangeKind.accepted,
        ),
      );
      await pumpEventQueue();
      expect(service.calls, 2);
      expect(p.stats!.todayAppointments, 1);
      expect(p.isLoading, isFalse);
    });

    test('another salon’s: nothing is asked', () async {
      final p = await loaded(SalonId('pA'));
      p.bookingChanged(
        const BookingChange(
          appointmentId: 'a1',
          providerId: SalonId('pB'),
          kind: BookingChangeKind.accepted,
        ),
      );
      await pumpEventQueue();
      expect(service.calls, 1);
    });
  });

  group('a salon switch during a load (B1.3, decision 10)', () {
    test(
      'salon A’s late answer never shows under salon B — and is not kept as B’s',
      () async {
        final p = ProDashboardProvider();
        addTearDown(p.dispose);
        service.gates['pA'] = Completer<void>();
        final first = p.loadDashboardStats(SalonId('pA')); // held
        p.resetForSalonSwitch();
        await p.loadDashboardStats(SalonId('pB'));
        expect(p.stats!.todayAppointments, 7);
        service.gates['pA']!.complete(); // A answers last
        await first;
        expect(
          p.stats!.todayAppointments,
          7,
          reason: 'B’s figures, revenue included',
        );
        expect(p.stats!.todayRevenue, 7 * 5000);
        expect(p.isLoading, isFalse);
        // And entering again keeps B's — the cache never held A's.
        await p.loadDashboardStats(SalonId('pB'));
        expect(p.stats!.todayAppointments, 7);
      },
    );

    test(
      'a switch while B is loading and A answers in between: B’s loader is not lowered by A',
      () async {
        final p = ProDashboardProvider();
        addTearDown(p.dispose);
        service.gates['pA'] = Completer<void>();
        service.gates['pB'] = Completer<void>();
        final a = p.loadDashboardStats(SalonId('pA'));
        p.resetForSalonSwitch();
        final b = p.loadDashboardStats(SalonId('pB'));
        service.gates['pA']!.complete();
        await a;
        expect(p.isLoading, isTrue, reason: 'B is still loading');
        expect(p.stats, isNull);
        service.gates['pB']!.complete();
        await b;
        expect(p.stats!.todayAppointments, 7);
      },
    );
  });
}
