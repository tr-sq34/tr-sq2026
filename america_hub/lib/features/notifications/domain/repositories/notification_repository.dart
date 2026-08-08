import '../entities/app_notification.dart';

abstract interface class NotificationRepository {
  Future<List<AppNotification>> getNotifications();
  Future<void> markRead(String notificationId);
  Future<void> markAllRead();
}
