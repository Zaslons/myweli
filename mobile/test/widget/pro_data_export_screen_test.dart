import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/core/utils/formatters.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/artist.dart';
import 'package:myweli/models/salon_client.dart';
import 'package:myweli/models/service.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/screens/provider/profile/pro_data_export_screen.dart';
import 'package:myweli/services/api/api_pro_artist_service.dart';
import 'package:myweli/services/api/api_pro_clients_service.dart';
import 'package:myweli/services/api/api_pro_service.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
import 'package:myweli/services/interfaces/session_store.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/services/mock/mock_device_registration_service.dart';
import 'package:myweli/services/mock/mock_pro_artist_service.dart';
import 'package:myweli/services/mock/mock_pro_clients_service.dart';
import 'package:myweli/services/mock/mock_pro_service.dart';
import 'package:myweli/services/mock/mock_pro_team_service.dart';
import 'package:myweli/services/mock/mock_push_notification_service.dart';
import 'package:myweli/services/mock/mock_subscription_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fonts.dart';
import '../support/pump_app.dart';
import '../support/settle.dart';
import '../support/sign_in.dart';
import '../support/surface.dart';

/// A pro session for the REAL services below — they only need its token.
InMemorySessionStore _proSession() =>
    InMemorySessionStore()
      ..save(jsonEncode({'token': 'tok', 'refreshToken': 'r1'}));

/// An HTTP client whose every request answers [body] with a 200 — so the
/// REAL service parses it, which the canned answers skip.
MockClient _answering(Object body) =>
    MockClient((_) async => http.Response(jsonEncode(body), 200));

/// The salon read and the two catalogue reads, each able to fail. Canned
/// answers (one service, one booking) so a section that fails can never be
/// mistaken for a salon that has nothing.
class _Pro extends MockProService {
  bool failSalon = false;
  bool failServices = false;
  bool failAppointments = false;
  bool failEarnings = false;

  /// The 200 body the earnings read answers, through the REAL
  /// `ApiProService` parse; null = the canned earnings.
  Map<String, dynamic>? earningsWire;
  final servicesAsked = <String>[];

  /// The earnings reads, with their range — the export asks for all of it.
  final earningsAsked = <({String salon, DateTime? from, DateTime? to})>[];

  void reset() {
    failSalon = false;
    failServices = false;
    failAppointments = false;
    failEarnings = false;
    earningsWire = null;
    servicesAsked.clear();
    earningsAsked.clear();
  }

  @override
  Future<ApiResponse<EarningsData>> getEarnings(
    SalonId providerId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    earningsAsked.add((salon: providerId, from: startDate, to: endDate));
    if (failEarnings) return ApiResponse.error('Erreur');
    if (earningsWire case final body?) {
      return ApiProService(
        client: _answering(body),
        baseUrl: 'http://x',
        providerSessionStore: _proSession(),
      ).getEarnings(providerId);
    }
    return ApiResponse.success(
      EarningsData(
        totalEarnings: 1250000,
        transactions: [
          for (final id in ['t1', 't2'])
            EarningsTransaction(
              id: id,
              appointmentId: 'rdv-$id',
              amount: 625000,
              date: DateTime.utc(2026, 10, 1),
              status: 'completed',
            ),
        ],
      ),
    );
  }

  @override
  Future<ApiResponse<MyProviderInfo>> getMyProvider({SalonId? salonId}) async {
    if (failSalon) return ApiResponse.error('Erreur');
    return super.getMyProvider(salonId: salonId);
  }

  @override
  Future<ApiResponse<List<Service>>> getProviderServices(
    SalonId providerId,
  ) async {
    servicesAsked.add(providerId);
    if (failServices) return ApiResponse.error('Erreur');
    return ApiResponse.success([
      Service(
        id: 'svc-$providerId',
        name: 'Tresses',
        description: '',
        price: 15000,
        durationMinutes: 120,
        providerId: providerId,
      ),
    ]);
  }

