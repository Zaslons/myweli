import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/push/push_registration.dart';
import 'package:myweli/core/theme/app_theme.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/artist.dart';
import 'package:myweli/models/salon_client.dart';
import 'package:myweli/models/service.dart';
import 'package:myweli/providers/pro_auth_provider.dart';
import 'package:myweli/screens/provider/profile/pro_data_export_screen.dart';
import 'package:myweli/services/interfaces/pro_service_interface.dart';
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

/// The salon read and the two catalogue reads, each able to fail. Canned
/// answers (one service, one booking) so a section that fails can never be
/// mistaken for a salon that has nothing.
class _Pro extends MockProService {
  bool failSalon = false;
  bool failServices = false;
  bool failAppointments = false;
  final servicesAsked = <String>[];

  void reset() {
    failSalon = false;
    failServices = false;
    failAppointments = false;
    servicesAsked.clear();
  }

  @override
  Future<ApiResponse<MyProviderInfo>> getMyProvider({String? salonId}) async {
    if (failSalon) return ApiResponse.error('Erreur');
    return super.getMyProvider(salonId: salonId);
  }

  @override
  Future<ApiResponse<List<Service>>> getProviderServices(
    String providerId,
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
    String providerId, {
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

class _Artists extends MockProArtistService {
  bool fail = false;
  final asked = <String>[];

  void reset() {
    fail = false;
    asked.clear();
  }

  @override
  Future<ApiResponse<List<Artist>>> getArtists(String providerId) async {
    asked.add(providerId);
    if (fail) return ApiResponse.error('Erreur');
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

  final asked = <({String salon, int page, int? pageSize})>[];

  void reset() {
    size = 3;
    failPage = null;
    throwOnFail = false;
    totalOf = null;
    maxPageSize = 50;
    echoPageSize = true;
    asked.clear();
  }

  @override
  Future<ApiResponse<SalonClientsPage>> listClients(
    String providerId, {
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
    String? switchTo,
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
    };
    for (final MapEntry(key: section, value: fail) in cases.entries) {
      testWidgets(section, (tester) async {
        await pumpExport(tester, arrange: fail);
        expectRefused(section);
        expect(copied, isNull);
      }, variant: bothPlatforms);
    }
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

  // SYSTEM.md §13.3: the longest refusal (all five sections) at 200 % on a
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
          ..failAppointments = true;
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
      'la fiche du salon, les services, l’équipe, les rendez-vous et le '
      'fichier clients',
    );
    await tester.ensureVisible(find.text('Réessayer'));
    await tester.pump();
    final retry = tester.getRect(find.text('Réessayer'));
    expect(retry.bottom, lessThanOrEqualTo(780));
  });

  testWidgets('after a switch, every read is for the switched-to salon (R6)', (
    tester,
  ) async {
    await pumpExport(tester, switchTo: 'provider2');

    final export = await copyExport(tester);
    expect((export['salon'] as Map)['id'], 'provider2');
    expect(pro.servicesAsked, ['provider2']);
    expect(artists.asked, ['provider2']);
    expect(clients.asked.map((a) => a.salon).toSet(), {'provider2'});
  });
}
