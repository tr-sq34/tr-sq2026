import '../../../../core/pagination/cursor_page.dart';
import '../../domain/entities/news_article.dart';
import '../../domain/repositories/news_repository.dart';

/// Sunucu bağlanana kadar Haber Merkezi'ni ayakta tutan demo içerik.
///
/// Haberler ana sayfadaki manşet şeridiyle aynı yerden gelir: burada da manşet,
/// [NewsArticle.headlineRank] verilmiş haberden başka bir şey değil. Böylece
/// mock modda gezerken iki yüzeyin senkron çalıştığı görülebiliyor.
class MockNewsRepository implements NewsRepository {
  MockNewsRepository();

  late final List<NewsArticle> _articles = _seed();

  @override
  Future<CursorPage<NewsArticle>> fetchNews({
    String? cursor,
    int limit = 20,
    NewsCategory? category,
  }) async {
    final filtered = category == null
        ? _articles
        : _articles.where((item) => item.category == category).toList();
    // Tek sayfa: demo verisi sayfalamayı gerektirecek kadar uzun değil, ve
    // uydurma bir sonraki imleci döndürmek listeyi sonsuz gösterirdi.
    return CursorPage(
      items: filtered.take(limit).toList(growable: false),
      nextCursor: null,
    );
  }

  @override
  Future<List<NewsArticle>> fetchHeadlines({int limit = 5}) async {
    final headlines = _articles.where((item) => item.isHeadline).toList()
      ..sort((a, b) => a.headlineRank!.compareTo(b.headlineRank!));
    return headlines.take(limit).toList(growable: false);
  }

  @override
  Future<NewsArticle> getArticle(String id) async {
    final article = _articles.where((item) => item.id == id).firstOrNull;
    if (article == null) throw StateError('Haber bulunamadı.');
    return article;
  }

  @override
  Future<NewsReactionTally> react(
    String articleId,
    NewsReaction? reaction,
  ) async {
    final index = _articles.indexWhere((item) => item.id == articleId);
    if (index == -1) throw StateError('Haber bulunamadı.');
    final article = _articles[index];
    final previous = article.viewerReaction;
    // Sayaçlar önceki tepki geri alınarak yeniden hesaplanır; sunucudaki
    // birincil anahtar da aynı şeyi söylüyor: kişi başına tek tepki.
    var likes = article.likeCount - (previous == NewsReaction.like ? 1 : 0);
    var dislikes =
        article.dislikeCount - (previous == NewsReaction.dislike ? 1 : 0);
    if (reaction == NewsReaction.like) likes += 1;
    if (reaction == NewsReaction.dislike) dislikes += 1;
    _articles[index] = article.copyWith(
      likeCount: likes,
      dislikeCount: dislikes,
      viewerReaction: reaction,
      clearViewerReaction: reaction == null,
    );
    return NewsReactionTally(
      likeCount: likes,
      dislikeCount: dislikes,
      viewerReaction: reaction,
    );
  }

