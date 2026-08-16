import '../../../../core/network/api_client.dart';
import '../../domain/entities/app_notification.dart';
import '../../domain/entities/notification_preference.dart';
import '../../domain/repositories/notification_repository.dart';
import '../dtos/app_notification_dto.dart';

/// Zilin kaynağı.
///
/// Buranın yerinde bugüne kadar EmptyNotificationRepository duruyordu ve
/// doğru olan oydu: hiçbir servis bildirim yayınlamıyordu, boş liste tek dürüst
/// cevaptı. Artık paylaşımına gelen yorum, gönderine gelen beğeni ve ilanına
/// gelen kaydetme sunucuda bir satır bırakıyor.
class ApiNotificationRepository implements NotificationRepository {
  ApiNotificationRepository({required ApiClient client}) : _client = client;
  final ApiClient _client;

  @override
  Future<List<AppNotification>> getNotifications() async {
    final response = await _client.get<Map<String, dynamic>>('/notifications');
    final data = response.data?['data'] as List? ?? const [];
    return [
      for (final item in data)
        AppNotificationDto.fromJson(item as Map<String, dynamic>).toDomain(),
    ];
  }

  @override
  Future<void> markRead(String notificationId) =>
      _client.put<void>('/notifications/$notificationId/read');

  @override
  Future<void> markAllRead() => _client.put<void>('/notifications/read-all');

  @override
  Future<NotificationPreferences> getPreferences() async {
    final response = await _client.get<Map<String, dynamic>>('/notifications/preferences');
    return _read(response.data);
  }

  @override
  Future<NotificationPreferences> savePreferences(Map<String, bool> changes) async {
    final response = await _client.put<Map<String, dynamic>>(
      '/notifications/preferences',
      data: {'preferences': changes},
    );
    return _read(response.data);
  }

  /// Gövde beklenmedik geldiğinde her şeyi açık göstermek yerine hata veriyoruz:
  /// kapattığı bildirimi açık görmek, üyeye ayarının silindiğini düşündürür.
  NotificationPreferences _read(Map<String, dynamic>? body) {
    final preferences = (body?['data'] as Map<String, dynamic>?)?['preferences'];
    if (preferences is! Map<String, dynamic>) {
      throw const FormatException('Bildirim tercihleri okunamadi.');
    }
    return NotificationPreferences.fromWire(preferences);
  }
}
