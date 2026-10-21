import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/app_notification.dart';
import 'package:myweli/providers/notifications_provider.dart';
import 'package:myweli/services/interfaces/notification_service_interface.dart';

class _MockNotificationService extends Mock
    implements NotificationServiceInterface {}

void main() {
  late _MockNotificationService service;

  setUpAll(() {
    service = _MockNotificationService();
    serviceLocator.notificationService = service;
  });

  setUp(() => reset(service));

  AppNotification note(String id, {bool read = false}) => AppNotification(
    id: id,
    type: AppNotificationType.general,
    title: 'title',
    body: 'body',
    createdAt: DateTime(2024),
    read: read,
  );

  test('load populates the list and computes unreadCount', () async {
    when(() => service.getNotifications()).thenAnswer(
      (_) async => ApiResponse.success([note('a'), note('b', read: true)]),
    );

    final provider = NotificationsProvider();
    await provider.load();

    expect(provider.notifications, hasLength(2));
    expect(provider.unreadCount, 1);
    expect(provider.loadFailed, isFalse);
  });

  test('load marks loadFailed and empties on error', () async {
    when(
      () => service.getNotifications(),
    ).thenAnswer((_) async => ApiResponse.error('boom'));

    final provider = NotificationsProvider();
    await provider.load();

    expect(provider.loadFailed, isTrue);
    expect(provider.notifications, isEmpty);
  });

  test('markRead flips one item and persists it', () async {
    when(
      () => service.getNotifications(),
    ).thenAnswer((_) async => ApiResponse.success([note('a'), note('b')]));
    when(
      () => service.markRead(any()),
    ).thenAnswer((_) async => ApiResponse.success(true));

    final provider = NotificationsProvider();
    await provider.load();
    await provider.markRead('a');

    expect(provider.unreadCount, 1);
    verify(() => service.markRead('a')).called(1);
  });

  test('markAllRead clears unread and persists', () async {
    when(
      () => service.getNotifications(),
    ).thenAnswer((_) async => ApiResponse.success([note('a'), note('b')]));
    when(
      () => service.markAllRead(),
    ).thenAnswer((_) async => ApiResponse.success(true));

    final provider = NotificationsProvider();
    await provider.load();
    await provider.markAllRead();

    expect(provider.unreadCount, 0);
    verify(() => service.markAllRead()).called(1);
  });

  // docs/design/app-notifications-read-revert.md — a failed write puts back
  // what THIS gesture marked, and only that (SYSTEM.md §15: undo is never a
  // snapshot), and says why.
  group('a failed « marquer comme lu »', () {
    const offline = 'Pas de connexion. Réessayez.';
    const generic = 'Une erreur est survenue. Réessayez.';

    ApiResponse<bool> noAnswer() => ApiResponse.error(offline, code: 'network');
    // What `_errorFrom` makes of the server's `{"error":"internal_error"}`:
    // the body has no `message`, so the sentence is « Erreur ».
    ApiResponse<bool> refused() =>
        ApiResponse.error('Erreur', code: 'internal_error');

    bool readOf(NotificationsProvider p, String id) =>
        p.notifications.singleWhere((n) => n.id == id).read;

    Future<NotificationsProvider> loaded(List<AppNotification> items) async {
      when(
        () => service.getNotifications(),
      ).thenAnswer((_) async => ApiResponse.success(items));
      final provider = NotificationsProvider(service: service);
      await provider.load();
      return provider;
    }

    test('markRead, no answer: that one is unread again, the other is '
        'untouched, and the sentence is the service\'s', () async {
      final provider = await loaded([note('a'), note('b')]);
      when(() => service.markRead('a')).thenAnswer((_) async => noAnswer());

      final failure = await provider.markRead('a');

      expect(failure, offline);
      expect(readOf(provider, 'a'), isFalse);
      expect(readOf(provider, 'b'), isFalse);
      expect(provider.unreadCount, 2);
    });

    test('markRead, refused by the server: unread again, and the generic '
        'sentence — never the server\'s « Erreur »', () async {
      final provider = await loaded([note('a')]);
      when(() => service.markRead('a')).thenAnswer((_) async => refused());

      expect(await provider.markRead('a'), generic);
      expect(readOf(provider, 'a'), isFalse);
    });

    test('markRead, the service throws: unread again, generic', () async {
      final provider = await loaded([note('a')]);
      when(() => service.markRead('a')).thenThrow(Exception('boom'));

      expect(await provider.markRead('a'), generic);
      expect(readOf(provider, 'a'), isFalse);
    });

    test('markRead, accepted: null, and it stays read', () async {
      final provider = await loaded([note('a')]);
      when(
        () => service.markRead('a'),
      ).thenAnswer((_) async => ApiResponse.success(true));

      expect(await provider.markRead('a'), isNull);
      expect(readOf(provider, 'a'), isTrue);
    });

    test('markRead is read at once, before the answer', () async {
      final provider = await loaded([note('a')]);
      final answer = Completer<ApiResponse<bool>>();
      when(() => service.markRead('a')).thenAnswer((_) => answer.future);

      final pending = provider.markRead('a');
      expect(readOf(provider, 'a'), isTrue);

      answer.complete(noAnswer());
      await pending;
      expect(readOf(provider, 'a'), isFalse);
    });

    test('markRead on a row already read writes nothing and says '
        'nothing', () async {
      final provider = await loaded([note('a', read: true)]);

      expect(await provider.markRead('a'), isNull);
      verifyNever(() => service.markRead(any()));
    });

    test('two markRead in flight: the one that fails AFTER the other '
        'succeeded puts back only itself (no snapshot)', () async {
      final provider = await loaded([note('a'), note('b')]);
      final answerA = Completer<ApiResponse<bool>>();
      final answerB = Completer<ApiResponse<bool>>();
      when(() => service.markRead('a')).thenAnswer((_) => answerA.future);
      when(() => service.markRead('b')).thenAnswer((_) => answerB.future);

      final a = provider.markRead('a');
      final b = provider.markRead('b');
      answerB.complete(ApiResponse.success(true));
      expect(await b, isNull);
      answerA.complete(noAnswer());
      expect(await a, offline);

      expect(readOf(provider, 'a'), isFalse);
      expect(readOf(provider, 'b'), isTrue);
    });

    test('markAllRead, no answer: only what was unread goes back — one read '
        'before stays read', () async {
      final provider = await loaded([
        note('a'),
        note('b', read: true),
        note('c'),
      ]);
      when(() => service.markAllRead()).thenAnswer((_) async => noAnswer());

      final failure = await provider.markAllRead();

      expect(failure, offline);
      expect(readOf(provider, 'a'), isFalse);
      expect(readOf(provider, 'b'), isTrue);
      expect(readOf(provider, 'c'), isFalse);
      expect(provider.unreadCount, 2);
    });

    test('markAllRead, refused: unread again, generic', () async {
      final provider = await loaded([note('a')]);
      when(() => service.markAllRead()).thenAnswer((_) async => refused());

      expect(await provider.markAllRead(), generic);
      expect(readOf(provider, 'a'), isFalse);
    });

    test('markAllRead, the service throws: unread again, generic', () async {
      final provider = await loaded([note('a')]);
      when(() => service.markAllRead()).thenThrow(Exception('boom'));

      expect(await provider.markAllRead(), generic);
      expect(readOf(provider, 'a'), isFalse);
    });

    test('markAllRead, accepted: null, all read', () async {
      final provider = await loaded([note('a'), note('b')]);
      when(
        () => service.markAllRead(),
      ).thenAnswer((_) async => ApiResponse.success(true));

      expect(await provider.markAllRead(), isNull);
      expect(provider.unreadCount, 0);
    });

    test('markAllRead with nothing unread writes nothing', () async {
      final provider = await loaded([note('a', read: true)]);

      expect(await provider.markAllRead(), isNull);
      verifyNever(() => service.markAllRead());
    });

    test('markAllRead fails after a reload brought a new notification: the '
        'newcomer stays (no snapshot)', () async {
      final provider = await loaded([note('a')]);
      final answer = Completer<ApiResponse<bool>>();
      when(() => service.markAllRead()).thenAnswer((_) => answer.future);

      final pending = provider.markAllRead();
      when(
        () => service.getNotifications(),
      ).thenAnswer((_) async => ApiResponse.success([note('new'), note('a')]));
      await provider.load();
      answer.complete(noAnswer());
      await pending;

      expect(provider.notifications.map((n) => n.id), ['new', 'a']);
      expect(readOf(provider, 'new'), isFalse);
      expect(readOf(provider, 'a'), isFalse);
    });

    test('a row tapped just before « Tout lire », whose own write fails '
        'while « Tout lire » is out, is still unread after « Tout lire » '
        'fails (no snapshot)', () async {
      final provider = await loaded([note('a'), note('b')]);
      final answerA = Completer<ApiResponse<bool>>();
      final answerAll = Completer<ApiResponse<bool>>();
      when(() => service.markRead('a')).thenAnswer((_) => answerA.future);
      when(() => service.markAllRead()).thenAnswer((_) => answerAll.future);

      final a = provider.markRead('a');
      final all = provider.markAllRead();
      answerA.complete(noAnswer());
      await a;
      answerAll.complete(noAnswer());
      await all;

      expect(readOf(provider, 'a'), isFalse);
      expect(readOf(provider, 'b'), isFalse);
    });

    test('a row tapped just before « Tout lire » whose write succeeds stays '
        'read when « Tout lire » fails', () async {
      final provider = await loaded([note('a'), note('b')]);
      final answerA = Completer<ApiResponse<bool>>();
      final answerAll = Completer<ApiResponse<bool>>();
      when(() => service.markRead('a')).thenAnswer((_) => answerA.future);
      when(() => service.markAllRead()).thenAnswer((_) => answerAll.future);

      final a = provider.markRead('a');
      final all = provider.markAllRead();
      answerA.complete(ApiResponse.success(true));
      await a;
      answerAll.complete(noAnswer());
      await all;

      expect(readOf(provider, 'a'), isTrue);
      expect(readOf(provider, 'b'), isFalse);
    });
  });

  // docs/design/app-failure-messages.md §2.3 (B3.3, owner decision 12): the
  // read state follows the server. A lost answer is asked again ONCE (the write
  // is safe to repeat: `SET read = true`); a reload while a write is out keeps
  // what the person just marked.
  group('the read state follows the server (B3.3)', () {
    const offline = 'Pas de connexion. Réessayez.';
    const generic = 'Une erreur est survenue. Réessayez.';
    ApiResponse<bool> noAnswer() => ApiResponse.error(offline, code: 'network');
    ApiResponse<bool> accepted() => ApiResponse.success(true);

    bool readOf(NotificationsProvider p, String id) =>
        p.notifications.singleWhere((n) => n.id == id).read;

    /// The server's list, as each load answers it.
    late List<AppNotification> serverList;

    Future<NotificationsProvider> loaded(List<AppNotification> items) async {
      serverList = items;
      when(
        () => service.getNotifications(),
      ).thenAnswer((_) async => ApiResponse.success(List.of(serverList)));
      final provider = NotificationsProvider(service: service);
      await provider.load();
      return provider;
    }

    /// Answers [answers] in order, one per call.
    void markReadAnswers(String id, List<ApiResponse<bool>> answers) {
      final queue = [...answers];
      when(
        () => service.markRead(id),
      ).thenAnswer((_) async => queue.removeAt(0));
    }

    test(
      'lost once, then taken: asked again at once — read, nothing to say',
      () async {
        final provider = await loaded([note('a')]);
        markReadAnswers('a', [noAnswer(), accepted()]);

        expect(await provider.markRead('a'), isNull);
        expect(readOf(provider, 'a'), isTrue);
        verify(() => service.markRead('a')).called(2);
      },
    );

    test(
      'lost twice: unread again, « Pas de connexion », and never a third try',
      () async {
        final provider = await loaded([note('a')]);
        markReadAnswers('a', [noAnswer(), noAnswer()]);

        expect(await provider.markRead('a'), offline);
        expect(readOf(provider, 'a'), isFalse);
        verify(() => service.markRead('a')).called(2);
      },
    );

    test('a refusal is not asked again', () async {
      final provider = await loaded([note('a')]);
      markReadAnswers('a', [
        ApiResponse.error(generic, code: 'internal_error'),
      ]);

      expect(await provider.markRead('a'), generic);
      verify(() => service.markRead('a')).called(1);
    });

    test(
      '« Tout lire » lost once, then taken: all read, nothing to say',
      () async {
        final provider = await loaded([note('a'), note('b')]);
        final queue = [noAnswer(), accepted()];
        when(
          () => service.markAllRead(),
        ).thenAnswer((_) async => queue.removeAt(0));

        expect(await provider.markAllRead(), isNull);
        expect(provider.unreadCount, 0);
        verify(() => service.markAllRead()).called(2);
      },
    );

    test('a reload while « lu » is out: the row stays read (the server had not '
        'written it yet), and stays read once it has', () async {
      final provider = await loaded([note('a'), note('b')]);
      final answer = Completer<ApiResponse<bool>>();
      when(() => service.markRead('a')).thenAnswer((_) => answer.future);

      final pending = provider.markRead('a');
      await provider.load(); // the server still says unread
      expect(readOf(provider, 'a'), isTrue, reason: 'kept across the reload');
      expect(readOf(provider, 'b'), isFalse);

      answer.complete(accepted());
      expect(await pending, isNull);
      expect(readOf(provider, 'a'), isTrue);
    });

    test(
      'a reload while « lu » is out, and then the server refuses: unread',
      () async {
        final provider = await loaded([note('a')]);
        final answer = Completer<ApiResponse<bool>>();
        when(() => service.markRead('a')).thenAnswer((_) => answer.future);

        final pending = provider.markRead('a');
        await provider.load();
        answer.complete(ApiResponse.error(generic, code: 'internal_error'));
        expect(await pending, generic);
        expect(readOf(provider, 'a'), isFalse);
      },
    );

    test('a reload during « Tout lire »: what it marked stays read; a new '
        'notification the reload brought stays unread', () async {
      final provider = await loaded([note('a'), note('b')]);
      final answer = Completer<ApiResponse<bool>>();
      when(() => service.markAllRead()).thenAnswer((_) => answer.future);

      final pending = provider.markAllRead();
      serverList = [note('new'), note('a'), note('b')];
      await provider.load();
      expect(readOf(provider, 'a'), isTrue);
      expect(readOf(provider, 'b'), isTrue);
      expect(readOf(provider, 'new'), isFalse);

      answer.complete(accepted());
      await pending;
      expect(readOf(provider, 'new'), isFalse);
      expect(provider.unreadCount, 1);
    });

    test(
      'once the write answered, a reload shows what the server says',
      () async {
        final provider = await loaded([note('a')]);
        markReadAnswers('a', [accepted()]);
        await provider.markRead('a');
        serverList = [
          note('a'),
        ]; // read elsewhere undone, say: the server rules
        await provider.load();
        expect(
          readOf(provider, 'a'),
          isFalse,
          reason:
              'nothing in flight any more — nothing is kept over the server',
        );
      },
    );
  });
}
