import '../../models/api_response.dart';
import '../../models/app_notification.dart';
import '../../models/notification_preferences.dart';

abstract class NotificationServiceInterface {
  Future<ApiResponse<List<AppNotification>>> getNotifications();
  Future<ApiResponse<bool>> markRead(String id);
  Future<ApiResponse<bool>> markAllRead();

  /// Notification preferences (FR-NOTIF-004).
  Future<ApiResponse<NotificationPreferences>> getPreferences();
  Future<ApiResponse<NotificationPreferences>> updatePreferences({
    bool? reminders,
    bool? marketing,
    bool? push,
  });
}
