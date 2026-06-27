import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myweli/core/di/dependency_injection.dart';
import 'package:myweli/models/api_response.dart';
import 'package:myweli/models/notification_preferences.dart';
import 'package:myweli/providers/notification_preferences_provider.dart';
import 'package:myweli/services/interfaces/notification_service_interface.dart';
import 'package:myweli/services/mock/mock_notification_service.dart';

class _MockNotificationService extends Mock
    implements NotificationServiceInterface {}

void main() {
  group('NotificationPreferences model', () {
    test('json round-trip', () {
      const p = NotificationPreferences(reminders: false, push: false);
      final back = NotificationPreferences.fromJson(p.toJson());
      expect(back, p);
    });

    test('absent fields default to true', () {
      final p = NotificationPreferences.fromJson(const {});
      expect(p.reminders, isTrue);
      expect(p.marketing, isTrue);
      expect(p.push, isTrue);
    });
  });

  group('MockNotificationService prefs', () {
    test('defaults all on, update persists', () async {
      final svc = MockNotificationService();
      expect(
          (await svc.getPreferences()).data, const NotificationPreferences());
      await svc.updatePreferences(marketing: false);
      expect((await svc.getPreferences()).data!.marketing, isFalse);
    });
  });

  group('NotificationPreferencesProvider', () {
    late _MockNotificationService service;

    setUpAll(() {
      service = _MockNotificationService();
      serviceLocator.notificationService = service;
    });

    setUp(() => reset(service));

    test('load populates prefs', () async {
      when(() => service.getPreferences()).thenAnswer(
        (_) async => ApiResponse.success(
            const NotificationPreferences(marketing: false)),
      );
      final p = NotificationPreferencesProvider();
      await p.load();
      expect(p.prefs.marketing, isFalse);
      expect(p.loadFailed, isFalse);
    });

    test('load failure sets loadFailed', () async {
      when(() => service.getPreferences())
          .thenAnswer((_) async => ApiResponse.error('x'));
      final p = NotificationPreferencesProvider();
      await p.load();
      expect(p.loadFailed, isTrue);
    });

    test('setReminders persists on success', () async {
      when(
        () => service.updatePreferences(
          reminders: any(named: 'reminders'),
          marketing: any(named: 'marketing'),
          push: any(named: 'push'),
        ),
      ).thenAnswer(
        (_) async => ApiResponse.success(
            const NotificationPreferences(reminders: false)),
      );
      final p = NotificationPreferencesProvider();
      final ok = await p.setReminders(false);
      expect(ok, isTrue);
      expect(p.prefs.reminders, isFalse);
      verify(
        () => service.updatePreferences(
          reminders: false,
          marketing: null,
          push: null,
        ),
      ).called(1);
    });

    test('setReminders reverts on failure and sets error', () async {
      when(
        () => service.updatePreferences(
          reminders: any(named: 'reminders'),
          marketing: any(named: 'marketing'),
          push: any(named: 'push'),
        ),
      ).thenAnswer((_) async => ApiResponse.error('nope'));
      final p = NotificationPreferencesProvider();
      // default prefs are all-true
      final ok = await p.setReminders(false);
      expect(ok, isFalse);
      expect(p.prefs.reminders, isTrue); // reverted
      expect(p.error, isNotNull);
    });
  });
}