  @override
  Future<ApiResponse<List<Appointment>>> getProviderAppointments(
    SalonId providerId, {
    AppointmentStatus? status,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (failAppointments) return ApiResponse.error('Erreur');
    return ApiResponse.success([
      Appointment(
        id: 'rdv-$providerId',
        userId: 'u1',
        providerId: providerId,
        serviceIds: const ['svc'],
        appointmentDate: DateTime(2026, 10, 1, 10),
        status: AppointmentStatus.completed,
        totalPrice: 15000,
        createdAt: DateTime(2026, 9, 1),
      ),
    ]);
  }
}

/// An artist the export cannot hold: the team read answered, and the file
/// still cannot be made (docs/design/web-client-polish.md §2.3, Q3).
class _UnbuildableArtist extends Artist {
  const _UnbuildableArtist()
    : super(id: 'x', name: 'x', providerId: const SalonId('p'));

  @override
  String get name => throw StateError('an artist the file cannot hold');
}

class _Artists extends MockProArtistService {
  bool fail = false;

  /// The team answers with an artist the file cannot hold.
  bool unbuildable = false;

  /// The 200 body the team read answers, through the REAL
  /// `ApiProArtistService` parse; null = the canned team.
  Map<String, dynamic>? wire;
  final asked = <String>[];

  void reset() {
    fail = false;
    unbuildable = false;
    wire = null;
    asked.clear();
  }

  @override
  Future<ApiResponse<List<Artist>>> getArtists(SalonId providerId) async {
    asked.add(providerId);
    if (fail) return ApiResponse.error('Erreur');
    if (unbuildable) return ApiResponse.success([const _UnbuildableArtist()]);
    if (wire case final body?) {
      return ApiProArtistService(
        client: _answering(body),
        baseUrl: 'http://x',
        providerSessionStore: _proSession(),
      ).getArtists(providerId);
    }
    return ApiResponse.success([
      Artist(id: 'art-$providerId', name: 'Awa', providerId: providerId),
    ]);
  }
}

/// A salon of [size] clients, answered like `ClientsService.list`: the size
/// asked, clamped to 1–50 (default 20), echoed on every page.
class _Clients extends MockProClientsService {
  int size = 3;

  /// The page that answers an error — or throws, with [throwOnFail].
  int? failPage;
  bool throwOnFail = false;

  /// The `total` a page reports; null = [size]. A list that moves during
  /// the walk (a client added, a visit re-sorting it).
  int Function(int page)? totalOf;

  /// The server's own page cap — a server whose maximum is below the 50
  /// asked pages with ITS size, and the walk must count pages with it.
  int maxPageSize = 50;

  /// Whether a page echoes its size (the real server always does).
  bool echoPageSize = true;

  /// The 200 body page 1 answers, through the REAL `ApiProClientsService`
  /// parse; null = the canned page.
  Map<String, dynamic>? wirePage1;

  final asked = <({String salon, int page, int? pageSize})>[];

  void reset() {
    size = 3;
    failPage = null;
    throwOnFail = false;
    totalOf = null;
    maxPageSize = 50;
    echoPageSize = true;
    wirePage1 = null;
    asked.clear();
  }

