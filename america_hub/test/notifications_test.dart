import 'package:america_hub/core/navigation/app_deep_link.dart';
import 'package:america_hub/core/network/api_client.dart';
import 'package:america_hub/core/storage/in_memory_token_store.dart';
import 'package:america_hub/features/notifications/application/notifications_controller.dart';
import 'package:america_hub/features/notifications/data/repositories/api_notification_repository.dart';
import 'package:america_hub/features/notifications/domain/entities/app_notification.dart';
import 'package:america_hub/features/notifications/domain/repositories/notification_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_adapter.dart';

Map<String, dynamic> row({
  required String kind,
  String subjectId = '11111111-1111-1111-1111-111111111111',
  String subjectTitle = 'Kanepe',
  int actorCount = 1,
  String? actorName,
  bool isRead = false,
}) => {
  'id': 'notification-1',
  'kind': kind,
  'subjectId': subjectId,
  'subjectTitle': subjectTitle,
  'actorCount': actorCount,
  'actorName': actorName,
  'createdAt': '2026-08-13T10:00:00.000Z',
  'isRead': isRead,
};

({ApiNotificationRepository repository, RecordingAdapter adapter}) build(
  List<Object?> bodies, {
  int statusCode = 200,
}) {
  final adapter = RecordingAdapter.sequence(bodies, statusCode: statusCode);
  final dio = Dio(BaseOptions(baseUrl: 'https://community.test/v1/'))
    ..httpClientAdapter = adapter;
  return (
    repository: ApiNotificationRepository(
      client: ApiClient(tokenStore: InMemoryTokenStore(), dio: dio),
    ),
    adapter: adapter,
  );
}

/// Sunucusuz bir depo: denetleyicinin iyimser davranışını sınamak için.
class _StubRepository implements NotificationRepository {
  _StubRepository(this._items, {this.failWrites = false});
  List<AppNotification> _items;
  final bool failWrites;
  int markAllCalls = 0;

  @override
  Future<List<AppNotification>> getNotifications() async => _items;

  @override
  Future<void> markAllRead() async {
    markAllCalls++;
    if (failWrites) throw Exception('offline');
    _items = [for (final item in _items) item.copyWith(isRead: true)];
  }

  @override
  Future<void> markRead(String notificationId) async {
    if (failWrites) throw Exception('offline');
  }
}

AppNotification unread(String id) => AppNotification(
  id: id,
  type: AppNotificationType.postLike,
  title: 'Paylaşımın beğenildi',
  body: 'Bir kişi paylaşımını beğendi.',
  createdAt: DateTime(2026, 8, 13),
  deepLink: Uri.parse('turksquare://post/$id'),
);

