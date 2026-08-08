import '../../domain/entities/friendship.dart';
import '../../domain/repositories/friendship_repository.dart';
class MockFriendshipRepository implements FriendshipRepository { final Map<String,FriendshipStatus> _items={}; Future<FriendshipStatus> getStatus(String id) async=>_items[id]??FriendshipStatus.none; Future<void> sendRequest(String id) async{_items[id]=FriendshipStatus.pendingOutgoing;} Future<void> respond(String id,bool accepted) async{_items[id]=accepted?FriendshipStatus.friends:FriendshipStatus.none;} Future<void> block(String id) async{_items[id]=FriendshipStatus.blocked;} }
