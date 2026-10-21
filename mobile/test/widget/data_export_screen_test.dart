import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/data_export.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/appointment.dart';
import 'package:myweli/models/provider.dart' as models;
import 'package:myweli/models/user.dart';
import 'package:myweli/providers/appointment_provider.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/providers/provider_provider.dart';
import 'package:myweli/screens/profile/data_export_screen.dart';
import 'package:myweli/services/api/api_favorites_service.dart';
import 'package:myweli/services/interfaces/appointment_service_interface.dart';
import 'package:myweli/services/interfaces/auth_service_interface.dart';
import 'package:myweli/services/interfaces/favorites_service_interface.dart';
import 'package:myweli/services/interfaces/provider_service_interface.dart';
import 'package:myweli/services/interfaces/session_store.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:provider/provider.dart';

import '../support/pump_app.dart';

class _Auth extends Mock implements AuthServiceInterface {}

class _Appointments extends Mock implements AppointmentServiceInterface {}

class _Favorites extends Mock implements FavoritesServiceInterface {}

class _Discovery extends Mock implements ProviderServiceInterface {}

/// The signed-in client, fixed: the screen reads the profile from the
/// session, not from a request.
/// The favourites read answered, and the file still cannot be made from
/// them — a list the export cannot hold (docs/design/web-client-polish.md
/// §2.3, Q3).
class _Unbuildable extends FavoritesProvider {
  @override
  List<models.Provider> get favoriteProviders =>
      throw StateError('a favourite the file cannot hold');
}

class _SignedIn extends AuthProvider {
  _SignedIn(this._signedIn);

  final User _signedIn;

  @override
  User? get user => _signedIn;
}

/// The REAL favourites read, over a `GET /me/favorites` that answers [body]
/// with a 200 — the parse the interface stubs skip.
ApiFavoritesService _favoritesOverWire(Object body) {
  final store = InMemorySessionStore()
    ..save(jsonEncode({'token': 'tok', 'refreshToken': 'r1'}));
  return ApiFavoritesService(
    client: MockClient((_) async => http.Response(jsonEncode(body), 200)),
    baseUrl: 'http://x',
    sessionStore: store,
  );
}

