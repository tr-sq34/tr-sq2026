import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../domain/entities/content_report.dart';
import '../../domain/repositories/content_moderation_repository.dart';

/// Feed reporting against the community service, which owns posts, comments and
/// stories and can therefore freeze the reported content into the report itself.
class ApiContentModerationRepository implements ContentModerationRepository {
  ApiContentModerationRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;

  @override
  Future<ContentReportReceipt> reportContent({
    required ContentReportTarget targetType,
    required String targetId,
    required ReportCategory category,
    String? note,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.communityReports,
      data: {
        'targetType': targetType.wireValue,
        'targetId': targetId,
        'category': category.wireValue,
        'note': ?note,
      },
    );
    final data = response.data?['data'] as Map<String, dynamic>?;
    return ContentReportReceipt(
      id: data?['id'] as String? ?? '',
      // Absent means the service created a new report; only the duplicate path
      // sets the flag, and treating a missing field as "new" keeps an older
      // service version from telling the user their report was a repeat.
      duplicate: data?['duplicate'] as bool? ?? false,
    );
  }

  @override
  Future<ContentAuthorRestriction?> myRestriction() async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.communityMyRestriction,
    );
    final data = response.data?['data'] as Map<String, dynamic>?;
    if (data == null) return null;
    final expiresAt = data['expiresAt'] as String?;
    return ContentAuthorRestriction(
      kind: data['kind'] as String? ?? 'muted',
      reason: data['reason'] as String? ?? '',
      expiresAt: expiresAt == null ? null : DateTime.tryParse(expiresAt),
    );
  }
}
