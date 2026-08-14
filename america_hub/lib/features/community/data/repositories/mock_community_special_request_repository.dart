import '../../domain/entities/community_special_request.dart';
import '../../domain/repositories/community_special_request_repository.dart';

class MockCommunitySpecialRequestRepository implements CommunitySpecialRequestRepository {
  final List<CommunitySpecialRequest> _requests = [];

  @override
  Future<CommunitySpecialRequest> createRequest({required String postId, required CommunitySpecialRequestType type, required String message}) async {
    final request = CommunitySpecialRequest(
      id: 'request-${DateTime.now().microsecondsSinceEpoch}',
      postId: postId,
      type: type,
      senderId: 'local-user',
      message: message,
      createdAt: DateTime.now(),
    );
    _requests.add(request);
    return request;
  }

  @override
  Future<List<CommunitySpecialRequest>> getRequestsForPost(String postId) async =>
      _requests.where((item) => item.postId == postId).toList(growable: false);

  @override
  Future<void> updateStatus(String requestId, CommunitySpecialRequestStatus status) async {
    final index = _requests.indexWhere((item) => item.id == requestId);
    if (index < 0) throw StateError('İstek bulunamadı.');
    _requests[index] = _requests[index].copyWith(status: status);
  }
}
