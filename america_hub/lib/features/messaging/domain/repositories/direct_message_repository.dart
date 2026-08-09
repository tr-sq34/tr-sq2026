import '../../../../core/pagination/cursor_page.dart';
import '../entities/conversation.dart';
import '../entities/direct_message.dart';

abstract interface class DirectMessageRepository {
  /// Newest first. [cursor] walks backwards through history; a null
  /// `nextCursor` on the result means the beginning of the conversation has
  /// been reached.
  Future<CursorPage<DirectMessage>> fetchMessages(
    String conversationId, {
    String? cursor,
    int limit,
  });

  /// [idempotencyKey] must be stable across retries of the same message:
  /// sending twice with one key delivers one message, which is what makes a
  /// retry after a timeout safe.
  Future<String> sendMessage({
    required String conversationId,
    required String body,
    required String idempotencyKey,
  });

  /// Returns the existing conversation with [targetUserId] or creates one.
  Future<Conversation> openDirectConversation(String targetUserId);
}
