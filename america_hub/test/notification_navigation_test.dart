import 'package:america_hub/features/community/presentation/widgets/comments_sheet.dart';
import 'package:america_hub/features/marketplace/presentation/screens/marketplace_screen.dart';
import 'package:america_hub/features/notifications/domain/entities/app_notification.dart';
import 'package:america_hub/features/notifications/domain/entities/notification_preference.dart';
import 'package:america_hub/features/notifications/domain/repositories/notification_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shell_harness.dart';

/// Zilin arkasındaki satırlar. Sunucu yerine burada duruyorlar; sınanan şey
/// satıra dokunulduğunda nereye gidildiği.
class _Notifications implements NotificationRepository {
  _Notifications(this._items);

  List<AppNotification> _items;

  @override
  Future<List<AppNotification>> getNotifications() async => _items;

  @override
  Future<void> markAllRead() async {
    _items = [for (final item in _items) item.copyWith(isRead: true)];
  }

  @override
  Future<void> markRead(String notificationId) async {}

  @override
  Future<NotificationPreferences> getPreferences() async => const NotificationPreferences.allEnabled();

  @override
  Future<NotificationPreferences> savePreferences(Map<String, bool> changes) async =>
      const NotificationPreferences.allEnabled();
}

AppNotification _row({
  required AppNotificationType type,
  required String title,
  required String link,
}) => AppNotification(
  id: 'notification-$link',
  type: type,
  title: title,
  body: 'Bildirim satırı',
  createdAt: DateTime(2026, 8, 13),
  deepLink: Uri.parse(link),
);

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> openBell(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.notifications_none_rounded).first);
  await settle(tester);
}

void main() {
  // Zil aylardır gerçek satırlar gösteriyordu ama dokunmak hiçbir yere
  // götürmüyordu: çözülen bağlantı okunup atılıyordu.
  testWidgets('paylasim bildirimi o paylasimin yorumlarini aciyor', (
    tester,
  ) async {
    await pumpShell(
      tester,
      notifications: _Notifications([
        _row(
          type: AppNotificationType.postComment,
          title: 'Paylaşımına yorum yapıldı',
          link: 'turksquare://post/post-1',
        ),
      ]),
    );

    await openBell(tester);
    await tester.tap(find.text('Paylaşımına yorum yapıldı'));
    await settle(tester);

    expect(find.byType(CommentsSheet), findsOneWidget);
    // Hangi paylaşım olduğu tabakanın kendisinde yazıyor: bildirimden gelen üye
    // kartı görmüyor, yalnızca yorumları görüyor.
    expect(find.textContaining('Türk kahvaltısı'), findsOneWidget);
  });

  testWidgets('ilan bildirimi ilanin kendisini aciyor', (tester) async {
    await pumpShell(
      tester,
      notifications: _Notifications([
        _row(
          type: AppNotificationType.listingSaved,
          title: 'İlanın kaydedildi',
          link: 'turksquare://listing/listing-2',
        ),
      ]),
    );

    await openBell(tester);
    await tester.tap(find.text('İlanın kaydedildi'));
    await settle(tester);

    expect(find.byType(MarketplaceDetailScreen), findsOneWidget);
    expect(find.text('Vintage kilim'), findsWidgets);
  });

  testWidgets('artik olmayan paylasim sessizce yutulmuyor', (tester) async {
    await pumpShell(
      tester,
      notifications: _Notifications([
        _row(
          type: AppNotificationType.postLike,
          title: 'Paylaşımın beğenildi',
          link: 'turksquare://post/post-silinmis',
        ),
      ]),
    );

    await openBell(tester);
    await tester.tap(find.text('Paylaşımın beğenildi'));
    await settle(tester);

    expect(find.byType(CommentsSheet), findsNothing);
    expect(find.text('Bu paylaşım artık yok.'), findsOneWidget);
  });

  // Kişinin kendi profili diye bir ekran henüz yok; isteğin durduğu yer profilin
  // Arkadaşlar sekmesi, o yüzden bildirim oraya götürüyor.
  testWidgets('arkadaslik istegi profilin Arkadaslar sekmesine goturuyor', (
    tester,
  ) async {
    await pumpShell(
      tester,
      notifications: _Notifications([
        _row(
          type: AppNotificationType.friendRequest,
          title: 'Yeni arkadaşlık isteği',
          link: 'turksquare://friend/member-elif',
        ),
      ]),
    );

    await openBell(tester);
    await tester.tap(find.text('Yeni arkadaşlık isteği'));
    await settle(tester);

    // Bildirim ekranı da kapanıyor: üye isteği görmek için geri tuşuna basmak
    // zorunda kalmıyor.
    expect(find.text('Bildirimler'), findsNothing);
    expect(find.widgetWithText(Tab, 'Arkadaşlar'), findsOneWidget);
  });
}
