import 'package:america_hub/core/pagination/cursor_page.dart';
import 'package:america_hub/features/community/application/media_upload_controller.dart';
import 'package:america_hub/features/community/data/repositories/mock_media_upload_repository.dart';
import 'package:america_hub/features/messaging/application/direct_conversation_controller.dart';
import 'package:america_hub/features/messaging/application/messaging_controller.dart';
import 'package:america_hub/features/messaging/data/repositories/mock_message_moderation_repository.dart';
import 'package:america_hub/features/messaging/data/repositories/mock_messaging_repository.dart';
import 'package:america_hub/features/messaging/domain/entities/conversation.dart';
import 'package:america_hub/features/messaging/domain/entities/direct_message.dart';
import 'package:america_hub/features/messaging/domain/repositories/direct_message_repository.dart';
import 'package:america_hub/features/messaging/presentation/screens/inbox_screen.dart';
import 'package:america_hub/features/messaging/presentation/widgets/new_conversation_sheet.dart';
import 'package:america_hub/features/profile/application/friendship_controller.dart';
import 'package:america_hub/features/profile/domain/entities/friendship.dart';
import 'package:america_hub/features/profile/domain/repositories/friendship_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Yalnızca arkadaş listesini döndüren depo: seçici başka bir şey okumuyor.
class _Friendships implements FriendshipRepository {
  _Friendships({this.friends = const []});

  final List<FriendSummary> friends;

  @override
  Future<List<FriendSummary>> getFriends([String? userId]) async =>
      List.of(friends);

  @override
  Future<List<FriendRequest>> getRequests() async => const [];

  @override
  Future<FriendshipStatus> getStatus(String userId) async =>
      FriendshipStatus.none;

  @override
  Future<FriendshipStatus> sendRequest(String userId) async =>
      FriendshipStatus.pendingOutgoing;

  @override
  Future<FriendshipStatus> respond(String requestId, bool accepted) async =>
      FriendshipStatus.friends;

  @override
  Future<void> cancelRequest(String requestId) async {}

  @override
  Future<void> unfriend(String userId) async {}

  @override
  Future<void> block(String userId) async {}
}

/// Sohbetin gerçekten açılıp açılmadığını kaydediyor.
class _DirectMessages implements DirectMessageRepository {
  final List<String> opened = [];

  @override
  Future<Conversation> openDirectConversation(String targetUserId) async {
    opened.add(targetUserId);
    return Conversation(
      id: 'dm-$targetUserId',
      title: 'Elif Demir',
      preview: '',
      updatedAt: DateTime(2026, 8, 14),
      kind: ConversationKind.direct,
      participantId: targetUserId,
    );
  }

  @override
  Future<CursorPage<DirectMessage>> fetchMessages(
    String conversationId, {
    String? cursor,
    int limit = 30,
  }) async => const CursorPage(items: <DirectMessage>[], nextCursor: null);

  @override
  Future<String> sendMessage({
    required String conversationId,
    required String body,
    required String idempotencyKey,
  }) async => 'event-1';
}

const _elif = FriendSummary(
  userId: 'member-elif',
  displayName: 'Elif Demir',
  city: 'Paterson',
  regionCode: 'NJ',
);

void main() {
  testWidgets('seciciye yalnizca arkadaslar geliyor', (tester) async {
    final controller = FriendshipController(
      repository: _Friendships(friends: const [_elif]),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NewConversationSheet(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Elif Demir'), findsOneWidget);
    expect(find.text('Paterson, NJ'), findsOneWidget);
  });

  testWidgets('arkadasi olmayan uyeye ne yapacagi soyleniyor', (tester) async {
    final controller = FriendshipController(repository: _Friendships());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NewConversationSheet(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Henüz arkadaşın yok'), findsOneWidget);
  });

  testWidgets('secilen arkadas icin sunucuda sohbet aciliyor', (tester) async {
    final friendships = FriendshipController(
      repository: _Friendships(friends: const [_elif]),
    );
    final directMessages = _DirectMessages();
    final messaging = MessagingController(
      repository: MockMessagingRepository(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: InboxScreen(
          controller: messaging,
          createConversationController: (conversationId) =>
              DirectConversationController(
                repository: directMessages,
                conversationId: conversationId,
                viewerId: 'me',
              ),
          moderationRepository: MockMessageModerationRepository(),
          friendshipController: friendships,
          directMessageRepository: directMessages,
          mediaUploadController: MediaUploadController(
            repository: MockMediaUploadRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_rounded));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NewConversationSheet),
        matching: find.text('Elif Demir'),
      ),
    );
    await tester.pumpAndSettle();

    // Sohbet, karşıdaki üyenin kimliğiyle açılıyor; sohbetin kimliğiyle değil.
    expect(directMessages.opened, ['member-elif']);
  });
}
