import '../../domain/entities/friendship.dart';
import '../../domain/repositories/friendship_repository.dart';

/// Sadece `USE_MOCK_SERVICES` açıkken kullanılıyor. Bellekte durur, uygulama
/// kapanınca kaybolur.
class MockFriendshipRepository implements FriendshipRepository {
  final Map<String, FriendshipStatus> _statuses = {};
  final Map<String, FriendRequest> _requests = {};
  int _seq = 0;

  @override
  Future<FriendshipStatus> getStatus(String userId) async =>
      _statuses[userId] ?? FriendshipStatus.none;

  @override
  Future<FriendshipStatus> sendRequest(String userId) async {
    final id = 'mock-request-${_seq++}';
    _requests[id] = FriendRequest(
      id: id,
      userId: userId,
      displayName: 'TurkSquare üyesi',
      createdAt: DateTime.now(),
      isIncoming: false,
    );
    return _statuses[userId] = FriendshipStatus.pendingOutgoing;
  }

  @override
  Future<FriendshipStatus> respond(String requestId, bool accepted) async {
    final request = _requests.remove(requestId);
    final status = accepted ? FriendshipStatus.friends : FriendshipStatus.none;
    if (request != null) _statuses[request.userId] = status;
    return status;
  }

  @override
  Future<void> cancelRequest(String requestId) async {
    final request = _requests.remove(requestId);
    if (request != null) _statuses.remove(request.userId);
  }

  @override
  Future<void> unfriend(String userId) async => _statuses.remove(userId);

  @override
  Future<void> block(String userId) async {
    _statuses[userId] = FriendshipStatus.blocked;
    _requests.removeWhere((_, request) => request.userId == userId);
  }

  @override
  Future<List<FriendRequest>> getRequests() async =>
      _requests.values.toList(growable: false);

  @override
  Future<List<FriendSummary>> getFriends([String? userId]) async => _statuses
      .entries
      .where((entry) => entry.value == FriendshipStatus.friends)
      .map(
        (entry) =>
            FriendSummary(userId: entry.key, displayName: 'TurkSquare üyesi'),
      )
      .toList(growable: false);
}