void main() {
  test('yorum bildiriminde adı geçen kişi yazılıyor', () async {
    final harness = build([
      {
        'data': [
          row(kind: 'post_comment', subjectTitle: 'Bugün ne yapsak?', actorName: 'Elif Demir'),
        ],
      },
    ]);
    final items = await harness.repository.getNotifications();
    expect(items.single.type, AppNotificationType.postComment);
    expect(items.single.body, 'Elif Demir "Bugün ne yapsak?" paylaşımına yorum yaptı.');
  });

  test('birden fazla yorumcuda geri kalanlar sayı olarak anılıyor', () async {
    final harness = build([
      {
        'data': [
          row(kind: 'post_comment', subjectTitle: 'Bugün ne yapsak?', actorCount: 3, actorName: 'Elif Demir'),
        ],
      },
    ]);
    final items = await harness.repository.getNotifications();
    expect(items.single.body, 'Elif Demir ve 2 kişi daha "Bugün ne yapsak?" paylaşımına yorum yaptı.');
  });

  test('beğeni ve kaydetme kimseyi adıyla anmıyor', () async {
    final harness = build([
      {
        'data': [
          row(kind: 'post_like', subjectTitle: 'Bugün ne yapsak?', actorCount: 4),
          row(kind: 'listing_save', actorCount: 1),
        ],
      },
    ]);
    final items = await harness.repository.getNotifications();
    expect(items[0].body, '4 kişi "Bugün ne yapsak?" paylaşımını beğendi.');
    expect(items[1].body, 'Bir kişi "Kanepe" ilanını kaydetti.');
    expect(items[1].type, AppNotificationType.listingSaved);
  });

  test('paylaşım bildirimi paylaşıma, ilan bildirimi ilana gidiyor', () async {
    final harness = build([
      {
        'data': [
          row(kind: 'post_like', subjectId: 'post-9'),
          row(kind: 'listing_like', subjectId: 'listing-9'),
        ],
      },
    ]);
    final items = await harness.repository.getNotifications();
    expect(AppDeepLink.parse(items[0].deepLink), isA<PostDeepLink>());
    expect(AppDeepLink.parse(items[1].deepLink), isA<ListingDeepLink>());
  });

  test('uzun paylaşım tek satıra sığdırılıyor', () async {
    final harness = build([
      {
        'data': [
          row(
            kind: 'post_like',
            subjectTitle: 'Bu   çok\nuzun bir paylaşım metni ve tek satıra asla sığmaz',
          ),
        ],
      },
    ]);
    final items = await harness.repository.getNotifications();
    expect(items.single.body, contains('…'));
    expect(items.single.body, contains('Bu çok uzun bir paylaşım'));
  });

  test('okundu işaretleme sunucuya gidiyor', () async {
    final harness = build([null, null]);
    await harness.repository.markRead('notification-1');
    await harness.repository.markAllRead();
    expect(harness.adapter.requests[0].path, '/notifications/notification-1/read');
    expect(harness.adapter.requests[0].method, 'PUT');
    expect(harness.adapter.requests[1].path, '/notifications/read-all');
  });

  test('hepsini okundu işaretlemek rozeti anında sıfırlıyor', () async {
    final controller = NotificationsController(
      repository: _StubRepository([unread('a'), unread('b')]),
    );
    await controller.load();
    expect(controller.unreadCount, 2);
    await controller.markAllRead();
    expect(controller.unreadCount, 0);
  });

  test('sunucu kabul etmezse rozet geri geliyor', () async {
    final controller = NotificationsController(
      repository: _StubRepository([unread('a')], failWrites: true),
    );
    await controller.load();
    await controller.markAllRead();
    expect(controller.unreadCount, 1);
  });

  test('okunmamış bildirim yokken sunucuya hiç gidilmiyor', () async {
    final repository = _StubRepository([unread('a').copyWith(isRead: true)]);
    final controller = NotificationsController(repository: repository);
    await controller.load();
    await controller.markAllRead();
    expect(repository.markAllCalls, 0);
  });

  test('okundu bilgisi ulaşmasa da bildirim yine de açılıyor', () async {
    final controller = NotificationsController(
      repository: _StubRepository([unread('a')], failWrites: true),
    );
    await controller.load();
    final target = await controller.open(controller.items.single);
    expect(target, isA<PostDeepLink>());
    expect(controller.unreadCount, 1);
  });

  // `load()` yalnızca `finally` ile sarılıydı: istek 401 dönünce hata dışarı
  // sızıyor, ekran da "Yeni bildirim yok" diyordu. Hiç bildirim gelmemiş olmak
  // ile sunucuya ulaşamamak aynı cümleyle anlatılamaz.
  test('istek başarısız olunca hata fırlatmıyor, nedenini tutuyor', () async {
    final harness = build([
      {
        'error': {
          'code': 'NOTIFICATIONS_UNAVAILABLE',
          'message': 'Bildirimler yüklenemedi.',
        },
      },
    ], statusCode: 401);
    final controller = NotificationsController(repository: harness.repository);

    await controller.load();

    expect(controller.items, isEmpty);
    expect(controller.error, contains('yeniden giriş'));
  });
}
