/// Haber Merkezi'nin okuduğu haber.
///
/// Ana sayfadaki "Amerika'dan Manşetler" şeridi ile menüdeki Haber Merkezi aynı
/// kaydı okur; aradaki tek fark, şeridin yalnızca [headlineRank] verilmiş
/// haberleri göstermesidir. İki ayrı liste tutulmaması bilinçli: manşet ile
/// haber listesi arasında bir gün fark oluşması, senkron tutulacak iki kopyanın
/// kaçınılmaz sonucudur.
class NewsArticle {
  const NewsArticle({
    required this.id,
    required this.title,
    required this.summary,
    required this.category,
    required this.authorName,
    required this.publishedAt,
    this.body,
    this.imageUrl,
    this.regionCode,
    this.headlineRank,
    this.commentsEnabled = true,
    this.likeCount = 0,
    this.dislikeCount = 0,
    this.commentCount = 0,
    this.viewerReaction,
  });

  final String id;
  final String title;
  final String summary;

  /// Yalnızca detay ucundan gelir; liste 20 kB'lık gövdeleri taşımaz.
  final String? body;
  final NewsCategory category;
  final String authorName;
  final DateTime publishedAt;
  final String? imageUrl;
  final String? regionCode;
  final int? headlineRank;
  final bool commentsEnabled;
  final int likeCount;
  final int dislikeCount;
  final int commentCount;
  final NewsReaction? viewerReaction;

  bool get isHeadline => headlineRank != null;

  /// "3 saat önce" — listede ve detayda aynı biçim.
  String timeLabel({DateTime? now}) {
    final elapsed = (now ?? DateTime.now()).difference(publishedAt);
    if (elapsed.inMinutes < 1) return 'Az önce';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} dakika önce';
    if (elapsed.inHours < 24) return '${elapsed.inHours} saat önce';
    if (elapsed.inDays < 7) return '${elapsed.inDays} gün önce';
    return '${publishedAt.day.toString().padLeft(2, '0')}.'
        '${publishedAt.month.toString().padLeft(2, '0')}.${publishedAt.year}';
  }

  NewsArticle copyWith({
    String? body,
    int? likeCount,
    int? dislikeCount,
    int? commentCount,
    NewsReaction? viewerReaction,
    bool clearViewerReaction = false,
  }) => NewsArticle(
    id: id,
    title: title,
    summary: summary,
    body: body ?? this.body,
    category: category,
    authorName: authorName,
    publishedAt: publishedAt,
    imageUrl: imageUrl,
    regionCode: regionCode,
    headlineRank: headlineRank,
    commentsEnabled: commentsEnabled,
    likeCount: likeCount ?? this.likeCount,
    dislikeCount: dislikeCount ?? this.dislikeCount,
    commentCount: commentCount ?? this.commentCount,
    viewerReaction: clearViewerReaction
        ? null
        : viewerReaction ?? this.viewerReaction,
  );

  factory NewsArticle.fromJson(Map<String, dynamic> json) => NewsArticle(
    id: json['id'] as String,
    title: json['title'] as String,
    summary: json['summary'] as String,
    body: json['body'] as String?,
    category: NewsCategory.fromCode(json['category'] as String?),
    authorName: json['authorName'] as String? ?? 'TurkSquare',
    publishedAt:
        DateTime.tryParse(json['publishedAt'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
    imageUrl: json['imageUrl'] as String?,
    regionCode: json['regionCode'] as String?,
    headlineRank: json['headlineRank'] as int?,
    commentsEnabled: json['commentsEnabled'] as bool? ?? true,
    likeCount: json['likeCount'] as int? ?? 0,
    dislikeCount: json['dislikeCount'] as int? ?? 0,
    commentCount: json['commentCount'] as int? ?? 0,
    viewerReaction: NewsReaction.fromCode(json['viewerReaction'] as String?),
  );
}

/// Sunucudaki `news_articles.category` CHECK listesiyle birebir aynı kodlar.
enum NewsCategory {
  gundem('gundem', 'Gündem'),
  gocmenlik('gocmenlik', 'Göçmenlik'),
  ekonomi('ekonomi', 'Ekonomi'),
  yasam('yasam', 'Yaşam'),
  spor('spor', 'Spor'),
  kultur('kultur', 'Kültür'),
  topluluk('topluluk', 'Topluluk');

  const NewsCategory(this.code, this.label);
  final String code;
  final String label;

  /// Tanınmayan kod haberi düşürmez: sunucuya yeni bir kategori eklendiğinde
  /// eski sürümdeki uygulama haberi gizlemek yerine Gündem altında gösterir.
  static NewsCategory fromCode(String? code) => NewsCategory.values.firstWhere(
    (category) => category.code == code,
    orElse: () => NewsCategory.gundem,
  );
}

enum NewsReaction {
  like,
  dislike;

  static NewsReaction? fromCode(String? code) => switch (code) {
    'like' => NewsReaction.like,
    'dislike' => NewsReaction.dislike,
    _ => null,
  };
}
