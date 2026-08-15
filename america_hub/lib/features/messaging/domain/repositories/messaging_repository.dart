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
  Future<CommunityGroup> createGroup({
    required String name,
    required String city,
    required GroupPrivacy privacy,
    String? imageUrl,
    String? description,
  });

  /// Kurucunun sonradan değiştirebildiği her şey.
  ///
  /// Gizlilik burada yok: o hem odanın katılım kuralı hem de geçmişin kime
  /// göründüğü demek, tek bir alan değil. Açık bir grubu gizliye çevirmek
  /// halihazırda katılmış herkese geçmişi okunur bırakırdı — kurucuya ise
  /// grubun kapandığını düşündürürdü.
  ///
  /// [description] ve [imageUrl] için `null` "boşalt" demek, bu yüzden ikisi de
  /// gönderilmediklerinde atlanıyor.
  Future<CommunityGroup> updateGroup(
    String groupId, {
    String? name,
    String? city,
    Object? description,
    Object? imageUrl,
  });

  /// Gruptakiler ve daveti bekleyenler. Yalnızca gruba katılmış biri okuyabilir.
  Future<List<GroupMember>> getGroupMembers(String groupId);

  /// Kurucu birini gruba çağırıyor. Dönen durum daveti bekleyen kişinin
  /// durumu — davet edilmek katılmak değildir.
  Future<GroupMembershipStatus> inviteGroupMember(String groupId, String userId);

  /// Kurucu birini gruptan çıkarıyor ya da gönderdiği daveti geri alıyor.
  Future<void> removeGroupMember(String groupId, String userId);

  Future<List<GroupJoinRequest>> getJoinRequests(String groupId);
  Future<void> respondToJoinRequest(String groupId, String userId, {required bool accept});
  Future<void> respondToRequest(String requestId, RequestDecision decision);
}
