import '../../domain/entities/app_notification.dart';
import '../../domain/repositories/notification_repository.dart';

class MockNotificationRepository implements NotificationRepository {
  final List<AppNotification> _items = [
    AppNotification(id: 'notification-1', type: AppNotificationType.specialRequest, title: 'Yeni eşleşme isteği', body: 'Bavulda Yer Var paylaşımın için bir istek geldi.', createdAt: DateTime.now(), deepLink: Uri.parse('turksquare://request/request-1')),
  ];

  @override
  Future<List<AppNotification>> getNotifications() async => List.unmodifiable(_items);

  @override
  Future<void> markAllRead() async { for (var index = 0; index < _items.length; index++) { _items[index] = _items[index].copyWith(isRead: true); } }

  @override
  Future<void> markRead(String notificationId) async { final index = _items.indexWhere((item) => item.id == notificationId); if (index >= 0) _items[index] = _items[index].copyWith(isRead: true); }
}
