import 'community_post.dart';
import 'feed_extensions.dart';

/// UI'nin taşıdığı geçici paylaşım verisi. Ağ modeli değildir.
class CreatePostDraft {
  const CreatePostDraft({
    required this.message,
    required this.visibility,
    required this.commentsPolicy,
    this.media = const [],
    this.taggedUsers = const [],
    this.location,
    this.purpose = CommunityPostPurpose.standard,
    this.travelerMatch,
    this.poll,
    this.marketplaceListingId,
  });

  final String message;
  final PostVisibility visibility;
  final CommentsPolicy commentsPolicy;
  final List<PostMedia> media;
  final List<TaggedUser> taggedUsers;
  final PostLocation? location;
  final CommunityPostPurpose purpose;
  final TravelerMatchDetails? travelerMatch;
  final CommunityPoll? poll;
  final String? marketplaceListingId;

  String get normalizedMessage => message.trim();

  String? get validationError {
    if (normalizedMessage.isEmpty && media.isEmpty) {
      return 'Paylaşım için yazı veya medya ekleyin.';
    }
    if (normalizedMessage.length > CommunityPost.maxMessageLength) {
      return 'Paylaşım metni en fazla ${CommunityPost.maxMessageLength} karakter olabilir.';
    }
    if (media.length > 10)
      return 'Bir paylaşımda en fazla 10 medya kullanılabilir.';
    if (media.where((item) => item.type == PostMediaType.video).length > 1) {
      return 'Bir paylaşımda yalnızca bir video kullanılabilir.';
    }
    if (poll != null) {
      if (poll!.question.trim().isEmpty ||
          poll!.options.length < 2 ||
          poll!.options.length > 4)
        return 'Anket için soru ve 2–4 seçenek gereklidir.';
      if (poll!.options.any((option) => option.label.trim().isEmpty))
        return 'Anket seçenekleri boş olamaz.';
    }
    if (marketplaceListingId != null && marketplaceListingId!.trim().isEmpty)
      return 'Geçerli bir Çarşı ilanı seçin.';
    if (purpose == CommunityPostPurpose.travelerMatch && travelerMatch == null)
      return 'Yolculuk için nereden ve nereye bilgisini ekleyin.';
    if (purpose == CommunityPostPurpose.travelerMatch &&
        travelerMatch != null &&
        travelerMatch!.packageDetails.trim().isEmpty) {
      return 'Taşınacak paket veya eşya bilgisini ekleyin.';
    }
    return null;
  }

  bool get isValid => validationError == null;
}