/// « Mes données » refuses instead of offering a copy with holes: a read that
/// fails is never shown or copied as an empty section, the favourites are read
/// fresh with their names, and a refused clipboard says so. Design:
/// docs/design/consumer-export-completeness.md.
void main() {
  final auth = _Auth();
  final appointments = _Appointments();
  final favorites = _Favorites();
  final discovery = _Discovery();

  const tail =
      'Vos données ne sont proposées que complètes : vérifiez votre '
      'connexion et réessayez.';
  const appointmentsFailed = 'Impossible de charger vos rendez-vous. $tail';
  const favoritesFailed = 'Impossible de charger vos favoris. $tail';
  const copyButton = 'Copier mes données (JSON)';

  final client = User(
    id: 'u1',
    name: 'Awa Koné',
    email: 'awa@example.com',
    phoneNumber: '+2250700000012',
    createdAt: DateTime(2025, 5, 1),
  );

  Appointment appt(String id) => Appointment(
    id: id,
    userId: 'u1',
    providerId: 'provider1',
    serviceIds: const ['s1'],
    appointmentDate: DateTime(2026, 9, 1, 10),
    status: AppointmentStatus.completed,
    totalPrice: 15000,
    createdAt: DateTime(2026, 8, 1),
  );

  final salonA = MockData.providers[0];
  final salonB = MockData.providers[1];
  // A salon that stopped: the favourites read still hydrates it (Decision C),
  // the discovery list does not carry it.
  final stopped = MockData.providers[2].copyWith(
    id: 'stopped-salon',
    name: 'Salon Fermé',
    status: 'suspended',
  );

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
    registerFallbackValue(AppointmentStatus.pending);
    registerFallbackValue(ProviderSort.relevance);
    serviceLocator.authService = auth;
    serviceLocator.appointmentService = appointments;
    serviceLocator.favoritesService = favorites;
    serviceLocator.providerService = discovery;
    when(() => auth.getCurrentUser()).thenAnswer((_) async => null);
  });

  void appointmentsAnswer(Future<ApiResponse<List<Appointment>>> Function() a) {
    when(
      () => appointments.getUserAppointments(status: any(named: 'status')),
    ).thenAnswer((_) => a());
  }

  void favoritesAnswer(
    Future<ApiResponse<List<models.Provider>>> Function() a,
  ) {
    when(() => favorites.getFavoriteProviders(any())).thenAnswer((_) => a());
  }

  setUp(() {
    reset(appointments);
    reset(favorites);
    reset(discovery);
    appointmentsAnswer(
      () async => ApiResponse.success([appt('a1'), appt('a2')]),
    );
    favoritesAnswer(() async => ApiResponse.success([salonA, salonB]));
    // The discovery list — the first page, and never the stopped salon.
    when(
      () => discovery.getProviders(
        category: any(named: 'category'),
        searchQuery: any(named: 'searchQuery'),
        commune: any(named: 'commune'),
        sort: any(named: 'sort'),
        availableToday: any(named: 'availableToday'),
      ),
    ).thenAnswer((_) async => ApiResponse.success([salonA, salonB]));
  });

  /// What « Copier » writes, and whether the clipboard refuses.
  String? copied;
  var clipboardRefuses = false;

  Future<FavoritesProvider> pump(
    WidgetTester tester, {
    User? user,
    FavoritesProvider? favoritesState,
  }) async {
    copied = null;
    clipboardRefuses = false;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        if (clipboardRefuses) {
          throw PlatformException(code: 'denied', message: 'refused');
        }
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final favs = favoritesState ?? FavoritesProvider();
    await tester.pumpWidget(
      wrapApp(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(
            value: _SignedIn(user ?? client),
          ),
          ChangeNotifierProvider(create: (_) => AppointmentProvider()),
          ChangeNotifierProvider.value(value: favs),
          ChangeNotifierProvider(create: (_) => ProviderProvider()),
        ],
        home: const DataExportScreen(),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    return favs;
  }

  /// The refusal is the screen's error state: the sentence, a retry, and
  /// nothing to copy.
  void expectRefusal(String sentence) {
    expect(find.text('Chargement impossible'), findsOneWidget);
    expect(find.text(sentence), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    expect(find.text(copyButton), findsNothing);
  }

  Future<Map<String, dynamic>> copyAndRead(WidgetTester tester) async {
    await tester.tap(find.text(copyButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(copied, isNotNull, reason: 'nothing reached the clipboard');
    expect(find.text('Données copiées dans le presse-papiers'), findsOneWidget);
    final doc = jsonDecode(copied!) as Map<String, dynamic>;
    // Let the snack's timer run out before the test ends.
    await tester.pump(const Duration(seconds: 7));
    return doc;
  }

  group('a failed read is refused, never an empty section', () {
    testWidgets('the appointments read fails → « vos rendez-vous »', (
      tester,
    ) async {
      appointmentsAnswer(() async => ApiResponse.error('Erreur serveur'));
      await pump(tester);

      expectRefusal(appointmentsFailed);
    });

    testWidgets('the favourites read fails → « vos favoris »', (tester) async {
      favoritesAnswer(() async => ApiResponse.error('Erreur serveur'));
      await pump(tester);

      expectRefusal(favoritesFailed);
    });

    // docs/design/export-unreadable-200.md §2: the server always sends
    // `providers`, so a 200 without it is a body that did not arrive whole —
    // « vos favoris », never « 0 Favoris » copied as complete.
    for (final MapEntry(key: name, value: body) in {
      '{}': <String, Object?>{},
      'the ids without the salons': <String, Object?>{
        'providerIds': ['provider1'],
      },
    }.entries) {
      testWidgets('the favourites answer a 200 without their list ($name) → '
          '« vos favoris »', (tester) async {
        favoritesAnswer(
          () => _favoritesOverWire(body).getFavoriteProviders('u1'),
        );
        await pump(tester);

        expectRefusal(favoritesFailed);
      });
    }

    testWidgets('CONTROL: the same read WITH its list → the copy', (
      tester,
    ) async {
      favoritesAnswer(
        () => _favoritesOverWire({
          'providerIds': ['p1'],
          'providers': [
            {
              'id': 'p1',
              'name': 'Salon Awa',
              'description': '',
              'address': 'Cocody',
              'imageUrls': <String>[],
              'rating': 4.5,
              'reviewCount': 1,
              'services': <Object>[],
              'availability': {
                'providerId': 'p1',
                'weeklySchedule': <String, Object>{},
                'blockedDates': <String>[],
              },
              'phoneNumber': '+2250700000001',
              'category': 'salon',
            },
          ],
        }).getFavoriteProviders('u1'),
      );
      await pump(tester);
      final doc = await copyAndRead(tester);

      expect(doc['favorites'], ['Salon Awa']);
    });

    testWidgets('the appointments read THROWS → the refusal', (tester) async {
      appointmentsAnswer(() async => throw Exception('socket closed'));
      await pump(tester);

      expectRefusal(appointmentsFailed);
    });

    testWidgets('« Réessayer » reads again, and then offers the copy', (
      tester,
    ) async {
      appointmentsAnswer(() async => ApiResponse.error('Erreur serveur'));
      await pump(tester);
      expectRefusal(appointmentsFailed);

      appointmentsAnswer(
        () async => ApiResponse.success([appt('a1'), appt('a2')]),
      );
      await tester.tap(find.text('Réessayer'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text(copyButton), findsOneWidget);
      expect(find.text('Chargement impossible'), findsNothing);
      expect(find.text('2'), findsNWidgets(2));
    });
  });

  group('the favourites are read, not remembered', () {
    testWidgets('one added on another device since the last read is copied', (
      tester,
    ) async {
      // Earlier in the session the favourites screen loaded one salon…
      final state = FavoritesProvider();
      favoritesAnswer(() async => ApiResponse.success([salonA]));
      await state.loadFavorites('u1');
      expect(state.favoriteProviderIds, [salonA.id]);
      // …and the account now has two (one added on the web).
      favoritesAnswer(() async => ApiResponse.success([salonA, salonB]));

      await pump(tester, favoritesState: state);
      final doc = await copyAndRead(tester);

      expect(doc['favorites'], [salonA.name, salonB.name]);
    });

    testWidgets('a favourite salon that stopped is copied by NAME, not id', (
      tester,
    ) async {
      favoritesAnswer(() async => ApiResponse.success([salonA, stopped]));
      await pump(tester);
      final doc = await copyAndRead(tester);

      expect(doc['favorites'], [salonA.name, 'Salon Fermé']);
    });
  });

  group('the profile line', () {
    testWidgets('an account with no phone (email sign-in) still renders', (
      tester,
    ) async {
      final emailOnly = User(
        id: 'u2',
        name: 'Fatou',
        email: 'fatou@example.com',
        authProvider: 'google',
        createdAt: DateTime(2026, 1, 5),
      );
      await pump(tester, user: emailOnly);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('fatou@example.com'), findsOneWidget);
      expect(find.text(copyButton), findsOneWidget);
    });
  });

  group('the clipboard', () {
    testWidgets('a refused clipboard says so, and never « Données copiées »', (
      tester,
    ) async {
      await pump(tester);
      clipboardRefuses = true;

      await tester.tap(find.text(copyButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(find.text('La copie a échoué. Réessayez.'), findsOneWidget);
      expect(find.text('Données copiées dans le presse-papiers'), findsNothing);
      expect(find.text(copyButton), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
    });
  });

  testWidgets('CONTROL — every read answers: the counts, and a whole copy', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('Rendez-vous'), findsOneWidget);
    expect(find.text('Favoris'), findsOneWidget);
    expect(find.text('2'), findsNWidgets(2));
    final doc = await copyAndRead(tester);

    expect(
      [for (final a in doc['appointments'] as List) (a as Map)['id']],
      ['a1', 'a2'],
    );
    expect(doc['favorites'], [salonA.name, salonB.name]);
  });

  // docs/design/web-client-polish.md §2.3 (Q3): the reads answered and the
  // file could not be made — its own sentence. It used to name both reads,
  // which had worked.
  testWidgets('a file that cannot be built → its own sentence, never the '
      'reads that answered', (tester) async {
    await pump(tester, favoritesState: _Unbuildable());

    expect(find.text('Chargement impossible'), findsOneWidget);
    expect(find.text(kDataExportBuildFailed), findsOneWidget);
    expect(find.textContaining('Impossible de charger'), findsNothing);
    expect(find.text('Réessayer'), findsOneWidget);
    expect(find.text(copyButton), findsNothing);
  });
}
