import '../../../../core/network/api_client.dart';
import '../../domain/entities/community_special_request.dart';
import '../../domain/repositories/community_special_request_repository.dart';

/// İmece ve bavul paylaşımlarına gelen istekler.
///
/// Bu sınıfa kadar istek diye bir şey yoktu: sahte depo hem sahte hem gerçek
/// kipte bağlıydı, istek gönderenin kendi belleğindeki bir listeye yazılıyor ve
/// uygulama kapanınca yok oluyordu. "İsteğin gönderildi." doğruydu, ama isteği
/// alan kimse yoktu.
///
/// İsteğin türü buradan gönderilmiyor. Sunucu türü paylaşımın kendi amacından
/// çıkarıyor: bir üye, başkasının destek paylaşımının aslında bir yolculuk
/// olduğuna karar veremez.
class ApiCommunitySpecialRequestRepository
    implements CommunitySpecialRequestRepository {
  ApiCommunitySpecialRequestRepository({required ApiClient client})
    : _client = client;

  final ApiClient _client;

  @override
  Future<CommunitySpecialRequest> createRequest({
    required String postId,
    required CommunitySpecialRequestType type,
    required String message,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/community/posts/$postId/requests',
      data: {'message': message},
    );
    return _fromJson(response.data!['data'] as Map<String, dynamic>);
  }

  @override
  Future<List<CommunitySpecialRequest>> getRequestsForPost(
    String postId,
  ) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/community/posts/$postId/requests',
    );
    final data = response.data?['data'] as List<dynamic>? ?? const [];
    return data
        .map((raw) => _fromJson(raw as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<void> updateStatus(
    String requestId,
    CommunitySpecialRequestStatus status,
  ) => _client.put<void>(
    '/community/requests/$requestId/status',
    data: {'status': status.name},
  );

  static CommunitySpecialRequest _fromJson(Map<String, dynamic> json) =>
      CommunitySpecialRequest(
        id: json['id'] as String,
        postId: json['postId'] as String,
        type: json['type'] == 'travelerMatch'
            ? CommunitySpecialRequestType.travelerMatch
            : CommunitySpecialRequestType.imeceOffer,
        senderId: json['senderId'] as String? ?? '',
        senderName: json['senderName'] as String? ?? '',
        message: json['message'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
        status: _statusFromJson(json['status'] as String?),
      );

  /// Tanımadığı bir durum gelirse istek bekliyor sayılıyor: sahibinin
  /// listesinde görünmesi, sessizce kaybolmasından iyi.
  static CommunitySpecialRequestStatus _statusFromJson(String? value) =>
      switch (value) {
        'accepted' => CommunitySpecialRequestStatus.accepted,
        'declined' => CommunitySpecialRequestStatus.declined,
        'cancelled' => CommunitySpecialRequestStatus.cancelled,
        _ => CommunitySpecialRequestStatus.pending,
      };
}
