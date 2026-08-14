import '../../../../core/network/api_client.dart';
import '../../domain/entities/friendship.dart';
import '../../domain/repositories/friendship_repository.dart';

/// Arkadaşlık.
///
/// Bu depoya kadar arkadaşlık diye bir şey yoktu. `relationship_projection`
/// sunucuda ikinci göçten beri duruyor ve neredeyse her erişim kararı onu
/// okuyor - hangi paylaşımı görebildiğin, kimin Story'sinin çıktığı, profildeki
/// arkadaş sayısı, mesaj açılıp açılamayacağı - ama hiçbir şey içine satır
/// yazmıyordu. Yani üretimde herkesin arkadaş sayısı sıfırdı ve kimse kimseyle
/// mesajlaşamıyordu.
class ApiFriendshipRepository implements FriendshipRepository {
  ApiFriendshipRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;

  @override
  Future<FriendshipStatus> getStatus(String userId) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/community/friends/status/$userId',
    );
    return _statusOf(
      (response.data?['data'] as Map<String, dynamic>?)?['relationship'],
    );
  }

  @override
  Future<FriendshipStatus> sendRequest(String userId) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/community/friends/requests',
      data: {'userId': userId},
    );
    return _statusOf(
      (response.data?['data'] as Map<String, dynamic>?)?['relationship'],
    );
  }

  @override
  Future<FriendshipStatus> respond(String requestId, bool accepted) async {
    final response = await _client.put<Map<String, dynamic>>(
      '/community/friends/requests/$requestId',
      data: {'status': accepted ? 'accepted' : 'declined'},
    );
    return _statusOf(
      (response.data?['data'] as Map<String, dynamic>?)?['relationship'],
    );
  }

  @override
  Future<void> cancelRequest(String requestId) =>
      _client.delete<void>('/community/friends/requests/$requestId');

  @override
  Future<void> unfriend(String userId) =>
      _client.delete<void>('/community/friends/$userId');

  @override
  Future<void> block(String userId) =>
      _client.post<void>('/community/blocks', data: {'userId': userId});

  @override
  Future<List<FriendRequest>> getRequests() async {
    final response = await _client.get<Map<String, dynamic>>(
      '/community/friends/requests',
    );
    final data = response.data?['data'] as List<dynamic>? ?? const [];
    return data.map((raw) {
      final json = raw as Map<String, dynamic>;
      return FriendRequest(
        id: json['id'] as String,
        userId: json['userId'] as String? ?? '',
        displayName: json['displayName'] as String? ?? 'TurkSquare üyesi',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
        isIncoming: json['direction'] == 'incoming',
        avatarUrl: json['avatarUrl'] as String?,
      );
    }).toList(growable: false);
  }

  @override
  Future<List<FriendSummary>> getFriends([String? userId]) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/community/friends',
      queryParameters: {'userId': ?userId},
    );
    final data = response.data?['data'] as List<dynamic>? ?? const [];
    return data.map((raw) {
      final json = raw as Map<String, dynamic>;
      return FriendSummary(
        userId: json['userId'] as String,
        displayName: json['displayName'] as String? ?? 'TurkSquare üyesi',
        city: json['city'] as String?,
        regionCode: json['regionCode'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
      );
    }).toList(growable: false);
  }

  /// Tanımadığı bir durum "ilişki yok" sayılıyor: bilinmeyen bir kelimeye
  /// bakıp "arkadaşsınız" demek, olmayan bir izni açmak olurdu.
  static FriendshipStatus _statusOf(Object? raw) => switch (raw) {
    'friends' => FriendshipStatus.friends,
    'pendingIncoming' => FriendshipStatus.pendingIncoming,
    'pendingOutgoing' => FriendshipStatus.pendingOutgoing,
    'blocked' => FriendshipStatus.blocked,
    _ => FriendshipStatus.none,
  };
}
