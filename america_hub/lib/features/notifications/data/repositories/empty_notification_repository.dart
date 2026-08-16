import '../../domain/entities/app_notification.dart';
import '../../domain/entities/notification_preference.dart';
import '../../domain/repositories/notification_repository.dart';

/// Nothing, honestly.
///
/// No service publishes member notifications yet — friend requests, comments
/// and badges all arrive in later phases. Wiring [MockNotificationRepository]
/// here instead would put an invented "Yeni eşleşme isteği" in front of real
/// members and a `1` on the bell that nothing can ever clear. An empty list is
/// the truthful answer until there is a source, and swapping this out for an
/// `ApiNotificationRepository` is then a one-line change in `main.dart`.
class EmptyNotificationRepository implements NotificationRepository {
  const EmptyNotificationRepository();

  @override
  Future<List<AppNotification>> getNotifications() async => const [];

  @override
  Future<void> markRead(String notificationId) async {}

  @override
  Future<void> markAllRead() async {}

  /// Zil hiç çalmadığı için kapatılacak bir şey de yok; hepsi açık görünüyor ve
  /// değiştirme denemesi sessizce hiçbir şey yapmıyor.
  @override
  Future<NotificationPreferences> getPreferences() async => const NotificationPreferences.allEnabled();

  @override
  Future<NotificationPreferences> savePreferences(Map<String, bool> changes) async =>
      const NotificationPreferences.allEnabled();
}
