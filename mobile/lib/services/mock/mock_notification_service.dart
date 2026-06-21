import '../../core/constants/app_constants.dart';
import '../../models/api_response.dart';
import '../../models/app_notification.dart';
import '../interfaces/notification_service_interface.dart';

class MockNotificationService implements NotificationServiceInterface {
  final List<AppNotification> _items = _seed();

  static List<AppNotification> _seed() {
    final now = DateTime.now();
    return [
      AppNotification(
        id: 'notif1',
        type: AppNotificationType.bookingConfirmed,
        title: 'Rendez-vous confirmé',
        body: 'Salon Excellence · ${_dayLabel(now)} à 10:00',
        createdAt: now.subtract(const Duration(hours: 2)),
        route: '/bookings',
      ),
      AppNotification(
        id: 'notif2',
        type: AppNotificationType.depositReceived,
        title: 'Acompte reçu',
        body: '6 000 XOF pour votre rendez-vous',
        createdAt: now.subtract(const Duration(hours: 2, minutes: 1)),
        route: '/bookings',
      ),
      AppNotification(
        id: 'notif3',
        type: AppNotificationType.reminder,
        title: 'Rappel de rendez-vous',
        body: 'Demain à 10:00 chez Salon Excellence',
        createdAt: now.subtract(const Duration(days: 1)),
        read: true,
        route: '/bookings',
      ),
      AppNotification(
        id: 'notif4',
        type: AppNotificationType.reviewRequest,
        title: 'Donnez votre avis',
        body: "Comment s'est passé votre rendez-vous ?",
        createdAt: now.subtract(const Duration(days: 3)),
        read: true,
        route: '/bookings',
      ),
    ];
  }

  static String _dayLabel(DateTime now) {
    final d = now.add(const Duration(days: 2));
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  @override
  Future<ApiResponse<List<AppNotification>>> getNotifications() async {
    await Future.delayed(AppConstants.mockDelay);
    final sorted = List<AppNotification>.from(_items)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ApiResponse.success(sorted);
  }

  @override
  Future<ApiResponse<bool>> markRead(String id) async {
    await Future.delayed(AppConstants.mockDelay);
    final index = _items.indexWhere((n) => n.id == id);
    if (index != -1) {
      _items[index] = _items[index].copyWith(read: true);
    }
    return ApiResponse.success(true);
  }

  @override
  Future<ApiResponse<bool>> markAllRead() async {
    await Future.delayed(AppConstants.mockDelay);
    for (var i = 0; i < _items.length; i++) {
      _items[i] = _items[i].copyWith(read: true);
    }
    return ApiResponse.success(true);
  }
}
