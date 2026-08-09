import '../entities/conversation.dart';

abstract interface class MessagingRepository {
  Future<List<Conversation>> getInbox();
  Future<List<CommunityGroup>> getGroups();
  Future<void> markConversationRead(String conversationId);

  /// Returns the membership the server settled on: joining a public group takes
  /// effect immediately, a private one only queues a request. The caller must
  /// not assume which happened — a group can be made private between the list
  /// load and the tap.
  Future<GroupMembershipStatus> joinGroup(String groupId);
  Future<void> leaveGroup(String groupId);
  Future<CommunityGroup> createGroup({required String name, required String city, required GroupPrivacy privacy, String? imageUrl});
  Future<List<GroupJoinRequest>> getJoinRequests(String groupId);
  Future<void> respondToJoinRequest(String groupId, String userId, {required bool accept});
  Future<void> respondToRequest(String requestId, RequestDecision decision);
}
