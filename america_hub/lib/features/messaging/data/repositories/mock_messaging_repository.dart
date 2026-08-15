import '../../domain/entities/conversation.dart';
import '../../domain/repositories/messaging_repository.dart';

class MockMessagingRepository implements MessagingRepository {
  final List<Conversation> _inbox = [Conversation(id: 'dm-1', title: 'Elif Demir', preview: 'Kahve için cumartesi uygun mu?', updatedAt: DateTime.now(), kind: ConversationKind.direct, unreadCount: 2, participantId: 'user-elif'), Conversation(id: 'request-1', title: 'Bavulda Yer Var', preview: 'New York → İstanbul için eşleşme talebi', updatedAt: DateTime.now(), kind: ConversationKind.request, unreadCount: 1, contextLabel: '25 Temmuz · Küçük paket')];
  final List<CommunityGroup> _groups = [
    const CommunityGroup(id: 'group-ny', name: 'New York Türkleri', members: 1420, city: 'New York, NY', description: 'Şehre yeni gelenlere ev, iş ve okul konusunda yol gösteriyoruz.'),
    const CommunityGroup(id: 'group-dev', name: 'Bay Area Yazılımcıları', members: 318, city: 'San Francisco, CA', privacy: GroupPrivacy.private, description: 'Vize, mülakat ve referans paylaşımı. Katılım onaya bağlı.'),
  ];

  /// Grup başına üye listesi. Kurucusu olduğumuz gruplarda ayarlar ekranının
  /// gerçekten bir şey göstermesi için burada da veri var.
  final Map<String, List<GroupMember>> _members = {};

  @override
  Future<List<Conversation>> getInbox() async => List.unmodifiable(_inbox);
  @override
  Future<List<CommunityGroup>> getGroups() async => List.unmodifiable(_groups);
  @override
  Future<void> markConversationRead(String id) async { final i=_inbox.indexWhere((item)=>item.id==id); if(i>=0)_inbox[i]=_inbox[i].copyWith(unreadCount: 0); }
  @override
  Future<GroupMembershipStatus> joinGroup(String id) async { final i=_groups.indexWhere((item)=>item.id==id); if(i<0)return GroupMembershipStatus.none; final status=_groups[i].isInvited||_groups[i].privacy==GroupPrivacy.public?GroupMembershipStatus.joined:GroupMembershipStatus.requested; _groups[i]=_groups[i].copyWith(membershipStatus:status); return status; }
  @override
  Future<void> leaveGroup(String id) async { final i=_groups.indexWhere((item)=>item.id==id); if(i>=0)_groups[i]=_groups[i].copyWith(membershipStatus:GroupMembershipStatus.none); }

  @override
  Future<CommunityGroup> createGroup({
    required String name,
    required String city,
    required GroupPrivacy privacy,
    String? imageUrl,
    String? description,
  }) async {
    final group = CommunityGroup(
      id: 'group-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      city: city,
      members: 1,
      privacy: privacy,
      imageUrl: imageUrl,
      description: description,
      isOwner: true,
      membershipStatus: GroupMembershipStatus.joined,
    );
    _groups.insert(0, group);
    _members[group.id] = [
      GroupMember(
        userId: 'me',
        displayName: 'Sen',
        isOwner: true,
        status: GroupMembershipStatus.joined,
        joinedAt: DateTime.now(),
      ),
    ];
    return group;
  }

  @override
  Future<CommunityGroup> updateGroup(
    String groupId, {
    String? name,
    String? city,
    Object? description = _unset,
    Object? imageUrl = _unset,
  }) async {
    final index = _groups.indexWhere((item) => item.id == groupId);
    if (index < 0) throw StateError('Grup bulunamadı.');
    final updated = _groups[index].copyWith(
      name: name,
      city: city,
      description: identical(description, _unset)
          ? CommunityGroup.unchanged
          : description,
      imageUrl: identical(imageUrl, _unset)
          ? CommunityGroup.unchanged
          : imageUrl,
    );
    _groups[index] = updated;
    return updated;
  }

  static const Object _unset = Object();

  @override
  Future<List<GroupMember>> getGroupMembers(String groupId) async =>
      List.unmodifiable(_members[groupId] ?? const <GroupMember>[]);

  @override
  Future<GroupMembershipStatus> inviteGroupMember(
    String groupId,
    String userId,
  ) async {
    final roster = _members.putIfAbsent(groupId, () => <GroupMember>[]);
    if (roster.any((member) => member.userId == userId)) {
      return roster.firstWhere((member) => member.userId == userId).status;
    }
    roster.add(GroupMember(
      userId: userId,
      displayName: null,
      isOwner: false,
      status: GroupMembershipStatus.invited,
      joinedAt: DateTime.now(),
    ));
    return GroupMembershipStatus.invited;
  }

  @override
  Future<void> removeGroupMember(String groupId, String userId) async {
    _members[groupId]?.removeWhere((member) => member.userId == userId);
  }

  @override
  Future<List<GroupJoinRequest>> getJoinRequests(String groupId) async => const [];
  @override
  Future<void> respondToJoinRequest(String groupId, String userId, {required bool accept}) async {}
  @override
  Future<void> respondToRequest(String requestId, RequestDecision decision) async { final i=_inbox.indexWhere((item)=>item.id==requestId); if(i>=0)_inbox[i]=_inbox[i].copyWith(requestDecision:decision,unreadCount:0,kind:decision==RequestDecision.accepted?ConversationKind.direct:ConversationKind.request); }
}
