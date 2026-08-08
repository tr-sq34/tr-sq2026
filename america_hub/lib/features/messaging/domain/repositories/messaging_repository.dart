import '../entities/conversation.dart';

abstract interface class MessagingRepository {
  Future<List<Conversation>> getInbox();
  Future<List<CommunityGroup>> getGroups();
  Future<void> markConversationRead(String conversationId);
  Future<void> joinGroup(String groupId);
  Future<CommunityGroup> createGroup({required String name, required String city, required GroupPrivacy privacy, String? imageUrl});
  Future<void> respondToRequest(String requestId, RequestDecision decision);
}
