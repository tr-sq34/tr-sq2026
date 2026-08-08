import 'package:flutter/foundation.dart';

import '../../../core/navigation/app_deep_link.dart';
import '../domain/entities/app_notification.dart';
import '../domain/repositories/notification_repository.dart';

class NotificationsController extends ChangeNotifier {
  NotificationsController({required NotificationRepository repository}) : _repository = repository;
  final NotificationRepository _repository;
  List<AppNotification> items = const [];
  bool isLoading = false;

  int get unreadCount => items.where((item) => !item.isRead).length;

  Future<void> load() async {
    isLoading = true; notifyListeners();
    try { items = await _repository.getNotifications(); } finally { isLoading = false; notifyListeners(); }
  }

  Future<AppDeepLink> open(AppNotification notification) async {
    if (!notification.isRead) {
      await _repository.markRead(notification.id);
      items = [for (final item in items) if (item.id == notification.id) item.copyWith(isRead: true) else item];
      notifyListeners();
    }
    return AppDeepLink.parse(notification.deepLink);
  }
}
