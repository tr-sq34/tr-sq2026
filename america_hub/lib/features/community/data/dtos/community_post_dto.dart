import '../../domain/entities/community_post.dart';
import '../../domain/entities/feed_extensions.dart';

class CommunityPostDto {
  const CommunityPostDto({required this.id, required this.authorName, required this.location, required this.createdAtLabel, required this.message, required this.likes, required this.comments, required this.isLiked, this.authorId = '', this.isAuthor = false, this.purpose = CommunityPostPurpose.standard, this.travelerMatch, this.media = const [], this.poll, this.newsReference});
  final String id;
  final String authorName;
  final String location;
  final String createdAtLabel;
  final String message;
  final int likes;
  final int comments;
  final bool isLiked;

  /// Paylaşımı yazanın kimliği. Buraya kadar hiç gelmiyordu; entity'deki
  /// `ownerId` sabit 'local-user' varsayılanında kalıyor, dolayısıyla gerçek
  /// bir hesapla girildiğinde hiçbir paylaşım üyenin kendi paylaşımı sayılmıyor
  /// - ne silme düğmesi çıkıyor, ne de sahibi altındaki yorumları kaldırabiliyor.
  final String authorId;

  /// Paylaşımın sahibi bu üye mi. Sunucu karşılaştırmayı kendisi yapıyor,
  /// oturum bilgisine bakmadan doğrudan cevap veriyor.
  final bool isAuthor;

  /// Paylaşımın ne için açıldığı. Besteci bunu ilk günden beri soruyordu ama
  /// sunucuya hiç gitmiyordu: "Bavulda Yer Var" olarak yayınlanan bir paylaşım
  /// herkesin akışına sıradan bir paylaşım olarak düşüyordu.
  final CommunityPostPurpose purpose;

  /// Yolculuk ayrıntıları. Yalnızca [CommunityPostPurpose.travelerMatch]
  /// paylaşımlarında dolu.
  final TravelerMatchDetails? travelerMatch;

  /// Paylaşıma eklenen fotoğraflar, gönderildikleri sırayla.
  ///
  /// Adresler her yanıtta yeniden imzalanıyor; kaydedilmiş bir URL değil,
  /// süreli bir izin. O yüzden burada saklanan tek şey o anki adres.
  final List<PostMedia> media;

  /// Anketi olan paylaşımlarda dolu. Anketin ayrı bir soru alanı yok: soru
  /// paylaşımın kendi metni, o yüzden [message] anketin de sorusu.
  final CommunityPoll? poll;

  /// Panelden akışa çıkarılmış bir haberde dolu. Kartın imzası, dokunulduğunda
  /// gideceği yer ve profilinin açılmaması buna bağlı.
  final NewsPostReference? newsReference;

  factory CommunityPostDto.fromJson(Map<String, dynamic> json) {
    final author = json['author'];
    final authorName = author is Map<String, dynamic> ? author['name'] as String? : null;
    final message = json['message'] as String? ?? '';
    return CommunityPostDto(
        id: json['id'] as String,
        authorName: json['authorName'] as String? ?? authorName ?? 'TurkSquare üyesi',
        location: json['location'] as String? ?? '',
        createdAtLabel: json['createdAtLabel'] as String? ?? 'Az önce',
        message: message,
        likes: (json['likes'] as num?)?.toInt() ?? 0,
        comments: (json['comments'] as num?)?.toInt() ?? 0,
        isLiked: json['isLiked'] as bool? ?? false,
        authorId: json['authorId'] as String? ?? '',
        isAuthor: json['isAuthor'] as bool? ?? false,
        purpose: _purposeFromJson(json['purpose']),
        travelerMatch: _travelerFromJson(json['travelerMatch']),
        media: _mediaFromJson(json['media']),
        poll: _pollFromJson(json['poll'], message),
        newsReference: _newsFromJson(json['news']),
      );
  }

  static NewsPostReference? _newsFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = raw['id'] as String?;
    if (id == null || id.isEmpty) return null;
    return NewsPostReference(
      articleId: id,
      title: raw['title'] as String? ?? '',
      category: raw['category'] as String?,
    );
  }

  static CommunityPostPurpose _purposeFromJson(Object? raw) => switch (raw) {
    'imeceHelp' => CommunityPostPurpose.imeceHelp,
    'travelerMatch' => CommunityPostPurpose.travelerMatch,
    _ => CommunityPostPurpose.standard,
  };

  static TravelerMatchDetails? _travelerFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final travelAt = DateTime.tryParse(raw['travelAt'] as String? ?? '');
    if (travelAt == null) return null;
    return TravelerMatchDetails(
      from: raw['from'] as String? ?? '',
      to: raw['to'] as String? ?? '',
      travelAt: travelAt.toLocal(),
      packageDetails: raw['packageDetails'] as String? ?? '',
      note: raw['note'] as String?,
    );
  }

  static List<PostMedia> _mediaFromJson(Object? raw) => [
    if (raw is List<dynamic>)
      for (final item in raw.whereType<Map<String, dynamic>>())
        if (item['url'] case final String url when url.isNotEmpty)
          PostMedia(
            id: item['id'] as String? ?? '',
            type: item['type'] == 'video'
                ? PostMediaType.video
                : PostMediaType.image,
            url: url,
            thumbnailUrl: item['thumbnailUrl'] as String?,
          ),
  ];

  static CommunityPoll? _pollFromJson(Object? raw, String question) {
    if (raw is! Map<String, dynamic>) return null;
    final options = (raw['options'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final closesAt = raw['closesAt'] as String?;
    return CommunityPoll(
      id: raw['id'] as String? ?? '',
      question: question,
      selectionMode: raw['selectionMode'] == 'multiple'
          ? PollSelectionMode.multiple
          : PollSelectionMode.single,
      endsAt: closesAt == null ? null : DateTime.tryParse(closesAt),
      options: [
        for (final option in options)
          PollOption(
            id: option['id'] as String,
            label: option['label'] as String? ?? '',
            votes: (option['votes'] as num?)?.toInt() ?? 0,
          ),
      ],
      selectedOptionIds: {
        for (final option in options)
          if (option['selected'] == true) option['id'] as String,
      },
    );
  }

  /// Sunucunun gönderdiği damga: `createdAtLabel` bir etiket değil, ISO 8601
  /// bir an. Okunur hale getirmek uygulamanın işi - kart "3dk" yazacaksa o
  /// hesabı okuyucunun saatiyle yapmak gerekiyor. Çözümlenemezse null kalıyor
  /// ve kart elindeki metni gösteriyor; uydurma bir tarih üretmiyoruz.
  DateTime? get createdAt => DateTime.tryParse(createdAtLabel)?.toLocal();

  CommunityPost toDomain() => CommunityPost(id: id, authorName: authorName, location: location, timeLabel: createdAtLabel, message: message, likes: likes, comments: comments, isLiked: isLiked, ownerId: authorId.isEmpty ? 'local-user' : authorId, isAuthor: isAuthor, purpose: purpose, travelerMatch: travelerMatch, media: media, poll: poll, newsReference: newsReference, createdAt: createdAt);
}
