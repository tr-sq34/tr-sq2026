import '../../../../core/network/api_client.dart';
import '../../domain/entities/app_notification.dart';
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
}
