import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myweli/core/auth/open_sign_in.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/core/utils/app_clock.dart';
import 'package:myweli/core/utils/salon_id.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/provider.dart' as models;
import 'package:myweli/models/user.dart';
import 'package:myweli/providers/auth_provider.dart';
import 'package:myweli/providers/favorites_provider.dart';
import 'package:myweli/screens/auth/login_screen.dart';
import 'package:myweli/services/interfaces/favorites_service_interface.dart';
import 'package:myweli/services/mock/mock_auth_service.dart';
import 'package:myweli/services/mock/mock_data.dart';
import 'package:myweli/widgets/provider/heart_after_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_app.dart';

/// consumer-signin-push.md §2.1–§2.2, §2.8 (decisions 204–206): the sign-in
/// opens OVER the screen the person is on, « Fermer » returns them there, and
/// a heart tapped before signing in is applied after.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final auth = _Auth();
  final favorites = _Favorites();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    serviceLocator.authService = auth;
    serviceLocator.favoritesService = favorites;
  });
  setUp(() {
    auth.reset();
    favorites.reset();
  });
  tearDown(SignInGate.reset);

  final salon = MockData.providers[1];

  /// Accueil stands in for any screen: it counts its own builds of State, so
  /// a test can prove it was NOT rebuilt from scratch (the sign-in was over
  /// it, not instead of it).
  late GoRouter router;
  late AuthProvider authProvider;
  late FavoritesProvider favoritesProvider;
  final answers = <bool>[];

  Widget app({String initial = '/home'}) {
    answers.clear();
    authProvider = AuthProvider();
    favoritesProvider = FavoritesProvider();
    router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(
          path: '/home',
          builder: (context, _) => _Home(
            onOpen: (reason) async =>
                answers.add(await openSignIn(router, reason: reason)),
            onHeart: () => heartAfterSignIn(
              router: router,
              messenger: ScaffoldMessenger.of(context),
              auth: authProvider,
              favorites: favoritesProvider,
              salonId: salon.id,
            ),
          ),
        ),
        GoRoute(
          path: '/bookings',
          builder: (_, _) => const Scaffold(body: Text('BOOKINGS')),
        ),
        GoRoute(
          path: '/detail',
          builder: (_, _) => const Scaffold(body: Text('DETAIL')),
        ),
        GoRoute(
          path: '/login',
          builder: (_, state) => LoginScreen(
            returnTo: state.uri.queryParameters['returnTo'],
            reason: SignInReason.fromKey(state.uri.queryParameters['reason']),
          ),
        ),
      ],
    );
    return wrapApp(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: favoritesProvider),
      ],
      routerConfig: router,
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> open(WidgetTester tester, [String label = 'open']) async {
    await tester.tap(find.text(label));
    await settle(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
  }

  testWidgets('« Fermer » returns to the screen beneath, which was never '
      'rebuilt, and the opener hears « not signed in »', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    expect(_Home.inits, 1);

    await open(tester);
    expect(find.byTooltip('Fermer'), findsOneWidget);
    // Beneath, still mounted: the sign-in is over it.
    expect(find.text('ACCUEIL', skipOffstage: false), findsOneWidget);

    await tester.tap(find.byTooltip('Fermer'));
    await settle(tester);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('ACCUEIL'), findsOneWidget);
    expect(_Home.inits, 1, reason: 'the same State: not rebuilt');
    expect(answers, [false]);
    expect(SignInGate.isOpen.value, isFalse);
  });

  testWidgets('a sign-in closed with « Fermer » never answers the NEXT one: '
      'its dispose comes after its exit animation, while taps already reach '
      'the screen beneath (the independent review of A3)', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    await open(tester);
    await tester.tap(find.byTooltip('Fermer'));
    // Mid-animation: the first sign-in is still mounted, the screen beneath
    // takes the tap.
    await tester.pump(const Duration(milliseconds: 50));
    expect(answers, [false]);
    // What a tap on « open » does (the hit test during a pop animation is
    // Flutter's; the race is in when the first screen's dispose runs).
    tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'open'))
        .onPressed!();
    await settle(tester);
    expect(find.byType(LoginScreen), findsOneWidget, reason: 'the second');
    expect(answers, [false], reason: 'the first dispose answered no one');
    expect(SignInGate.isOpen.value, isTrue);

    await tester.tap(find.byTooltip('Fermer'));
    await settle(tester);
    expect(answers, [false, false]);
  });

  testWidgets('« Fermer » is a 48 px target', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    await open(tester);
    // The button's own box: Material pads its 40 px look to a 48 px tap
    // area (`MaterialTapTargetSize.padded`); the tooltip wraps the look.
    final size = tester.getSize(
      find.ancestor(
        of: find.byTooltip('Fermer'),
        matching: find.byType(IconButton),
      ),
    );
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  testWidgets('the system back on the options step closes it too', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await settle(tester);
    await open(tester);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('ACCUEIL'), findsOneWidget);
    expect(answers, [false]);
  });

  testWidgets('the reason it opened is written on it', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    await open(tester, 'open heart');
    expect(
      find.text('Connectez-vous pour ajouter ce salon à vos favoris.'),
      findsOneWidget,
    );
    expect(
      find.text('Connectez-vous pour réserver en quelques secondes.'),
      findsNothing,
    );
  });

  testWidgets('on the code step, back returns to the e-mail step; « Fermer » '
      'still leaves', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    await open(tester);
    await tester.enterText(find.byType(TextField).first, 'awa@test.com');
    await tester.tap(find.text('Continuer avec e-mail'));
    await settle(tester);
    expect(find.text('Code à 6 chiffres'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(LoginScreen), findsOneWidget, reason: 'still open');
    expect(find.text('Continuer avec e-mail'), findsOneWidget);

    await tester.tap(find.text('Continuer avec e-mail'));
    await settle(tester);
    await tester.tap(find.byTooltip('Fermer'));
    await settle(tester);
    expect(find.byType(LoginScreen), findsNothing);
    expect(answers, [false]);
  });

  testWidgets(
    'signed in: back on the screen beneath, and the opener hears it',
    (tester) async {
      auth.googleUser = _withPhone;
      await tester.pumpWidget(app());
      await settle(tester);
      await open(tester);
      await tester.tap(find.text('Continuer avec Google'));
      await settle(tester);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.text('ACCUEIL'), findsOneWidget);
      expect(_Home.inits, 1);
      expect(answers, [true]);
      expect(authProvider.isAuthenticated, isTrue);
    },
  );

  testWidgets('« Fermer » waits while a request runs', (tester) async {
    auth.googleUser = _withPhone;
    await tester.pumpWidget(app());
    await settle(tester);
    await open(tester);
    await tester.tap(find.text('Continuer avec Google'));
    await tester.pump(); // the request is under way
    final close = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('Fermer'),
        matching: find.byType(IconButton),
      ),
    );
    expect(close.onPressed, isNull);
    await settle(tester);
  });

  group('the phone step (decision 206)', () {
    testWidgets('it says what « Fermer » does, and « Fermer » signs out', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await settle(tester);
      await open(tester);
      await tester.tap(find.text('Continuer avec Google')); // no phone yet
      await settle(tester);
      expect(find.text('Votre numéro de téléphone'), findsOneWidget);
      expect(
        find.text('Sans numéro, la connexion est annulée.'),
        findsOneWidget,
      );
      expect(authProvider.isAuthenticated, isTrue);

      await tester.tap(find.byTooltip('Fermer'));
      await settle(tester);
      expect(authProvider.isAuthenticated, isFalse);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.text('ACCUEIL'), findsOneWidget);
      expect(find.text('Connexion annulée.'), findsOneWidget);
      expect(answers, [false]);
    });

    testWidgets('a failed sign-out keeps the step, signed in, and says nothing '
        'of a cancellation', (tester) async {
      auth.failLogout = true;
      await tester.pumpWidget(app());
      await settle(tester);
      await open(tester);
      await tester.tap(find.text('Continuer avec Google'));
      await settle(tester);
      await tester.tap(find.byTooltip('Fermer'));
      await settle(tester);
      expect(authProvider.isAuthenticated, isTrue);
      expect(find.text('Votre numéro de téléphone'), findsOneWidget);
      expect(find.text('Connexion annulée.'), findsNothing);
    });

    testWidgets('the system back is « Fermer » there', (tester) async {
      await tester.pumpWidget(app());
      await settle(tester);
      await open(tester);
      await tester.tap(find.text('Continuer avec Google'));
      await settle(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(authProvider.isAuthenticated, isFalse);
      expect(find.byType(LoginScreen), findsNothing);
    });
  });

  group('nothing beneath (§2.1, the one use of returnTo)', () {
    testWidgets('« Fermer » goes to Accueil', (tester) async {
      await tester.pumpWidget(app(initial: '/login?returnTo=/bookings'));
      await settle(tester);
      await tester.tap(find.byTooltip('Fermer'));
      await settle(tester);
      expect(find.text('ACCUEIL'), findsOneWidget);
    });

    testWidgets('success goes to returnTo', (tester) async {
      auth.googleUser = _withPhone;
      await tester.pumpWidget(app(initial: '/login?returnTo=/bookings'));
      await settle(tester);
      await tester.tap(find.text('Continuer avec Google'));
      await settle(tester);
      expect(find.text('BOOKINGS'), findsOneWidget);
    });

    testWidgets('a returnTo that is not an in-app path lands on Accueil', (
      tester,
    ) async {
      auth.googleUser = _withPhone;
      await tester.pumpWidget(
        app(initial: '/login?returnTo=${Uri.encodeComponent('//evil.x')}'),
      );
      await settle(tester);
      await tester.tap(find.text('Continuer avec Google'));
      await settle(tester);
      expect(find.text('ACCUEIL'), findsOneWidget);
    });
  });

  testWidgets('the opener always hears an answer — even when a `go` removes '
      'the sign-in', (tester) async {
    await tester.pumpWidget(app());
    await settle(tester);
    await open(tester);
    router.go('/bookings');
    await settle(tester);
    expect(find.byType(LoginScreen), findsNothing);
    expect(answers, [false]);
    expect(SignInGate.isOpen.value, isFalse);
  });

  testWidgets('what waits for the sign-in to close lands on top of where the '
      'person is, and the success did not close it (§2.2)', (tester) async {
    auth.googleUser = _withPhone;
    await tester.pumpWidget(app());
    await settle(tester);
    await open(tester);
    // A notification tap while the sign-in is open (main.dart's `navigate`).
    unawaited(SignInGate.whenClosed().then((_) => router.push('/detail')));
    await tester.tap(find.text('Continuer avec Google'));
    await settle(tester);
    expect(find.text('DETAIL'), findsOneWidget);
    router.pop();
    await settle(tester);
    expect(find.text('ACCUEIL'), findsOneWidget, reason: 'beneath it: Accueil');
    expect(find.byType(LoginScreen), findsNothing);
  });

  group('a heart tapped before signing in (§2.8, decision 205)', () {
    testWidgets('added after the sign-in, with « Annuler »', (tester) async {
      auth.googleUser = _withPhone;
      favorites.stored = [MockData.providers[0]];
      await tester.pumpWidget(app());
      await settle(tester);
      await open(tester, 'heart');
      expect(
        find.text('Connectez-vous pour ajouter ce salon à vos favoris.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Continuer avec Google'));
      await settle(tester);
      expect(favorites.adds, [salon.id]);
      expect(favoritesProvider.isFavorite(salon.id), isTrue);
      expect(find.text('Ajouté aux favoris'), findsOneWidget);
      expect(find.text('Annuler'), findsOneWidget);
    });

    testWidgets('already a favourite: nothing sent, and said', (tester) async {
      auth.googleUser = _withPhone;
      favorites.stored = [salon];
      await tester.pumpWidget(app());
      await settle(tester);
      await open(tester, 'heart');
      await tester.tap(find.text('Continuer avec Google'));
      await settle(tester);
      expect(favorites.adds, isEmpty);
      expect(favorites.removes, isEmpty);
      expect(favoritesProvider.isFavorite(salon.id), isTrue);
      expect(find.text('Déjà dans vos favoris'), findsOneWidget);
    });

    testWidgets('the add fails: its sentence, the heart empty', (tester) async {
      auth.googleUser = _withPhone;
      favorites.failAdd = true;
      await tester.pumpWidget(app());
      await settle(tester);
      await open(tester, 'heart');
      await tester.tap(find.text('Continuer avec Google'));
      await settle(tester);
      expect(favoritesProvider.isFavorite(salon.id), isFalse);
      expect(find.text('Une erreur est survenue. Réessayez.'), findsOneWidget);
    });

    testWidgets('closed: nothing added, nothing said', (tester) async {
      await tester.pumpWidget(app());
      await settle(tester);
      await open(tester, 'heart');
      await tester.tap(find.byTooltip('Fermer'));
      await settle(tester);
      expect(favorites.adds, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}

final _withPhone = User(
  id: 'u-phone',
  email: 'awa@test.com',
  phoneNumber: '+2250700000001',
  authProvider: 'google',
  createdAt: AppClock.now(),
);

class _Home extends StatefulWidget {
  const _Home({required this.onOpen, required this.onHeart});

  final Future<void> Function(SignInReason) onOpen;
  final Future<void> Function() onHeart;

  static int inits = 0;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  @override
  void initState() {
    super.initState();
    _Home.inits++;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        const Text('ACCUEIL'),
        TextButton(
          onPressed: () => widget.onOpen(SignInReason.none),
          child: const Text('open'),
        ),
        TextButton(
          onPressed: () => widget.onOpen(SignInReason.heart),
          child: const Text('open heart'),
        ),
        TextButton(onPressed: widget.onHeart, child: const Text('heart')),
      ],
    ),
  );
}

class _Auth extends MockAuthService {
  User? googleUser;
  bool failLogout = false;

  void reset() {
    googleUser = null;
    failLogout = false;
    _Home.inits = 0;
  }

  @override
  Future<ApiResponse<User>> signInWithGoogle() async {
    final u = googleUser;
    if (u == null) return super.signInWithGoogle();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return ApiResponse.success(u);
  }

  @override
  Future<void> logout() async {
    if (failLogout) throw StateError('offline');
    await super.logout();
  }
}

class _Favorites implements FavoritesServiceInterface {
  List<models.Provider> stored = [];
  bool failAdd = false;
  final adds = <SalonId>[];
  final removes = <SalonId>[];

  void reset() {
    stored = [];
    failAdd = false;
    adds.clear();
    removes.clear();
  }

  @override
  Future<ApiResponse<List<models.Provider>>> getFavoriteProviders(
    String userId,
  ) async => ApiResponse.success(List.of(stored));

  @override
  Future<ApiResponse<bool>> addFavorite(String userId, SalonId id) async {
    if (failAdd) throw StateError('offline');
    adds.add(id);
    return ApiResponse.success(true);
  }

  @override
  Future<ApiResponse<bool>> removeFavorite(String userId, SalonId id) async {
    removes.add(id);
    return ApiResponse.success(true);
  }

  @override
  Future<ApiResponse<List<SalonId>>> getFavoriteProviderIds(
    String userId,
  ) async => ApiResponse.success([for (final p in stored) p.id]);

  @override
  Future<ApiResponse<bool>> isFavorite(String userId, SalonId id) async =>
      ApiResponse.success(stored.any((p) => p.id == id));
}
