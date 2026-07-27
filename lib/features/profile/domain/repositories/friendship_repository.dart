import '../entities/friendship.dart';
abstract interface class FriendshipRepository { Future<FriendshipStatus> getStatus(String userId); Future<void> sendRequest(String userId); Future<void> respond(String userId, bool accepted); Future<void> block(String userId); }