  @override
  Future<ApiResponse<SalonClientsPage>> listClients(
    SalonId providerId, {
    String? query,
    String? tag,
    int page = 1,
    int? pageSize,
  }) async {
    asked.add((salon: providerId, page: page, pageSize: pageSize));
    if (page == failPage) {
      if (throwOnFail) throw const FormatException('not JSON');
      return ApiResponse.error('Erreur');
    }
    if (page == 1 && wirePage1 != null) {
      return ApiProClientsService(
        client: _answering(wirePage1!),
        baseUrl: 'http://x',
        providerSessionStore: _proSession(),
      ).listClients(providerId, page: page, pageSize: pageSize);
    }
    final echo = (pageSize ?? 20).clamp(1, maxPageSize);
    final start = (page - 1) * echo;
    final end = (start + echo).clamp(0, size);
    return ApiResponse.success(
      SalonClientsPage(
        items: [
          for (var i = start; i < end; i++)
            SalonClient(
              id: 'c$i',
              displayName: 'Client $i',
              tags: const [],
              linked: false,
            ),
        ],
        page: page,
        total: totalOf?.call(page) ?? size,
        pageSize: echoPageSize ? echo : null,
      ),
    );
  }
}

const _copyButton = 'Copier mes données (JSON)';

String _refusal(String sections) =>
    'Export interrompu : impossible de charger $sections. '
    'Vérifiez votre connexion et réessayez.';

/// « Mes données » (app Pro) refuses instead of handing over a file with
/// holes: any of its five reads failing — or a client walk that does not
/// add up — shows « Chargement impossible » naming the missing data, and
/// nothing to copy. The client file is walked page by page.
/// Design: docs/design/app-pro-export-completeness.md.
void main() {
  final pro = _Pro();
  final artists = _Artists();
  final clients = _Clients();
  final bothPlatforms = TargetPlatformVariant(const {
    TargetPlatform.android,
    TargetPlatform.iOS,
  });

  setUpAll(() async {
    await loadRealFonts();
    SharedPreferences.setMockInitialValues({});
    // `late final` slots: one assignment for the file, knobs reset per test.
    serviceLocator.authService = MockAuthService();
    serviceLocator.proService = pro;
    serviceLocator.proArtistService = artists;
    serviceLocator.proClientsService = clients;
    serviceLocator.proTeamService = MockProTeamService();
    serviceLocator.subscriptionService = MockSubscriptionService();
    serviceLocator.proPushRegistration = PushRegistration(
      push: MockPushNotificationService(),
      devices: MockDeviceRegistrationService(),
    );
  });

  String? copied;

  setUp(() {
    MockData.resetTeam();
    pro.reset();
    artists.reset();
    clients.reset();
    copied = null;
  });

  /// Captures what the screen writes to the clipboard.
  void captureClipboard(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }

  /// Signs the owner in with every read healthy, THEN applies [arrange] —
  /// the sign-in itself reads the salon — and opens the screen.
  Future<ProAuthProvider> pumpExport(
    WidgetTester tester, {
    void Function()? arrange,
    SalonId? switchTo,
  }) async {
    final auth = await signInPro(tester);
    if (switchTo != null) {
      await tester.runAsync(() async {
        expect(await auth.switchSalon(switchTo), isTrue);
      });
    }
    arrange?.call();
    captureClipboard(tester);
    await tester.pumpWidget(
      wrapApp(
        providers: [ChangeNotifierProvider<ProAuthProvider>.value(value: auth)],
        home: const ProDataExportScreen(),
        // The real font, so a wrap is measured with real glyphs (fonts.dart).
        theme: AppTheme.themeData(fontFamily: kRealFont),
      ),
    );
    await settleMocks(tester, rounds: 4);
    return auth;
  }

  Future<Map<String, dynamic>> copyExport(WidgetTester tester) async {
    await tester.tap(find.text(_copyButton));
    await tester.pump();
    expect(copied, isNotNull, reason: 'nothing reached the clipboard');
    return jsonDecode(copied!) as Map<String, dynamic>;
  }

  void expectRefused(String sections) {
    expect(find.text('Chargement impossible'), findsOneWidget);
    expect(find.text(_refusal(sections)), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    expect(find.text(_copyButton), findsNothing);
  }

  testWidgets(
    'CONTROL: every read answers → every section is filled',
    (tester) async {
      await pumpExport(tester);

      expect(find.text('Chargement impossible'), findsNothing);
      final export = await copyExport(tester);
      expect((export['salon'] as Map)['id'], 'provider1');
      expect(export['services'], hasLength(1));
      expect(export['artists'], hasLength(1));
      expect(export['appointments'], hasLength(1));
      expect(export['clients'], hasLength(3));
      // B7.8: the sixth read, in the web's shape — a total and a COUNT.
      expect(export['earnings'], {'totalEarnings': 1250000, 'transactions': 2});
      expect(pro.earningsAsked.single, (
        salon: 'provider1',
        from: null,
        to: null,
      ), reason: 'the whole period, as the web asks');
      expect(find.text('Revenus'), findsOneWidget);
      expect(
        find.text(Formatters.formatCurrency(1250000)),
        findsOneWidget,
        reason: 'the summary says what the file holds',
      );
    },
    variant: bothPlatforms,
  );

  group('a read that fails refuses the export, naming what is missing', () {
    final cases = <String, void Function()>{
      'la fiche du salon': () => pro.failSalon = true,
      'les services': () => pro.failServices = true,
      'l’équipe': () => artists.fail = true,
      'les rendez-vous': () => pro.failAppointments = true,
      'le fichier clients': () => clients.failPage = 1,
      'les revenus': () => pro.failEarnings = true,
    };
    for (final MapEntry(key: section, value: fail) in cases.entries) {
      testWidgets(section, (tester) async {
        await pumpExport(tester, arrange: fail);
        expectRefused(section);
        expect(copied, isNull);
      }, variant: bothPlatforms);
    }
  });

  // docs/design/export-unreadable-200.md §2: through the REAL parse, a 200
  // that came back without its list is a failed read — never « Équipe 0 » or
  // « Clients 0 » copied as complete. The server always sends the list.
  group('a 200 without its list refuses the export', () {
    testWidgets('the team answers {} → « l’équipe »', (tester) async {
      await pumpExport(tester, arrange: () => artists.wire = {});
      expectRefused('l’équipe');
      expect(copied, isNull);
    });

    final clientPages = <String, Map<String, dynamic>>{
      'only its size': {'pageSize': 50},
      'items null, total 0': {'items': null, 'total': 0, 'pageSize': 50},
      'no total': {'items': <Object>[], 'pageSize': 50},
    };
    for (final MapEntry(key: name, value: body) in clientPages.entries) {
      testWidgets('the client page 1 has $name → « le fichier clients »', (
        tester,
      ) async {
        await pumpExport(tester, arrange: () => clients.wirePage1 = body);
        expectRefused('le fichier clients');
        expect(copied, isNull);
      });
    }

    // B7.8: the earnings read is strict too — `transactions` missing was
    // read as « none », a salon that earned nothing.
    final earningsBodies = <String, Map<String, dynamic>>{
      'no transactions': {'totalEarnings': 5000},
      'no total': {'transactions': <Object>[]},
    };
    for (final MapEntry(key: name, value: body) in earningsBodies.entries) {
      testWidgets('the earnings have $name → « les revenus »', (tester) async {
        await pumpExport(tester, arrange: () => pro.earningsWire = body);
        expectRefused('les revenus');
        expect(copied, isNull);
      });
    }

    testWidgets('CONTROL: the same reads WITH their lists → the copy', (
      tester,
    ) async {
      await pumpExport(
        tester,
        arrange: () {
          artists.wire = {
            'items': [
              {
                'id': 'art-wire',
                'name': 'Awa',
                'providerId': 'provider1',
                'workingHours': <String, Object>{},
              },
            ],
            'page': 1,
            'total': 1,
          };
          clients.wirePage1 = {
            'items': <Object>[],
            'page': 1,
            'pageSize': 50,
            'total': 0,
          };
          pro.earningsWire = {'totalEarnings': 0, 'transactions': <Object>[]};
        },
      );

      expect(find.text('Chargement impossible'), findsNothing);
      final export = await copyExport(tester);
      expect(export['artists'], hasLength(1));
      expect(export['clients'], isEmpty);
      expect(export['earnings'], {'totalEarnings': 0, 'transactions': 0});
    });
  });

  testWidgets('a read that THROWS is one failed section, not a crash', (
    tester,
  ) async {
    await pumpExport(
      tester,
      arrange: () => clients
        ..failPage = 1
        ..throwOnFail = true,
    );
    expectRefused('le fichier clients');
  });

  // docs/design/web-client-polish.md §2.3 (Q3): every read answered and the
  // file could not be made. It used to throw inside `setState` — the loader
  // for ever.
  testWidgets('a file that cannot be built → its own sentence, not a loader '
      'for ever', (tester) async {
    await pumpExport(tester, arrange: () => artists.unbuildable = true);

    expect(find.text('Chargement impossible'), findsOneWidget);
    expect(
      find.text('Le fichier n’a pas pu être préparé. Réessayez.'),
      findsOneWidget,
    );
    expect(find.textContaining('impossible de charger'), findsNothing);
    expect(find.text('Réessayer'), findsOneWidget);
    expect(find.text(_copyButton), findsNothing);
  });

  testWidgets('two failed reads are named in the file’s order', (tester) async {
    await pumpExport(
      tester,
      arrange: () {
        clients.failPage = 1;
        pro.failServices = true;
      },
    );
    expectRefused('les services et le fichier clients');
  });

  testWidgets('« Réessayer » runs every read again', (tester) async {
    await pumpExport(tester, arrange: () => pro.failAppointments = true);
    expectRefused('les rendez-vous');

    pro.failAppointments = false;
    await tester.tap(find.text('Réessayer'));
    await settleMocks(tester, rounds: 4);

    expect(find.text('Chargement impossible'), findsNothing);
    final export = await copyExport(tester);
    expect(export['appointments'], hasLength(1));
  });

  group('the client file is walked page by page', () {
    testWidgets('120 clients over three pages of 50 → all 120', (tester) async {
      await pumpExport(tester, arrange: () => clients.size = 120);

      expect(clients.asked.map((a) => (a.page, a.pageSize)), [
        (1, 50),
        (2, 50),
        (3, 50),
      ]);
      expect(find.text('120'), findsOneWidget);
      final export = await copyExport(tester);
      final names = (export['clients'] as List).map((c) => (c as Map)['name']);
      expect(names, hasLength(120));
      expect(names.toSet(), hasLength(120));
    });

    testWidgets('an empty base is one page and an empty section', (
      tester,
    ) async {
      await pumpExport(tester, arrange: () => clients.size = 0);

      expect(clients.asked, hasLength(1));
      final export = await copyExport(tester);
      expect(export['clients'], isEmpty);
    });

    testWidgets('a total that moves during the walk → refused', (tester) async {
      await pumpExport(
        tester,
        arrange: () => clients
          ..size = 120
          ..totalOf = (page) => page == 1 ? 120 : 121,
      );
      expectRefused('le fichier clients');
    });

    testWidgets('a server that pages smaller than asked → its size counts', (
      tester,
    ) async {
      await pumpExport(
        tester,
        arrange: () => clients
          ..size = 70
          ..maxPageSize = 30,
      );

      expect(clients.asked.map((a) => (a.page, a.pageSize)), [
        (1, 50),
        (2, 30),
        (3, 30),
      ]);
      final export = await copyExport(tester);
      expect(export['clients'], hasLength(70));
    });

    testWidgets('a page without its size echoed → refused, not guessed', (
      tester,
    ) async {
      await pumpExport(tester, arrange: () => clients.echoPageSize = false);
      expectRefused('le fichier clients');
    });

    testWidgets('a page that fails mid-walk → refused', (tester) async {
      await pumpExport(
        tester,
        arrange: () => clients
          ..size = 120
          ..failPage = 2,
      );
      expectRefused('le fichier clients');
    });
  });

  // SYSTEM.md §13.3: the longest refusal (all six sections) at 200 % on a
  // 360dp phone — it wraps and scrolls, and « Réessayer » stays reachable.
  testWidgets('the longest refusal survives 200 % text on 360dp', (
    tester,
  ) async {
    pinSurface(tester, size: const Size(360, 780), scale: 2);
    await pumpExport(
      tester,
      arrange: () {
        pro
          ..failSalon = true
          ..failServices = true
          ..failAppointments = true
          ..failEarnings = true;
        artists.fail = true;
        clients.failPage = 1;
      },
    );
    expect(tester.takeException(), isNull);
    // The scale reached the screen — not a 1× run under a 2× name.
    expect(
      MediaQuery.textScalerOf(tester.element(find.text('Réessayer'))).scale(10),
      20,
    );
    expectRefused(
      'la fiche du salon, les services, l’équipe, les rendez-vous, le '
      'fichier clients et les revenus',
    );
    await tester.ensureVisible(find.text('Réessayer'));
    await tester.pump();
    final retry = tester.getRect(find.text('Réessayer'));
    expect(retry.bottom, lessThanOrEqualTo(780));
  });

  testWidgets('after a switch, every read is for the switched-to salon (R6)', (
    tester,
  ) async {
    await pumpExport(tester, switchTo: SalonId('provider2'));

    final export = await copyExport(tester);
    expect((export['salon'] as Map)['id'], 'provider2');
    expect(pro.servicesAsked, ['provider2']);
    expect(artists.asked, ['provider2']);
    expect(clients.asked.map((a) => a.salon).toSet(), {'provider2'});
    expect(pro.earningsAsked.map((a) => a.salon), ['provider2']);
  });
}
