enum CommunitySpecialRequestType { imeceOffer, travelerMatch }

enum CommunitySpecialRequestStatus { pending, accepted, declined, cancelled }

/// İmece ve yolculuk ilanlarına verilen yanıtın, sohbet açılmadan önceki
/// güvenli ve denetlenebilir kaydıdır.
class CommunitySpecialRequest {
  const CommunitySpecialRequest({
    required this.id,
    required this.postId,
    required this.type,
    required this.senderId,
    required this.message,
    required this.createdAt,
    this.status = CommunitySpecialRequestStatus.pending,
  });

  final String id;
  final String postId;
  final CommunitySpecialRequestType type;
  final String senderId;
  final String message;
  final DateTime createdAt;
  final CommunitySpecialRequestStatus status;
}