  static List<NewsArticle> _seed() {
    final now = DateTime.now();
    return [
      NewsArticle(
        id: 'news-uscis',
        title:
            'USCIS, çalışma izni uzatma sürelerini ve başvuru kriterlerini güncelledi',
        summary:
            'Otomatik uzatma süresi belirli kategorilerde 540 güne çıkarıldı. '
            'Başvurusu beklemede olan üyeler için kritik olan tarihleri derledik.',
        body:
            'USCIS, çalışma izni (EAD) yenileme başvurularında otomatik uzatma '
            'süresini belirli kategorilerde 540 güne çıkardığını duyurdu. '
            'Düzenleme, süresi dolmak üzere olan izinlerini yenilemek için '
            'başvurusunu zamanında yapmış kişileri kapsıyor.\n\n'
            'Kurum, kararın işlem sürelerindeki birikimden kaynaklandığını ve '
            'başvurusu beklemede olan kişilerin çalışma hakkını kaybetmemesini '
            'amaçladığını belirtti. Başvurunuzun hangi kategoride olduğunu '
            'onay mektubunuzdaki kod üzerinden doğrulayabilirsiniz.\n\n'
            'İşvereninize iletmeniz gereken belge, süresi geçmiş EAD kartınız '
            'ile birlikte başvurunuzun alındığına dair I-797C bildirimidir. '
            'İkisi bir arada, uzatma süresi boyunca geçerli çalışma izni '
            'belgesi sayılıyor.',
        category: NewsCategory.gocmenlik,
        authorName: 'TurkSquare Haber',
        publishedAt: now.subtract(const Duration(hours: 2)),
        imageUrl:
            'https://images.unsplash.com/photo-1541872703-74c5e44368f9?auto=format&fit=crop&w=700&q=80',
        headlineRank: 1,
        likeCount: 34,
        dislikeCount: 2,
        commentCount: 1,
      ),
      NewsArticle(
        id: 'news-turkevi',
        title:
            'NYC Türkevi\'nde Türk el sanatları sergisi ziyaretçilerini bekliyor',
        summary:
            'Çini, hat ve ebru çalışmalarının yer aldığı sergi ay sonuna kadar '
            'ücretsiz gezilebiliyor.',
        body:
            'New York Türkevi\'nde açılan "Elden Ele" sergisi, Anadolu\'nun '
            'farklı şehirlerinden gelen ustaların çini, hat ve ebru '
            'çalışmalarını bir araya getiriyor.\n\n'
            'Sergi hafta içi 10.00-18.00, hafta sonu 12.00-18.00 arasında '
            'ücretsiz gezilebiliyor. Hafta sonları çocuklara yönelik ebru '
            'atölyesi de düzenleniyor; kontenjan sınırlı olduğu için önceden '
            'kayıt isteniyor.',
        category: NewsCategory.kultur,
        authorName: 'TurkSquare Haber',
        publishedAt: now.subtract(const Duration(hours: 5)),
        imageUrl:
            'https://images.unsplash.com/photo-1486406146926-c627a92ad1ab?auto=format&fit=crop&w=700&q=80',
        headlineRank: 2,
        likeCount: 58,
        commentCount: 0,
      ),
      NewsArticle(
        id: 'news-thy',
        title:
            'THY, New York ve Şikago hattında direkt sefer sayılarını artırıyor',
        summary:
            'Yaz tarifesiyle birlikte iki şehirden İstanbul\'a haftalık sefer '
            'sayısı artıyor; bağlantılı uçuşlarda bekleme süreleri kısalıyor.',
        body:
            'Türk Hava Yolları, yaz tarifesiyle birlikte New York (JFK) ve '
            'Şikago (ORD) hatlarında haftalık direkt sefer sayısını artırdığını '
            'açıkladı.\n\n'
            'Havayolu, artışın özellikle yaz aylarında yoğunlaşan aile '
            'ziyaretleri talebinden kaynaklandığını belirtti. Bağlantılı '
            'uçuşlarda İstanbul\'daki bekleme sürelerinin de kısalması '
            'bekleniyor.',
        category: NewsCategory.yasam,
        authorName: 'TurkSquare Haber',
        publishedAt: now.subtract(const Duration(days: 1)),
        imageUrl:
            'https://images.unsplash.com/photo-1436491865332-7a61a109cc05?auto=format&fit=crop&w=700&q=80',
        headlineRank: 3,
        likeCount: 21,
        dislikeCount: 4,
        commentCount: 0,
      ),
      NewsArticle(
        id: 'news-nj-kira',
        title: 'New Jersey\'de kira artışlarına tavan getiren düzenleme mecliste',
        summary:
            'Paterson ve çevresindeki ilçeleri de kapsayan tasarı, yıllık kira '
            'artışını enflasyona bağlamayı öngörüyor.',
        body:
            'New Jersey eyalet meclisinde görüşülen tasarı, yıllık kira '
            'artışlarını tüketici fiyat endeksine bağlamayı öngörüyor. '
            'Düzenleme kabul edilirse Paterson, Clifton ve Passaic dahil olmak '
            'üzere birçok ilçede kira artışı üst sınıra tabi olacak.\n\n'
            'Kiracı dernekleri düzenlemeyi desteklerken, ev sahipleri '
            'birliği bakım maliyetlerinin karşılanamayacağı görüşünde. '
            'Oylamanın önümüzdeki ay yapılması bekleniyor.',
        category: NewsCategory.gundem,
        authorName: 'TurkSquare Haber',
        publishedAt: now.subtract(const Duration(days: 2)),
        regionCode: 'NJ',
        likeCount: 47,
        dislikeCount: 1,
        commentCount: 0,
      ),
    ];
  }
}
