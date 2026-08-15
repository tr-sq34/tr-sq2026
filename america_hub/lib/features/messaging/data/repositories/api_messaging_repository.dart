import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/pagination/cursor_page.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/direct_message.dart';
import '../../domain/repositories/direct_message_repository.dart';
import '../../domain/repositories/messaging_repository.dart';

/// Talks to the messaging gateway.
///
/// Direct conversations and groups are both Matrix rooms behind the same
/// message routes, so a group ID is a valid conversation ID here. Match
/// requests are the one part with no backend yet, and that method says so
/// rather than returning invented data.
class ApiMessagingRepository
    implements MessagingRepository, DirectMessageRepository {
  ApiMessagingRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;

  @override
  Future<List<Conversation>> getInbox() async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.messagingConversations,
      queryParameters: {'limit': 30},
    );
    final rows = (response.data?['data'] as List<dynamic>? ?? const []);
    return rows
        .map((row) => _toConversation(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  Conversation _toConversation(Map<String, dynamic> json) => Conversation(
    id: json['id'] as String,
    // The projection is the only source of names here. It is empty until the
    // participant has verified their email, which is also when they become
    // reachable at all.
    title: (json['participantDisplayName'] as String?)?.trim().isNotEmpty ??
            false
        ? json['participantDisplayName'] as String
        : 'TurkSquare üyesi',
    // Deliberately blank. Message bodies are never stored outside the
    // homeserver, so a preview would mean fetching the last event of every
    // conversation in the list on every inbox load.
    preview: '',
    updatedAt: DateTime.parse(json['lastMessageAt'] as String).toLocal(),
    kind: ConversationKind.direct,
    // Who to block if the user asks to. The gateway resolves it per viewer, so
    // it is already the other side rather than either end of the pair.
    participantId: json['participantId'] as String?,
  );

  @override
  Future<CursorPage<DirectMessage>> fetchMessages(
    String conversationId, {
    String? cursor,
    int limit = 30,
  }) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.messagingConversationMessages(conversationId),
      // `from` is omitted rather than sent empty: the gateway forwards it to
      // the homeserver verbatim, where a blank pagination token is an error.
      queryParameters: {'from': ?cursor, 'limit': limit},
    );
    final rows = (response.data?['data'] as List<dynamic>? ?? const []);
    return CursorPage(
      items: rows
          .map((row) => DirectMessage.fromJson(row as Map<String, dynamic>))
          .toList(growable: false),
      nextCursor: response.data?['nextCursor'] as String?,
    );
  }

  @override
  Future<String> sendMessage({
    required String conversationId,
    required String body,
    required String idempotencyKey,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.messagingConversationMessages(conversationId),
      data: {'body': body, 'idempotencyKey': idempotencyKey},
    );
    final data = response.data?['data'] as Map<String, dynamic>?;
    return data?['eventId'] as String? ?? idempotencyKey;
  }

  @override
  Future<Conversation> openDirectConversation(String targetUserId) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.messagingDirectConversations,
      data: {'targetUserId': targetUserId},
    );
    return _toConversation(response.data!['data'] as Map<String, dynamic>);
  }

  @override
  Future<List<CommunityGroup>> getGroups() async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.messagingGroups,
      queryParameters: {'limit': 50},
    );
    final rows = (response.data?['data'] as List<dynamic>? ?? const []);
    return rows
        .map((row) => _toGroup(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  CommunityGroup _toGroup(Map<String, dynamic> json) => CommunityGroup(
    id: json['id'] as String,
    name: json['name'] as String,
    city: json['city'] as String,
    members: (json['memberCount'] as num?)?.toInt() ?? 0,
    privacy: _privacy(json['privacy'] as String?),
    imageUrl: json['imageUrl'] as String?,
    description: json['description'] as String?,
    isOwner: json['role'] == 'owner',
    membershipStatus: _membership(json['membershipStatus'] as String?),
  );

  static GroupPrivacy _privacy(String? value) =>
      value == 'private' ? GroupPrivacy.private : GroupPrivacy.public;

  // Anything the server has not taught this build about is treated as "not a
  // member", which is the state that unlocks the fewest actions.
  static GroupMembershipStatus _membership(String? value) => switch (value) {
    'joined' => GroupMembershipStatus.joined,
    'requested' => GroupMembershipStatus.requested,
    'invited' => GroupMembershipStatus.invited,
    _ => GroupMembershipStatus.none,
  };

  /// The gateway has no read-receipt endpoint yet, so unread state is local to
  /// the device. Silently doing nothing is correct here: the caller only needs
  /// the badge cleared.
  @override
  Future<void> markConversationRead(String conversationId) async {}

  @override
  Future<GroupMembershipStatus> joinGroup(String groupId) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.messagingGroupJoin(groupId),
    );
    final data = response.data?['data'] as Map<String, dynamic>?;
    return _membership(data?['membershipStatus'] as String?);
  }

  @override
  Future<void> leaveGroup(String groupId) =>
      _client.post<Map<String, dynamic>>(ApiEndpoints.messagingGroupLeave(groupId));

  @override
  Future<CommunityGroup> createGroup({
    required String name,
    required String city,
    required GroupPrivacy privacy,
    String? imageUrl,
    String? description,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.messagingGroups,
      data: {
        'name': name,
        'city': city,
        'privacy': privacy.name,
        'imageUrl': ?imageUrl,
        'description': ?description,
      },
    );
    return _toGroup(response.data!['data'] as Map<String, dynamic>);
  }

  @override
  Future<CommunityGroup> updateGroup(
    String groupId, {
    String? name,
    String? city,
    Object? description = _unset,
    Object? imageUrl = _unset,
  }) async {
    final response = await _client.patch<Map<String, dynamic>>(
      ApiEndpoints.messagingGroup(groupId),
      // Gönderilmeyen alan olduğu gibi kalıyor, açıkça `null` gönderilen alan
      // siliniyor. Dokunulmamış bir alanı da null göndermek, kurucu yalnızca
      // adı değiştirdiğinde açıklamayı sessizce silerdi.
      data: {
        'name': ?name,
        'city': ?city,
        if (!identical(description, _unset)) 'description': description,
        if (!identical(imageUrl, _unset)) 'imageUrl': imageUrl,
      },
    );
    return _toGroup(response.data!['data'] as Map<String, dynamic>);
  }

  static const Object _unset = Object();

  @override
  Future<List<GroupMember>> getGroupMembers(String groupId) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.messagingGroupMembers(groupId),
    );
    final rows = (response.data?['data'] as List<dynamic>? ?? const []);
    return rows.map((row) {
      final json = row as Map<String, dynamic>;
      return GroupMember(
        userId: json['userId'] as String,
        displayName: json['displayName'] as String?,
        isOwner: json['role'] == 'owner',
        status: _membership(json['status'] as String?),
        joinedAt: DateTime.parse(json['joinedAt'] as String).toLocal(),
      );
    }).toList(growable: false);
  }

  @override
  Future<GroupMembershipStatus> inviteGroupMember(
    String groupId,
    String userId,
  ) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.messagingGroupMembers(groupId),
      data: {'userId': userId},
    );
    final data = response.data?['data'] as Map<String, dynamic>?;
    return _membership(data?['membershipStatus'] as String?);
  }

  @override
  Future<void> removeGroupMember(String groupId, String userId) =>
      _client.delete<Map<String, dynamic>>(
        ApiEndpoints.messagingGroupMember(groupId, userId),
      );

  @override
  Future<List<GroupJoinRequest>> getJoinRequests(String groupId) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.messagingGroupRequests(groupId),
    );
    final rows = (response.data?['data'] as List<dynamic>? ?? const []);
    return rows.map((row) {
      final json = row as Map<String, dynamic>;
      return GroupJoinRequest(
        userId: json['userId'] as String,
        displayName: json['displayName'] as String?,
        requestedAt: DateTime.parse(json['requestedAt'] as String).toLocal(),
      );
    }).toList(growable: false);
  }

  @override
  Future<void> respondToJoinRequest(
    String groupId,
    String userId, {
    required bool accept,
  }) => _client.post<Map<String, dynamic>>(
    ApiEndpoints.messagingGroupRequest(groupId, userId),
    data: {'decision': accept ? 'accepted' : 'declined'},
  );

  @override
  Future<void> respondToRequest(
    String requestId,
    RequestDecision decision,
  ) async => throw UnsupportedError('Eşleşme istekleri henüz kullanılamıyor.');
}
