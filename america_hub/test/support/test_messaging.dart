import 'package:america_hub/core/pagination/cursor_page.dart';
import 'package:america_hub/features/messaging/application/direct_conversation_controller.dart';
import 'package:america_hub/features/messaging/data/repositories/mock_message_moderation_repository.dart';
import 'package:america_hub/features/messaging/domain/entities/conversation.dart';
import 'package:america_hub/features/messaging/domain/entities/direct_message.dart';
import 'package:america_hub/features/messaging/domain/repositories/direct_message_repository.dart';
import 'package:america_hub/features/messaging/presentation/messaging_launcher.dart';

/// Sohbetin kiminle açıldığını ve ilk mesaj olarak ne gittiğini kaydeder.
class RecordingDirectMessages implements DirectMessageRepository {
  RecordingDirectMessages({this.fails = false});

  /// Sunucunun yanıt vermediği durum: düğme sessiz kalmasın diye sınanıyor.
  final bool fails;

  final List<String> opened = [];
  final List<String> sent = [];

  @override
  Future<Conversation> openDirectConversation(String targetUserId) async {
    if (fails) throw Exception('offline');
    opened.add(targetUserId);
    return Conversation(
      id: 'dm-$targetUserId',
      title: 'Satıcı',
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
  }) async {
    sent.add(body);
    return 'event-${sent.length}';
  }
}

/// Ekranların beklediği kurulum, sunucusuz.
MessagingLauncher testMessaging({
  DirectMessageRepository? directMessages,
  String viewerId = 'me',
}) {
  final repository = directMessages ?? RecordingDirectMessages();
  return MessagingLauncher(
    directMessages: repository,
    createController: (conversationId) => DirectConversationController(
      repository: repository,
      conversationId: conversationId,
      viewerId: viewerId,
    ),
    moderationRepository: MockMessageModerationRepository(),
    viewerId: () => viewerId,
  );
}
