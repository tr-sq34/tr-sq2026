enum ConversationKind { direct, group, request }
enum RequestDecision { pending, accepted, declined }
enum GroupPrivacy { public, private }

/// Bir üyenin bir gruba göre durduğu yer.
///
/// [invited] sonradan eklendi ve yönü ötekilerin tersi: [requested] üyenin
/// kapıyı çalması, [invited] ise kurucunun kapıyı açıp beklemesi. İkisini tek
/// duruma sıkıştırmak, davet edilen kişiye "isteğin onay bekliyor" demek
/// olurdu; oysa onay zaten verilmiş, karar artık kendisinde.
enum GroupMembershipStatus { none, requested, invited, joined }

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
  const CommunityGroup({
    required this.id,
    required this.name,
    required this.members,
    required this.city,
    this.privacy = GroupPrivacy.public,
    this.imageUrl,
    this.description,
    this.isOwner = false,
    this.membershipStatus = GroupMembershipStatus.none,
  });
  final String id, name, city;
  final int members;
  final GroupPrivacy privacy;
  final String? imageUrl;

  /// Grubun ne için kurulduğu. Ad ve şehir grubun nerede olduğunu söylüyor, ne
  /// olduğunu değil: "New York Türkleri" bir yeni gelen yardımlaşması da olur,
  /// maç izleme grubu da. Katılmaya karar verecek kişinin okuyacağı tek metin.
  final String? description;

  /// True only for the account that created the group. Owners moderate the
  /// Matrix room and are the only ones who see pending join requests.
  final bool isOwner;
  final GroupMembershipStatus membershipStatus;
  bool get isJoined => membershipStatus == GroupMembershipStatus.joined;
  bool get isPending => membershipStatus == GroupMembershipStatus.requested;

  /// Kurucu çağırdı, cevap üyede. Kartta "Katıl" değil "Daveti kabul et"
  /// yazmasının sebebi bu.
  bool get isInvited => membershipStatus == GroupMembershipStatus.invited;

  CommunityGroup copyWith({
    GroupMembershipStatus? membershipStatus,
    int? members,
    String? name,
    String? city,
    // Bu ikisi silinebiliyor, o yüzden "verilmedi" ile "boşaltıldı" ayrı
    // taşınıyor: null bir değer geçersiz sayılsaydı kapak fotoğrafı hiç
    // kaldırılamazdı.
    Object? description = unchanged,
    Object? imageUrl = unchanged,
  }) => CommunityGroup(
    id: id,
    name: name ?? this.name,
    members: members ?? this.members,
    city: city ?? this.city,
    privacy: privacy,
    imageUrl: identical(imageUrl, unchanged) ? this.imageUrl : imageUrl as String?,
    description: identical(description, unchanged) ? this.description : description as String?,
    isOwner: isOwner,
    membershipStatus: membershipStatus ?? this.membershipStatus,
  );

  /// "Bu alana dokunma" demenin yolu. `null` gerçek bir değer — alanı boşaltmak
  /// demek — olduğu için varsayılan olarak kullanılamıyor.
  static const Object unchanged = Object();
}

/// Somebody waiting for an owner to let them into a private group.
class GroupJoinRequest {
  const GroupJoinRequest({required this.userId, required this.displayName, required this.requestedAt});
  final String userId;
  /// Null until the requester's profile reaches the messaging projection.
  final String? displayName;
  final DateTime requestedAt;
}

/// Gruptaki bir kişi.
///
/// Daveti bekleyenler de bu listede: kurucunun aynı kişiyi ikinci kez davet
/// etmemesi için davetin gönderildiğini görmesi gerekiyor. Katılma isteği
/// gönderenler burada değil — onlar yalnızca kurucunun gördüğü ayrı bir liste.
class GroupMember {
  const GroupMember({
    required this.userId,
    required this.displayName,
    required this.isOwner,
    required this.status,
    required this.joinedAt,
  });
  final String userId;
  /// Üyenin adı henüz mesajlaşma izdüşümüne ulaşmadıysa null.
  final String? displayName;
  final bool isOwner;
  final GroupMembershipStatus status;
  final DateTime joinedAt;
  bool get isInvitePending => status == GroupMembershipStatus.invited;
}
