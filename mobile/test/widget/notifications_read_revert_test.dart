import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/theme/colors.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/app_notification.dart';
import 'package:myweli/providers/notifications_provider.dart';
import 'package:myweli/screens/notifications/notifications_screen.dart';
import 'package:myweli/screens/provider/notifications/pro_notifications_screen.dart';
import 'package:myweli/services/interfaces/notification_service_interface.dart';
import 'package:myweli/services/interfaces/push_notification_service_interface.dart';
import 'package:myweli/widgets/notifications/notification_tile.dart';
import 'package:myweli/widgets/notifications/notifications_list.dart';
import 'package:provider/provider.dart';

import '../support/pump_app.dart';

class _MockNotificationService extends Mock
    implements NotificationServiceInterface {}

/// docs/design/app-notifications-read-revert.md — a « marquer comme lu » the
/// server did not take puts back what THIS gesture marked and says why, in
/// both notification centres (consumer + pro share the feed and the action).
void main() {
  const offline = 'Pas de connexion. Réessayez.';
  const generic = 'Une erreur est survenue. Réessayez.';
  const markAll = 'Tout marquer comme lu';

  late _MockNotificationService service;

  setUpAll(() => initializeDateFormatting('fr_FR', null));
  setUp(() => service = _MockNotificationService());

  ApiResponse<bool> noAnswer() => ApiResponse.error(offline, code: 'network');
  ApiResponse<bool> refused() =>
      ApiResponse.error('Erreur', code: 'internal_error');

  AppNotification note(String id, {bool read = false, String? route}) =>
      AppNotification(
        id: id,
        type: AppNotificationType.general,
        title: 'Titre $id',
        body: 'Corps $id',
        createdAt: DateTime(2026, 6, 28),
        read: read,
        route: route,
      );

  /// What each row RENDERS (the tile's own notification), in order.
  Map<String, bool> rendered(WidgetTester tester) => {
    for (final tile in tester.widgetList<NotificationTile>(
      find.byType(NotificationTile),
    ))
      tile.notification.id: tile.notification.read,
  };

  Finder snack(String text) =>
      find.descendant(of: find.byType(SnackBar), matching: find.text(text));

  void expectErrorSnack(WidgetTester tester, String text) {
    expect(snack(text), findsOneWidget);
    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
      AppColors.error,
      reason: 'a failed write is an ERROR snackbar (SYSTEM.md §15)',
    );
  }

  Future<NotificationsProvider> pump(
    WidgetTester tester,
    List<AppNotification> items, {
    Widget? child,
    void Function(BuildContext, String)? onOpenRoute,
  }) async {
    when(
      () => service.getNotifications(),
    ).thenAnswer((_) async => ApiResponse.success(items));
    final provider = NotificationsProvider(service: service);
    await tester.pumpWidget(
      wrapApp(
        providers: [ChangeNotifierProvider.value(value: provider)],
        home:
            child ??
            Scaffold(body: NotificationsList(onOpenRoute: onOpenRoute)),
      ),
    );
    await tester.pumpAndSettle();
    return provider;
  }

  group('touching a row', () {
    for (final (name, answer, sentence) in [
      ('no answer', noAnswer, offline),
      ('refused', refused, generic),
    ]) {
      testWidgets('$name: the row is unread again and the snackbar says '
          '« $sentence »', (tester) async {
        await pump(tester, [note('a'), note('b')]);
        final pending = Completer<ApiResponse<bool>>();
        when(() => service.markRead('a')).thenAnswer((_) => pending.future);

        await tester.tap(find.text('Titre a'));
        await tester.pump();
        expect(rendered(tester), {
          'a': true,
          'b': false,
        }, reason: 'read at once');

        pending.complete(answer());
        await tester.pumpAndSettle();

        expect(rendered(tester), {'a': false, 'b': false});
        expectErrorSnack(tester, sentence);
      });
    }

    // docs/design/app-failure-messages.md §2.3 (B3.3): the failure stayed up
    // its 6 s over a retry that had worked.
    testWidgets('a new touch that succeeds hides the last failure at once', (
      tester,
    ) async {
      await pump(tester, [note('a')]);
      final answers = [noAnswer(), noAnswer(), ApiResponse.success(true)];
      when(
        () => service.markRead('a'),
      ).thenAnswer((_) async => answers.removeAt(0));

      await tester.tap(find.text('Titre a'));
      await tester.pumpAndSettle();
      expectErrorSnack(tester, offline);

      await tester.tap(find.text('Titre a')); // the network is back
      await tester.pump();
      await tester.pump(
        const Duration(milliseconds: 400),
      ); // the exit animation
      expect(find.byType(SnackBar), findsNothing);
      expect(rendered(tester), {'a': true});
    });

    testWidgets('accepted: the row stays read, nothing is said', (
      tester,
    ) async {
      await pump(tester, [note('a')]);
      when(
        () => service.markRead('a'),
      ).thenAnswer((_) async => ApiResponse.success(true));

      await tester.tap(find.text('Titre a'));
      await tester.pumpAndSettle();

      expect(rendered(tester), {'a': true});
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('the route opens WITHOUT waiting for the write; a failure '
        'once the booking is on top says nothing there, and the row is '
        'unread on the way back', (tester) async {
      await pump(
        tester,
        [note('a', route: '/pro/appointment/a1')],
        onOpenRoute: (context, route) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Réservation')),
          ),
        ),
      );
      final pending = Completer<ApiResponse<bool>>();
      when(() => service.markRead('a')).thenAnswer((_) => pending.future);

      await tester.tap(find.text('Titre a'));
      await tester.pumpAndSettle();
      expect(find.text('Réservation'), findsOneWidget);

      pending.complete(noAnswer());
      await tester.pumpAndSettle();
      expect(
        find.byType(SnackBar),
        findsNothing,
        reason: 'the sentence would land on the booking and blame it',
      );

      Navigator.of(tester.element(find.text('Réservation'))).pop();
      await tester.pumpAndSettle();
      expect(rendered(tester), {'a': false});
    });
  });

  group('« Tout marquer comme lu »', () {
    final screens = <String, Widget Function()>{
      'consumer': () => const NotificationsScreen(),
      'pro': () => ProNotificationsScreen(
        permissionStatus: () async => PushPermissionStatus.granted,
      ),
    };

    for (final MapEntry(key: app, value: screen) in screens.entries) {
      for (final (name, answer, sentence) in [
        ('no answer', noAnswer, offline),
        ('refused', refused, generic),
      ]) {
        testWidgets('$app, $name: the action comes back, only the rows it '
            'marked are unread again, « $sentence »', (tester) async {
          await pump(tester, [
            note('a'),
            note('b', read: true),
            note('c'),
          ], child: screen());
          final pending = Completer<ApiResponse<bool>>();
          when(() => service.markAllRead()).thenAnswer((_) => pending.future);

          await tester.tap(find.byTooltip(markAll));
          await tester.pump();
          expect(find.byTooltip(markAll), findsNothing);
          expect(rendered(tester), {'a': true, 'b': true, 'c': true});

          pending.complete(answer());
          await tester.pumpAndSettle();

          expect(find.byTooltip(markAll), findsOneWidget);
          expect(rendered(tester), {'a': false, 'b': true, 'c': false});
          expectErrorSnack(tester, sentence);
        });
      }

      testWidgets('$app, accepted: all read, the action gone, nothing said', (
        tester,
      ) async {
        await pump(tester, [note('a'), note('b')], child: screen());
        when(
          () => service.markAllRead(),
        ).thenAnswer((_) async => ApiResponse.success(true));

        await tester.tap(find.byTooltip(markAll));
        await tester.pumpAndSettle();

        expect(rendered(tester), {'a': true, 'b': true});
        expect(find.byTooltip(markAll), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
      });
    }

    testWidgets('a failure once a row has opened its booking says nothing '
        'there; the rows it marked are unread on the way back', (tester) async {
      when(() => service.getNotifications()).thenAnswer(
        (_) async =>
            ApiResponse.success([note('a', route: '/bookings'), note('b')]),
      );
      final provider = NotificationsProvider(service: service);
      final router = GoRouter(
        initialLocation: '/notifications',
        routes: [
          GoRoute(
            path: '/notifications',
            builder: (_, _) => const NotificationsScreen(),
          ),
          GoRoute(
            path: '/bookings',
            builder: (_, _) => const Scaffold(body: Text('Réservation')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        wrapApp(
          providers: [ChangeNotifierProvider.value(value: provider)],
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();
      final pending = Completer<ApiResponse<bool>>();
      when(() => service.markAllRead()).thenAnswer((_) => pending.future);

      await tester.tap(find.byTooltip(markAll));
      await tester.pump();
      // Read already (the optimism): the row opens its route, writes nothing.
      await tester.tap(find.text('Titre a'));
      await tester.pumpAndSettle();
      expect(find.text('Réservation'), findsOneWidget);
      verifyNever(() => service.markRead(any()));

      pending.complete(noAnswer());
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      router.pop();
      await tester.pumpAndSettle();
      expect(rendered(tester), {'a': false, 'b': false});
      expect(find.byTooltip(markAll), findsOneWidget);
    });

    // §3.2 ② — the action unmounts itself while it is out; focus goes with it.
    group('focus', () {
      FocusNode focusOf(WidgetTester tester, Finder finder) =>
          Focus.of(tester.element(finder));
      final action = find.byIcon(Icons.done_all);

      Future<Completer<ApiResponse<bool>>> pumpPro(WidgetTester tester) async {
        await pump(
          tester,
          [note('a'), note('b')],
          child: ProNotificationsScreen(
            permissionStatus: () async => PushPermissionStatus.granted,
          ),
        );
        final pending = Completer<ApiResponse<bool>>();
        when(() => service.markAllRead()).thenAnswer((_) => pending.future);
        return pending;
      }

      testWidgets('activated from the keyboard: the focus fell with the '
          'action, and comes back to it with the failure', (tester) async {
        final pending = await pumpPro(tester);
        focusOf(tester, action).requestFocus();
        await tester.pump();
        expect(focusOf(tester, action).hasPrimaryFocus, isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(action, findsNothing);
        expect(
          FocusManager.instance.primaryFocus,
          isA<FocusScopeNode>(),
          reason: 'the focus fell: nothing in particular holds it',
        );

        pending.complete(noAnswer());
        await tester.pumpAndSettle();

        expect(action, findsOneWidget);
        expect(focusOf(tester, action).hasPrimaryFocus, isTrue);
      });

      testWidgets('touched with a finger: the action never had the focus, '
          'and does not take it', (tester) async {
        final pending = await pumpPro(tester);

        await tester.tap(action);
        await tester.pump();
        pending.complete(noAnswer());
        await tester.pumpAndSettle();

        expect(action, findsOneWidget);
        expect(focusOf(tester, action).hasPrimaryFocus, isFalse);
      });

      testWidgets('focus moved elsewhere while the write was out stays '
          'there — never stolen', (tester) async {
        final pending = await pumpPro(tester);
        focusOf(tester, action).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();

        final row = focusOf(tester, find.text('Titre b'));
        row.requestFocus();
        await tester.pump();
        expect(row.hasPrimaryFocus, isTrue);

        pending.complete(noAnswer());
        await tester.pumpAndSettle();

        expect(action, findsOneWidget);
        expect(row.hasPrimaryFocus, isTrue);
        expect(focusOf(tester, action).hasPrimaryFocus, isFalse);
      });
    });
  });
}
