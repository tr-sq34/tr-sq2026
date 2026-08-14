import 'package:america_hub/core/navigation/app_deep_link.dart';
import 'package:america_hub/core/network/api_client.dart';
import 'package:america_hub/core/storage/in_memory_token_store.dart';
import 'package:america_hub/features/notifications/data/dtos/app_notification_dto.dart';
import 'package:america_hub/features/notifications/domain/entities/app_notification.dart';
import 'package:america_hub/features/profile/application/friendship_controller.dart';
import 'package:america_hub/features/profile/data/repositories/api_friendship_repository.dart';
import 'package:america_hub/features/profile/domain/entities/friendship.dart';
import 'package:america_hub/features/profile/domain/repositories/friendship_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_adapter.dart';

Map<String, dynamic> requestRow({
  String id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  String userId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  String direction = 'incoming',
  String displayName = 'Elif',
}) => {
  'id': id,
  'userId': userId,
  'displayName': displayName,
  'direction': direction,
  'createdAt': '2026-08-13T10:00:00.000Z',
};

({ApiFriendshipRepository repository, RecordingAdapter adapter}) build(
  List<Object?> bodies,
) {
  final adapter = RecordingAdapter.sequence(bodies);
  final dio = Dio(BaseOptions(baseUrl: 'https://community.test/v1/'))
    ..httpClientAdapter = adapter;
  return (
    repository: ApiFriendshipRepository(
      client: ApiClient(tokenStore: InMemoryTokenStore(), dio: dio),
    ),
    adapter: adapter,
  );
}

/// Sunucusuz depo: denetleyicinin hata karşısındaki davranışını sınamak için.
class _StubRepository implements FriendshipRepository {
  _StubRepository({this.fail = false});

  final bool fail;
  final List<FriendRequest> requests = [];
  final List<FriendSummary> friends = [];
  FriendshipStatus sendResult = FriendshipStatus.pendingOutgoing;
  final List<String> calls = [];

  @override
  Future<FriendshipStatus> getStatus(String userId) async =>
      FriendshipStatus.none;

  @override
  Future<FriendshipStatus> sendRequest(String userId) async {
    calls.add('send:$userId');
    if (fail) throw Exception('offline');
    return sendResult;
  }

  @override
  Future<FriendshipStatus> respond(String requestId, bool accepted) async {
    calls.add('respond:$requestId:$accepted');
    if (fail) throw Exception('offline');
    requests.removeWhere((item) => item.id == requestId);
    return accepted ? FriendshipStatus.friends : FriendshipStatus.none;
  }

  @override
  Future<void> cancelRequest(String requestId) async {
    calls.add('cancel:$requestId');
    if (fail) throw Exception('offline');
    requests.removeWhere((item) => item.id == requestId);
  }

  @override
  Future<void> unfriend(String userId) async {
    calls.add('unfriend:$userId');
    if (fail) throw Exception('offline');
    friends.removeWhere((item) => item.userId == userId);
  }

  @override
  Future<void> block(String userId) async {
    calls.add('block:$userId');
    if (fail) throw Exception('offline');
  }

  @override
  Future<List<FriendRequest>> getRequests() async {
    if (fail) throw Exception('offline');
    return List.of(requests);
  }

  @override
  Future<List<FriendSummary>> getFriends([String? userId]) async {
    if (fail) throw Exception('offline');
    return List.of(friends);
  }
}

FriendRequest incoming(String id, String userId) => FriendRequest(
  id: id,
  userId: userId,
  displayName: 'Elif',
  createdAt: DateTime(2026, 8, 13),
  isIncoming: true,
);

