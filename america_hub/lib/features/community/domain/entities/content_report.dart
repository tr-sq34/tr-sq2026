import '../../../../core/moderation/report_category.dart';

export '../../../../core/moderation/report_category.dart';

/// What kind of thing is being reported.
///
/// The wire values match the `target_type` check constraint on
/// `content_reports`, and the service uses them to decide which table to freeze
/// a copy of the content from. A value the service does not know is rejected at
/// intake, so the enum is the contract rather than a hint.
enum ContentReportTarget {
  post('post', 'Paylaşım'),
  comment('comment', 'Yorum'),
  story('story', 'Story'),
  // Forum akıştan ayrı bir yerde duruyor ama şikâyet kuyruğu tek: moderasyon
  // ekibi konuyu da yanıtı da paylaşımla aynı listede görüyor.
  forumTopic('forum_topic', 'Forum konusu'),
  forumReply('forum_reply', 'Forum yanıtı');

  const ContentReportTarget(this.wireValue, this.label);

  final String wireValue;
  final String label;
}

/// The outcome of filing a report.
///
/// [duplicate] is true when this user already has an open report on the same
/// content. The service answers with the existing report instead of an error,
/// because from the reporter's side nothing went wrong — the thing they wanted
/// is already true — and an error would push them to report again.
class ContentReportReceipt {
  const ContentReportReceipt({required this.id, required this.duplicate});

  final String id;
  final bool duplicate;
}

/// A restriction the moderation team placed on the signed-in member.
///
/// The app reads this to explain a 403 in words instead of showing "işlem
/// başarısız": someone who was muted for harassment should learn that, and when
/// it ends, from the app rather than from support.
class ContentAuthorRestriction {
  const ContentAuthorRestriction({
    required this.kind,
    required this.reason,
    this.expiresAt,
  });

  final String kind;
  final String reason;
  final DateTime? expiresAt;

  bool get isSuspension => kind == 'suspended';
}
