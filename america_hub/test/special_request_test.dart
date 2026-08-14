import 'package:america_hub/core/network/api_client.dart';
import 'package:america_hub/core/storage/in_memory_token_store.dart';
import 'package:america_hub/features/community/application/community_special_request_controller.dart';
import 'package:america_hub/features/community/data/repositories/api_community_special_request_repository.dart';
import 'package:america_hub/features/community/domain/entities/community_special_request.dart';
import 'package:america_hub/features/community/domain/repositories/community_special_request_repository.dart';
import 'package:america_hub/features/notifications/data/dtos/app_notification_dto.dart';
import 'package:america_hub/features/notifications/domain/entities/app_notification.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_adapter.dart';

Map<String, dynamic> requestRow({
  String id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  String type = 'travelerMatch',
  String status = 'pending',
  String senderName = 'Elif',
}) => {
  'id': id,
  'postId': 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  'senderId': 'cccccccc-cccc-cccc-cccc-cccccccccccc',
  'senderName': senderName,
  'type': type,
  'message': 'İstanbul’dan bir paket gönderebilir miyim?',
  'status': status,
  'createdAt': '2026-08-13T10:00:00.000Z',
};

({ApiCommunitySpecialRequestRepository repository, RecordingAdapter adapter})
build(List<Object?> bodies) {
  final adapter = RecordingAdapter.sequence(bodies);
  final dio = Dio(BaseOptions(baseUrl: 'https://community.test/v1/'))
    ..httpClientAdapter = adapter;
  return (
    repository: ApiCommunitySpecialRequestRepository(
      client: ApiClient(tokenStore: InMemoryTokenStore(), dio: dio),
    ),
    adapter: adapter,
  );
}

/// Sunucusuz depo: denetleyicinin hata karşısındaki davranışını sınamak için.
class _StubRepository implements CommunitySpecialRequestRepository {
  _StubRepository({this.failReads = false, this.failWrites = false});
  final bool failReads;
  final bool failWrites;
  final List<CommunitySpecialRequest> items = [];

  @override
  Future<CommunitySpecialRequest> createRequest({
    required String postId,
    required CommunitySpecialRequestType type,
    required String message,
  }) async {
    if (failWrites) throw Exception('offline');
    final request = CommunitySpecialRequest(
      id: 'request-${items.length}',
      postId: postId,
      type: type,
      senderId: 'sender',
      senderName: 'Elif',
      message: message,
      createdAt: DateTime(2026, 8, 13),
    );
    items.add(request);
    return request;
  }

  @override
  Future<List<CommunitySpecialRequest>> getRequestsForPost(
    String postId,
  ) async {
    if (failReads) throw Exception('offline');
    return items.where((item) => item.postId == postId).toList();
  }

  @override
  Future<void> updateStatus(
    String requestId,
    CommunitySpecialRequestStatus status,
  ) async {
    if (failWrites) throw Exception('offline');
  }
}

