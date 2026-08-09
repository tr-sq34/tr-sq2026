import '../../domain/entities/message_report.dart';
import '../../domain/repositories/message_moderation_repository.dart';

/// Records what the UI asked for so the report and block flows can be exercised
/// without a backend. Nothing is invented on the way back: both calls succeed,
/// which is the only outcome the screens branch on.
class MockMessageModerationRepository implements MessageModerationRepository {
  final List<({String conversationId, String? messageEventId, ReportCategory category, String? note})> reports = [];
  final List<String> blockedUserIds = [];

  @override
  Future<void> reportConversation({
    required String conversationId,
    String? messageEventId,
    required ReportCategory category,
    String? note,
  }) async {
    reports.add((
      conversationId: conversationId,
      messageEventId: messageEventId,
      category: category,
      note: note,
    ));
  }

  @override
  Future<void> blockUser(String userId) async => blockedUserIds.add(userId);
}
