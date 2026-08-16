import '../entities/app_notification.dart';
import '../entities/notification_preference.dart';

abstract interface class NotificationRepository {
  Future<List<AppNotification>> getNotifications();
  Future<void> markRead(String notificationId);
  Future<void> markAllRead();

  /// Üyenin kapattığı zil türleri. Kaydedilmiş satırı olmayan tür açık geliyor,
  /// o yüzden cevap her zaman altı türün tamamını taşıyor.
  Future<NotificationPreferences> getPreferences();

  /// Yalnızca değişen türü gönderiyoruz; sunucu diğerlerine dokunmuyor. Cevap
  /// kaydedilmiş son hâl: iki cihazdan aynı anda yapılan değişiklikte ekranda
  /// kalan, gönderdiğimiz değil, sunucuda duran.
  Future<NotificationPreferences> savePreferences(Map<String, bool> changes);
}
