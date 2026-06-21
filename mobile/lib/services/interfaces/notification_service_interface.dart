import '../../models/api_response.dart';
import '../../models/app_notification.dart';

abstract class NotificationServiceInterface {
  Future<ApiResponse<List<AppNotification>>> getNotifications();
  Future<ApiResponse<bool>> markRead(String id);
  Future<ApiResponse<bool>> markAllRead();
}
