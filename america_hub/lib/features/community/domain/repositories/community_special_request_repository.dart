import '../entities/community_special_request.dart';

/// Canlıda bildirim, moderasyon ve mesajlaşma servislerinin arkasında kalır.
/// UI bu sözleşmeye bağlı olduğu için mock/API geçişi ekranları etkilemez.
abstract interface class CommunitySpecialRequestRepository {
  Future<CommunitySpecialRequest> createRequest({
    required String postId,
    required CommunitySpecialRequestType type,
    required String message,
  });

  Future<List<CommunitySpecialRequest>> getRequestsForPost(String postId);
  Future<void> updateStatus(String requestId, CommunitySpecialRequestStatus status);
}
