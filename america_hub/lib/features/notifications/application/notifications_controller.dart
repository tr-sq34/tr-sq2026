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
    isLoading = true;
    // The shell's bell and the notifications screen both start this from
    // `initState`, so a listener can be mid-build when it runs; notifying then
    // is a framework error. Only the notification waits — the flag above is set
    // straight away.
    await Future<void>.microtask(() {});
    notifyListeners();
    try { items = await _repository.getNotifications(); } finally { isLoading = false; notifyListeners(); }
  }

  /// Hepsini okundu işaretle. Depoda bu yöntem başından beri vardı ama hiçbir
  /// yerden çağrılmıyordu: on iki bildirimi temizlemenin tek yolu on ikisine
  /// tek tek dokunmaktı.
  Future<void> markAllRead() async {
    if (unreadCount == 0) return;
    final previous = items;
    items = [for (final item in items) item.copyWith(isRead: true)];
    notifyListeners();
    try {
      await _repository.markAllRead();
    } catch (_) {
      // Sunucu kabul etmediyse rozet geri geliyor: temizlenmiş gibi görünüp
      // uygulama yeniden açılınca geri dönen bir sayaç daha kötü.
      items = previous;
      notifyListeners();
    }
  }

  Future<AppDeepLink> open(AppNotification notification) async {
    // Okundu bilgisi sunucuya ulaşmazsa satır okunmamış kalıyor - ama açılış
    // yine de oluyor. Kopan bağlantı yüzünden dokunulan bildirimin hiçbir şey
    // yapmaması, sayacın bir fazla kalmasından daha kötü.
    if (!notification.isRead) {
      try {
        await _repository.markRead(notification.id);
        items = [for (final item in items) if (item.id == notification.id) item.copyWith(isRead: true) else item];
        notifyListeners();
      } catch (_) {}
    }
    return AppDeepLink.parse(notification.deepLink);
  }
}
