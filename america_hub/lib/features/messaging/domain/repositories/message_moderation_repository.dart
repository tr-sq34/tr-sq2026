import '../entities/message_report.dart';

/// The two things a user must always be able to do about someone else's
/// messages: report them, and stop hearing from them.
///
/// They live on one interface even though they are served by two services —
/// reporting by the messaging gateway, blocking by the community service, which
/// owns the social graph — because from the screen's point of view they are the
/// same decision made at the same moment.
abstract interface class MessageModerationRepository {
  /// Files a report. [messageEventId] is null when the user is reporting the
  /// conversation as a whole rather than one message.
  ///
  /// The server freezes a copy of the reported message when this returns, so a
  /// later deletion by the sender cannot erase the evidence.
  Future<void> reportConversation({
    required String conversationId,
    String? messageEventId,
    required ReportCategory category,
    String? note,
  });

  /// Severs contact in both directions: neither side can open a conversation
  /// with or send a message to the other afterwards.
  Future<void> blockUser(String userId);
}
