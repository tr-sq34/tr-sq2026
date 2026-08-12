import '../../domain/entities/promotion.dart';
import '../../domain/repositories/promotion_repository.dart';

/// Sunucu bağlanana kadar ana sayfadaki sponsorlu alanları ayakta tutan demo
/// içerik.
///
/// Gönderilen talep gerçekten burada saklanır ve "Tanıtımlarım" listesinde
/// `pending` olarak görünür: mock modda da akışın tamamı — talep, kuyruk,
/// karar bekleyiş — gezilebilsin diye.
class MockPromotionRepository implements PromotionRepository {
  MockPromotionRepository();

  late final List<Promotion> _promotions = _seed();
  final Map<String, int> _impressions = {};
  final Map<String, int> _clicks = {};
  var _nextId = 1;

  @override
  Future<List<Promotion>> fetchActive() async {
    final now = DateTime.now();
    return _promotions
        .where((promotion) => promotion.isLiveAt(now))
        .toList(growable: false);
  }

  @override
  Future<List<Promotion>> fetchMine() async => _promotions
      .where((promotion) => _mine.contains(promotion.id))
      .map(
        (promotion) => Promotion(
          id: promotion.id,
          placement: promotion.placement,
          title: promotion.title,
          subtitle: promotion.subtitle,
          imageUrl: promotion.imageUrl,
          targetKind: promotion.targetKind,
          targetValue: promotion.targetValue,
          regionCode: promotion.regionCode,
          city: promotion.city,
          startsAt: promotion.startsAt,
          endsAt: promotion.endsAt,
          status: promotion.status,
          decisionReason: promotion.decisionReason,
          requestNote: promotion.requestNote,
          impressions: _impressions[promotion.id] ?? promotion.impressions,
          clicks: _clicks[promotion.id] ?? promotion.clicks,
        ),
      )
      .toList(growable: false);

  @override
  Future<void> submit(PromotionRequestDraft draft) async {
    final id = 'promo-local-${_nextId++}';
    _mine.add(id);
    _promotions.insert(
      0,
      Promotion(
        id: id,
        placement: draft.placement,
        title: draft.title,
        subtitle: draft.subtitle,
        // Mock medya deposu kimliği yerel dosya yoluna çözüyor; talep listesi
        // görselini bu yüzden kimlikle taşımıyor, karar verilene kadar
        // önizleme göstermiyoruz.
        startsAt: draft.startsAt,
        endsAt: draft.endsAt,
        // Onay bekliyor: mock taraf da kendini onaylamaz.
        status: PromotionStatus.pending,
        regionCode: draft.regionCode,
        city: draft.city,
        requestNote: draft.note,
      ),
    );
  }

  @override
  Future<void> recordEvent(String promotionId, PromotionEventKind kind) async {
    final counter = kind == PromotionEventKind.impression
        ? _impressions
        : _clicks;
    counter[promotionId] = (counter[promotionId] ?? 0) + 1;
  }

  /// Demo üyenin sahibi olduğu tanıtımlar; ana sayfadaki diğerleri başka
  /// üyelerin.
  final Set<String> _mine = {'promo-kervan', 'promo-gecmis'};

  static List<Promotion> _seed() {
    final now = DateTime.now();
    return [
      Promotion(
        id: 'promo-kervan',
        placement: PromotionPlacement.storySlot,
        title: 'Kervan Market',
        subtitle: 'Hafta sonu Türk ürünlerinde %20 indirim',
        imageUrl:
            'https://images.unsplash.com/photo-1542838132-92c53300491e?auto=format&fit=crop&w=400&q=80',
        startsAt: now.subtract(const Duration(days: 2)),
        endsAt: now.add(const Duration(days: 5)),
        status: PromotionStatus.approved,
        city: 'Paterson',
        regionCode: 'NJ',
        requestNote: 'Açılış haftası duyurusu.',
        impressions: 1240,
        clicks: 86,
      ),
      Promotion(
        id: 'promo-ustabasi',
        placement: PromotionPlacement.storySlot,
        title: 'Usta Başı Tadilat',
        subtitle: 'Ev tadilatında ücretsiz keşif',
        imageUrl:
            'https://images.unsplash.com/photo-1581094794329-c8112a89af12?auto=format&fit=crop&w=400&q=80',
        startsAt: now.subtract(const Duration(days: 1)),
        endsAt: now.add(const Duration(days: 9)),
        status: PromotionStatus.approved,
      ),
      Promotion(
        id: 'promo-ilk-yil',
        placement: PromotionPlacement.featuredCard,
        title: 'Amerika’da İlk Yıl',
        subtitle: 'Banka hesabı, ehliyet, sigorta — sırasıyla.',
        imageUrl:
            'https://images.unsplash.com/photo-1534430480872-3498386e7856?auto=format&fit=crop&w=500&q=80',
        targetKind: PromotionTargetKind.news,
        targetValue: 'news-uscis',
        startsAt: now.subtract(const Duration(days: 3)),
        endsAt: now.add(const Duration(days: 20)),
        status: PromotionStatus.approved,
      ),
      Promotion(
        id: 'promo-gecmis',
        placement: PromotionPlacement.appBanner,
        title: 'Anadolu Lokantası',
        subtitle: 'Öğle menüsü duyurusu',
        startsAt: now.subtract(const Duration(days: 20)),
        endsAt: now.subtract(const Duration(days: 12)),
        status: PromotionStatus.rejected,
        city: 'Brooklyn',
        regionCode: 'NY',
        requestNote: 'Öğle menüsünü duyurmak istiyoruz.',
        decisionReason:
            'Görselde okunmayan telefon numarası var; yeniden yükleyip '
            'tekrar gönderebilirsin.',
      ),
    ];
  }
}