void main() {
  group('ApiCommunitySpecialRequestRepository', () {
    test('istek gönderirken türü göndermiyor: türü paylaşım belirliyor', () async {
      final harness = build([
        {'data': requestRow()},
      ]);
      await harness.repository.createRequest(
        postId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        type: CommunitySpecialRequestType.imeceOffer,
        message: 'Yardım edebilirim.',
      );
      final sent = harness.adapter.requests.single;
      expect(sent.method, 'POST');
      expect(
        sent.path,
        '/community/posts/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/requests',
      );
      expect(sent.data, {'message': 'Yardım edebilirim.'});
      expect((sent.data as Map).containsKey('type'), isFalse);
    });

    test('gelen satırı gönderenin adıyla birlikte okuyor', () async {
      final harness = build([
        {
          'data': [requestRow()],
        },
      ]);
      final list = await harness.repository.getRequestsForPost(
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      );
      expect(list, hasLength(1));
      expect(list.single.senderName, 'Elif');
      expect(list.single.type, CommunitySpecialRequestType.travelerMatch);
      expect(list.single.status, CommunitySpecialRequestStatus.pending);
    });

    test('tanımadığı durumu bekliyor sayıyor', () async {
      final harness = build([
        {
          'data': [requestRow(status: 'archived')],
        },
      ]);
      final list = await harness.repository.getRequestsForPost('post');
      expect(list.single.status, CommunitySpecialRequestStatus.pending);
    });

    test('durum güncellemesi tek bir alan gönderiyor', () async {
      final harness = build([null]);
      await harness.repository.updateStatus(
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        CommunitySpecialRequestStatus.accepted,
      );
      final sent = harness.adapter.requests.single;
      expect(sent.method, 'PUT');
      expect(
        sent.path,
        '/community/requests/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/status',
      );
      expect(sent.data, {'status': 'accepted'});
    });
  });

  group('CommunitySpecialRequestController', () {
    test('okuma bittiğinde liste "yüklendi" sayılıyor', () async {
      final controller = CommunitySpecialRequestController(
        repository: _StubRepository(),
      );
      expect(controller.hasLoaded('post-1'), isFalse);
      await controller.loadForPost('post-1');
      expect(controller.hasLoaded('post-1'), isTrue);
      expect(controller.requestsFor('post-1'), isEmpty);
    });

    test('okuma başarısızsa hata mesajı bırakıyor, fırlatmıyor', () async {
      final controller = CommunitySpecialRequestController(
        repository: _StubRepository(failReads: true),
      );
      await controller.loadForPost('post-1');
      expect(controller.errorMessage, isNotNull);
      expect(controller.hasLoaded('post-1'), isFalse);
    });

    test('sunucu yanıtı tutmazsa durum listede değişmiyor', () async {
      final repository = _StubRepository();
      final controller = CommunitySpecialRequestController(
        repository: repository,
      );
      await controller.send(
        postId: 'post-1',
        type: CommunitySpecialRequestType.imeceOffer,
        message: 'Yardım edebilirim.',
      );
      final failing = CommunitySpecialRequestController(
        repository: _StubRepository(failWrites: true),
      );
      final isDone = await failing.updateStatus(
        'request-0',
        CommunitySpecialRequestStatus.accepted,
      );
      expect(isDone, isFalse);
      expect(
        controller.requestsFor('post-1').single.status,
        CommunitySpecialRequestStatus.pending,
      );
    });

    test('kabul edilen istek listede kabul edilmiş görünüyor', () async {
      final controller = CommunitySpecialRequestController(
        repository: _StubRepository(),
      );
      await controller.send(
        postId: 'post-1',
        type: CommunitySpecialRequestType.travelerMatch,
        message: 'Bir paket gönderebilir miyim?',
      );
      final isDone = await controller.updateStatus(
        'request-0',
        CommunitySpecialRequestStatus.accepted,
      );
      expect(isDone, isTrue);
      final saved = controller.requestsFor('post-1').single;
      expect(saved.status, CommunitySpecialRequestStatus.accepted);
      // copyWith diğer alanları düşürmüyor.
      expect(saved.senderName, 'Elif');
      expect(saved.message, 'Bir paket gönderebilir miyim?');
    });
  });

  group('İstek bildirimi', () {
    test('gönderenin adıyla ve paylaşıma bağlanan bir satır üretiyor', () {
      final notification = AppNotificationDto.fromJson({
        'id': 'notification-1',
        'kind': 'special_request',
        'subjectId': 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'subjectTitle': 'İstanbul → New York, 5 kg yerim var',
        'actorCount': 1,
        'actorName': 'Elif',
        'createdAt': '2026-08-13T10:00:00.000Z',
        'isRead': false,
      }).toDomain();
      expect(notification.type, AppNotificationType.specialRequest);
      expect(notification.title, 'Yeni istek');
      expect(notification.body, contains('Elif'));
      expect(notification.body, contains('istek gönderdi'));
      expect(
        notification.deepLink.toString(),
        'turksquare://post/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      );
    });

    test('birden çok bekleyen istek tek satırda toplanıyor', () {
      final notification = AppNotificationDto.fromJson({
        'id': 'notification-1',
        'kind': 'special_request',
        'subjectId': 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'subjectTitle': 'Taşınmaya yardım lazım',
        'actorCount': 3,
        'actorName': 'Elif',
        'createdAt': '2026-08-13T10:00:00.000Z',
        'isRead': false,
      }).toDomain();
      expect(notification.body, contains('Elif ve 2 kişi daha'));
    });
  });
}
