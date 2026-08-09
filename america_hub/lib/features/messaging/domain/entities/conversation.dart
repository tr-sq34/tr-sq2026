enum ConversationKind { direct, group, request }
enum RequestDecision { pending, accepted, declined }
enum GroupPrivacy { public, private }
enum GroupMembershipStatus { none, requested, joined }

class Conversation {
  const Conversation({required this.id, required this.title, required this.preview, required this.updatedAt, required this.kind, this.unreadCount = 0, this.contextLabel, this.requestDecision = RequestDecision.pending, this.participantId});
  final String id, title, preview;
  final DateTime updatedAt;
  final ConversationKind kind;
  final int unreadCount;
  final String? contextLabel;
  final RequestDecision requestDecision;
  /// The other side of a direct thread. Null for a group, where there is no
  /// single counterparty — which is why blocking is offered per message there
  /// rather than for the whole thread.
  final String? participantId;
  Conversation copyWith({int? unreadCount, RequestDecision? requestDecision, ConversationKind? kind}) => Conversation(id: id, title: title, preview: preview, updatedAt: updatedAt, kind: kind ?? this.kind, unreadCount: unreadCount ?? this.unreadCount, contextLabel: contextLabel, requestDecision: requestDecision ?? this.requestDecision, participantId: participantId);
}

class CommunityGroup {
  const CommunityGroup({required this.id, required this.name, required this.members, required this.city, this.privacy = GroupPrivacy.public, this.imageUrl, this.isOwner = false, this.membershipStatus = GroupMembershipStatus.none});
  final String id, name, city;
  final int members;
  final GroupPrivacy privacy;
  final String? imageUrl;
  /// True only for the account that created the group. Owners moderate the
  /// Matrix room and are the only ones who see pending join requests.
  final bool isOwner;
  final GroupMembershipStatus membershipStatus;
  bool get isJoined => membershipStatus == GroupMembershipStatus.joined;
  bool get isPending => membershipStatus == GroupMembershipStatus.requested;
  CommunityGroup copyWith({GroupMembershipStatus? membershipStatus, int? members}) => CommunityGroup(id: id, name: name, members: members ?? this.members, city: city, privacy: privacy, imageUrl: imageUrl, isOwner: isOwner, membershipStatus: membershipStatus ?? this.membershipStatus);
}

/// Somebody waiting for an owner to let them into a private group.
class GroupJoinRequest {
  const GroupJoinRequest({required this.userId, required this.displayName, required this.requestedAt});
  final String userId;
  /// Null until the requester's profile reaches the messaging projection.
  final String? displayName;
  final DateTime requestedAt;
}
