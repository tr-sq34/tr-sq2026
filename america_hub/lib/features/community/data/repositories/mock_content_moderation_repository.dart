import '../../domain/entities/content_report.dart';
import '../../domain/repositories/content_moderation_repository.dart';

/// Records what the UI asked for so the report flow can be exercised without a
/// backend. It also reproduces the one branch the sheet cares about: reporting
/// the same content twice comes back as a duplicate rather than an error.
class MockContentModerationRepository implements ContentModerationRepository {
  final List<
    ({
      ContentReportTarget targetType,
      String targetId,
      ReportCategory category,
      String? note,
    })
  >
  reports = [];

  @override
  Future<ContentReportReceipt> reportContent({
    required ContentReportTarget targetType,
    required String targetId,
    required ReportCategory category,
    String? note,
  }) async {
    final duplicate = reports.any(
      (report) =>
          report.targetType == targetType && report.targetId == targetId,
    );
    reports.add((
      targetType: targetType,
      targetId: targetId,
      category: category,
      note: note,
    ));
    return ContentReportReceipt(
      id: 'mock-report-${reports.length}',
      duplicate: duplicate,
    );
  }

  @override
  Future<ContentAuthorRestriction?> myRestriction() async => null;
}
