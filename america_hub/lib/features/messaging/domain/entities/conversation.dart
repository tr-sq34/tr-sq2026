enum ConversationKind { direct, group, request }
enum RequestDecision { pending, accepted, declined }
enum GroupPrivacy { public, private }
enum GroupMembershipStatus { none, requested, joined }

class Conversation {
  const Conversation({required this.id, required this.title, required this.preview, required this.updatedAt, required this.kind, this.unreadCount = 0, this.contextLabel, this.requestDecision = RequestDecision.pending});
  final String id, title, preview;
  final DateTime updatedAt;
  final ConversationKind kind;
  final int unreadCount;
  final String? contextLabel;
  final RequestDecision requestDecision;
  Conversation copyWith({int? unreadCount, RequestDecision? requestDecision, ConversationKind? kind}) => Conversation(id: id, title: title, preview: preview, updatedAt: updatedAt, kind: kind ?? this.kind, unreadCount: unreadCount ?? this.unreadCount, contextLabel: contextLabel, requestDecision: requestDecision ?? this.requestDecision);
}

class CommunityGroup {
  const CommunityGroup({required this.id, required this.name, required this.members, required this.city, this.privacy = GroupPrivacy.public, this.imageUrl, this.adminIds = const ['local-user'], this.membershipStatus = GroupMembershipStatus.none});
  final String id, name, city;
  final int members;
  final GroupPrivacy privacy;
  final String? imageUrl;
  final List<String> adminIds;
  final GroupMembershipStatus membershipStatus;
  bool get isJoined => membershipStatus == GroupMembershipStatus.joined;
  CommunityGroup copyWith({GroupMembershipStatus? membershipStatus, List<String>? adminIds}) => CommunityGroup(id: id, name: name, members: members, city: city, privacy: privacy, imageUrl: imageUrl, adminIds: adminIds ?? this.adminIds, membershipStatus: membershipStatus ?? this.membershipStatus);
}
