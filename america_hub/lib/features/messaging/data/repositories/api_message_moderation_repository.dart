import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../domain/entities/message_report.dart';
import '../../domain/repositories/message_moderation_repository.dart';

/// Reports go to the messaging gateway, blocks go to the community service.
///
/// Two clients rather than one because the two calls have different base URLs,
/// and folding them into a single service would mean either the gateway owning
/// the social graph or the community service owning Matrix — both of which the
/// rest of the system deliberately avoids.
class ApiMessageModerationRepository implements MessageModerationRepository {
  ApiMessageModerationRepository({
    required ApiClient messagingClient,
    required ApiClient communityClient,
  })  : _messaging = messagingClient,
        _community = communityClient;

  final ApiClient _messaging;
  final ApiClient _community;

  @override
  Future<void> reportConversation({
    required String conversationId,
    String? messageEventId,
    required ReportCategory category,
    String? note,
  }) async {
    await _messaging.post<Map<String, dynamic>>(
      ApiEndpoints.messagingReports,
      data: {
        'conversationId': conversationId,
        'messageEventId': ?messageEventId,
        'category': category.wireValue,
        'note': ?note,
      },
    );
  }

  @override
  Future<void> blockUser(String userId) async {
    await _community.post<Map<String, dynamic>>(
      ApiEndpoints.communityBlocks,
      data: {'userId': userId},
    );
  }
}
