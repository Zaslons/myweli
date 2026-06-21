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
    when(() => service.getNotifications())
        .thenAnswer((_) async => ApiResponse.error('boom'));

    final provider = NotificationsProvider();
    await provider.load();

    expect(provider.loadFailed, isTrue);
    expect(provider.notifications, isEmpty);
  });

  test('markRead flips one item and persists it', () async {
    when(() => service.getNotifications())
        .thenAnswer((_) async => ApiResponse.success([note('a'), note('b')]));
    when(() => service.markRead(any()))
        .thenAnswer((_) async => ApiResponse.success(true));

    final provider = NotificationsProvider();
    await provider.load();
    await provider.markRead('a');

    expect(provider.unreadCount, 1);
    verify(() => service.markRead('a')).called(1);
  });

  test('markAllRead clears unread and persists', () async {
    when(() => service.getNotifications())
        .thenAnswer((_) async => ApiResponse.success([note('a'), note('b')]));
    when(() => service.markAllRead())
        .thenAnswer((_) async => ApiResponse.success(true));

    final provider = NotificationsProvider();
    await provider.load();
    await provider.markAllRead();

    expect(provider.unreadCount, 0);
    verify(() => service.markAllRead()).called(1);
  });
}
