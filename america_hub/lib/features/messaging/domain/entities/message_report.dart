// [ReportCategory] moved to core once feed content became reportable too.
//
// Re-exported from its original home so every messaging import keeps working:
// the enum is the same object either way, which is what matters when a report
// sheet and a repository have to agree on it.
export '../../../../core/moderation/report_category.dart';
