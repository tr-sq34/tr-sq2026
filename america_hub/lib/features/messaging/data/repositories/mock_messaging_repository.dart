import '../../domain/entities/conversation.dart';
import '../../domain/repositories/messaging_repository.dart';

class MockMessagingRepository implements MessagingRepository {
  final List<Conversation> _inbox = [Conversation(id: 'dm-1', title: 'Elif Demir', preview: 'Kahve için cumartesi uygun mu?', updatedAt: DateTime.now(), kind: ConversationKind.direct, unreadCount: 2, participantId: 'user-elif'), Conversation(id: 'request-1', title: 'Bavulda Yer Var', preview: 'New York → İstanbul için eşleşme talebi', updatedAt: DateTime.now(), kind: ConversationKind.request, unreadCount: 1, contextLabel: '25 Temmuz · Küçük paket')];
  final List<CommunityGroup> _groups = [const CommunityGroup(id: 'group-ny', name: 'New York Türkleri', members: 1420, city: 'New York, NY'), const CommunityGroup(id: 'group-dev', name: 'Bay Area Yazılımcıları', members: 318, city: 'San Francisco, CA', privacy: GroupPrivacy.private)];
  Future<List<Conversation>> getInbox() async => List.unmodifiable(_inbox);
  Future<List<CommunityGroup>> getGroups() async => List.unmodifiable(_groups);
  Future<void> markConversationRead(String id) async { final i=_inbox.indexWhere((item)=>item.id==id); if(i>=0)_inbox[i]=_inbox[i].copyWith(unreadCount: 0); }
  @override
  Future<GroupMembershipStatus> joinGroup(String id) async { final i=_groups.indexWhere((item)=>item.id==id); if(i<0)return GroupMembershipStatus.none; final status=_groups[i].privacy==GroupPrivacy.public?GroupMembershipStatus.joined:GroupMembershipStatus.requested; _groups[i]=_groups[i].copyWith(membershipStatus:status); return status; }
  @override
  Future<void> leaveGroup(String id) async { final i=_groups.indexWhere((item)=>item.id==id); if(i>=0)_groups[i]=_groups[i].copyWith(membershipStatus:GroupMembershipStatus.none); }
  @override
  Future<CommunityGroup> createGroup({required String name, required String city, required GroupPrivacy privacy, String? imageUrl}) async { final group=CommunityGroup(id:'group-${DateTime.now().microsecondsSinceEpoch}',name:name,city:city,members:1,privacy:privacy,imageUrl:imageUrl,isOwner:true,membershipStatus:GroupMembershipStatus.joined); _groups.insert(0,group); return group; }
  @override
  Future<List<GroupJoinRequest>> getJoinRequests(String groupId) async => const [];
  @override
  Future<void> respondToJoinRequest(String groupId, String userId, {required bool accept}) async {}
  @override
  Future<void> respondToRequest(String requestId, RequestDecision decision) async { final i=_inbox.indexWhere((item)=>item.id==requestId); if(i>=0)_inbox[i]=_inbox[i].copyWith(requestDecision:decision,unreadCount:0,kind:decision==RequestDecision.accepted?ConversationKind.direct:ConversationKind.request); }
}