void main() {
  test('istek gonderirken sunucuya yalnizca uye kimligi gidiyor', () async {
    final harness = build([
      {
        'data': {'relationship': 'pendingOutgoing'},
      },
    ]);

    final status = await harness.repository.sendRequest('member-1');

    expect(status, FriendshipStatus.pendingOutgoing);
    expect(harness.adapter.requests.single.method, 'POST');
    expect(harness.adapter.requests.single.path, '/community/friends/requests');
    expect(harness.adapter.requests.single.data, {'userId': 'member-1'});
  });

  test('karsilikli istek sunucuda arkadasliga donusuyor', () async {
    final harness = build([
      {
        'data': {'relationship': 'friends'},
      },
    ]);

    expect(
      await harness.repository.sendRequest('member-1'),
      FriendshipStatus.friends,
    );
  });

  test('tanimadigi durum "iliski yok" sayiliyor', () async {
    final harness = build([
      {
        'data': {'relationship': 'sicak-arkadaslik'},
      },
    ]);

    expect(
      await harness.repository.getStatus('member-1'),
      FriendshipStatus.none,
    );
  });

  test('yanit isteğin kimligiyle gidiyor, kisinin kimligiyle degil', () async {
    final harness = build([
      {
        'data': {'relationship': 'friends'},
      },
    ]);

    await harness.repository.respond('request-9', true);

    expect(harness.adapter.requests.single.method, 'PUT');
    expect(
      harness.adapter.requests.single.path,
      '/community/friends/requests/request-9',
    );
    expect(harness.adapter.requests.single.data, {'status': 'accepted'});
  });

  test('istek listesi yonune gore ayriliyor', () async {
    final harness = build([
      {
        'data': [
          requestRow(id: 'r1'),
          requestRow(id: 'r2', direction: 'outgoing'),
        ],
      },
    ]);

    final requests = await harness.repository.getRequests();

    expect(requests.map((item) => item.isIncoming), [true, false]);
    expect(requests.first.displayName, 'Elif');
  });

  test('baskasinin listesi userId ile isteniyor', () async {
    final harness = build([
      {'data': []},
    ]);

    await harness.repository.getFriends('member-2');

    expect(harness.adapter.requests.single.queryParameters, {
      'userId': 'member-2',
    });
  });

  test('kendi listesinde userId gonderilmiyor', () async {
    final harness = build([
      {'data': []},
    ]);

    await harness.repository.getFriends();

    expect(harness.adapter.requests.single.queryParameters, isEmpty);
  });

  test('kabul edilen istek listeden dusuyor ve durum arkadas oluyor', () async {
    final repository = _StubRepository()
      ..requests.add(incoming('r1', 'member-1'));
    final controller = FriendshipController(repository: repository);
    await controller.load();

    expect(await controller.respond('r1', true), isTrue);

    expect(controller.requests, isEmpty);
    expect(controller.statusOf('member-1'), FriendshipStatus.friends);
  });

  test('sunucu yanit vermezse istek listede kaliyor', () async {
    final repository = _StubRepository(fail: true);
    final controller = FriendshipController(repository: repository);
    controller.requests = [incoming('r1', 'member-1')];

    expect(await controller.respond('r1', false), isFalse);

    expect(controller.requests, hasLength(1));
    expect(controller.errorMessage, isNotNull);
  });

  test('yuklenmis liste uye basina ayri istek gerektirmiyor', () async {
    final repository = _StubRepository()
      ..friends.add(
        const FriendSummary(userId: 'member-7', displayName: 'Elif'),
      )
      ..requests.add(incoming('r1', 'member-1'));
    final controller = FriendshipController(repository: repository);
    await controller.load();

    expect(controller.statusOf('member-7'), FriendshipStatus.friends);
    expect(controller.statusOf('member-1'), FriendshipStatus.pendingIncoming);
    expect(controller.statusOf('member-9'), FriendshipStatus.none);
  });

  test('karsilikli istekte durum beklemede degil arkadas yaziliyor', () async {
    final repository = _StubRepository()..sendResult = FriendshipStatus.friends;
    final controller = FriendshipController(repository: repository);

    expect(await controller.send('member-1'), isTrue);

    expect(controller.statusOf('member-1'), FriendshipStatus.friends);
  });

  test('arkadaslikten cikarilan kisi listeden dusuyor', () async {
    final repository = _StubRepository()
      ..friends.add(
        const FriendSummary(userId: 'member-7', displayName: 'Elif'),
      );
    final controller = FriendshipController(repository: repository);
    await controller.load();

    expect(await controller.unfriend('member-7'), isTrue);

    expect(controller.friends, isEmpty);
    expect(controller.statusOf('member-7'), FriendshipStatus.none);
  });

  test('geri cekilen istek listeden dusuyor', () async {
    final repository = _StubRepository();
    final controller = FriendshipController(repository: repository);
    controller.requests = [
      FriendRequest(
        id: 'r1',
        userId: 'member-1',
        displayName: 'Elif',
        createdAt: DateTime(2026, 8, 13),
        isIncoming: false,
      ),
    ];

    expect(await controller.cancelRequest('r1'), isTrue);

    expect(controller.requests, isEmpty);
    expect(repository.calls, contains('cancel:r1'));
  });

  test('arkadaslik bildirimi kendi cumlesini ve baglantisini kuruyor', () {
    final notification = AppNotificationDto.fromJson({
      'id': 'n1',
      'kind': 'friend_request',
      'subjectId': 'member-1',
      'subjectTitle': 'Elif',
      'actorCount': 1,
      'actorName': 'Elif',
      'createdAt': '2026-08-13T10:00:00.000Z',
      'isRead': false,
    }).toDomain();

    expect(notification.type, AppNotificationType.friendRequest);
    expect(notification.title, 'Arkadaşlık isteği');
    expect(notification.body, 'Elif sana arkadaşlık isteği gönderdi.');
    expect(notification.deepLink.toString(), 'turksquare://friend/member-1');
  });

  test('arkadaslik baglantisi uye kimligine cozuluyor', () {
    final link = AppDeepLink.parse(Uri.parse('turksquare://friend/member-1'));

    expect(link, isA<FriendRequestDeepLink>());
    expect((link as FriendRequestDeepLink).memberId, 'member-1');
  });
}
