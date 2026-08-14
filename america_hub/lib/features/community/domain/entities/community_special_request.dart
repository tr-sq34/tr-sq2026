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
    this.senderName = '',
  });

  final String id;
  final String postId;
  final CommunitySpecialRequestType type;
  final String senderId;
  final String message;
  final DateTime createdAt;
  final CommunitySpecialRequestStatus status;

  /// İsteği gönderenin adı. Beğeni ve kaydetme sayı olarak kalıyor, ama bu
  /// başka bir şey: kişi mesaj yazıp tanışmak istediğini kendisi söylüyor.
  /// Sahibi kimin yazdığını görmeden yanıtlayamaz.
  final String senderName;

  CommunitySpecialRequest copyWith({CommunitySpecialRequestStatus? status}) =>
      CommunitySpecialRequest(
        id: id,
        postId: postId,
        type: type,
        senderId: senderId,
        message: message,
        createdAt: createdAt,
        status: status ?? this.status,
        senderName: senderName,
      );
}
