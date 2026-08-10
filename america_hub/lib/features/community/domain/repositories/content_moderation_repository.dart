import '../entities/content_report.dart';

/// Reporting for everything a member can publish in the feed.
///
/// Separate from `MessageModerationRepository` because the two are served by
/// different backends — feed content by the community service, messages by the
/// messaging gateway — and because their evidence rules differ: a reported post
/// is public and can be shown to a moderator in full, while a reported message
/// is only ever readable as the snapshot the reporter submitted.
abstract interface class ContentModerationRepository {
  /// Files a report against a post, comment or story.
  ///
  /// The service copies the reported content into the report inside the same
  /// transaction, so an author deleting it a second later cannot empty the case
  /// file for the takedown their own deletion triggered.
  Future<ContentReportReceipt> reportContent({
    required ContentReportTarget targetType,
    required String targetId,
    required ReportCategory category,
    String? note,
  });

  /// The restriction currently on the signed-in member, or null when there is
  /// none. Used to explain why publishing is refused.
  Future<ContentAuthorRestriction?> myRestriction();
}
