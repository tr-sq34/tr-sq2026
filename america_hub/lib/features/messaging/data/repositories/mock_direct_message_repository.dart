import '../../../../core/pagination/cursor_page.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/direct_message.dart';
import '../../domain/repositories/direct_message_repository.dart';

/// In-memory stand-in used when `USE_MOCK_SERVICES=true`, so the chat screen
/// can be run and demoed without a gateway. It keeps one thread per
/// conversation and never paginates — [fetchMessages] always reports that the
/// history is complete.
class MockDirectMessageRepository implements DirectMessageRepository {
  MockDirectMessageRepository({this.viewerId = 'me'});

  /// Messages whose sender is this ID render as the viewer's own.
  final String viewerId;

  static const _peerId = 'mock-peer';

  late final Map<String, List<DirectMessage>> _threads = {
    'dm-1': [
      DirectMessage(
        id: 'mock-1',
        senderId: _peerId,
        body: 'Selam! Bu hafta sonu Brooklyn tarafında mısın?',
        sentAt: DateTime.now().subtract(const Duration(minutes: 42)),
      ),
      DirectMessage(
        id: 'mock-2',
        senderId: viewerId,
        body: 'Buradayım. Kahve içmeye çıkabiliriz.',
        sentAt: DateTime.now().subtract(const Duration(minutes: 38)),
      ),
      DirectMessage(
        id: 'mock-3',
        senderId: _peerId,
        body: 'Harika, cumartesi 11 gibi uyar mı?',
        sentAt: DateTime.now().subtract(const Duration(minutes: 12)),
      ),
    ],
  };

  @override
  Future<CursorPage<DirectMessage>> fetchMessages(
    String conversationId, {
    String? cursor,
    int limit = 30,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    // The gateway returns newest first; the controller relies on that order.
    final thread = _threads[conversationId] ?? const <DirectMessage>[];
    return CursorPage(items: thread.reversed.toList(growable: false));
  }

  @override
  Future<String> sendMessage({
    required String conversationId,
    required String body,
    required String idempotencyKey,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 220));
    _threads.putIfAbsent(conversationId, () => []).add(
      DirectMessage(
        id: idempotencyKey,
        senderId: viewerId,
        body: body,
        sentAt: DateTime.now(),
      ),
    );
    return idempotencyKey;
  }

  @override
  Future<Conversation> openDirectConversation(String targetUserId) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    return Conversation(
      id: 'dm-$targetUserId',
      title: 'TurkSquare üyesi',
      preview: '',
      updatedAt: DateTime.now(),
      kind: ConversationKind.direct,
    );
  }
}
