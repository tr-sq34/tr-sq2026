import '../../domain/entities/marketplace_seller.dart';

class MockMarketplaceListingAnalyzer implements MarketplaceListingAnalyzer {
  @override
  Future<MarketplaceAnalysisSuggestion> analyze({required MarketplaceListingType type, required List<String> mediaUrls}) async {
    final label = switch (type) { MarketplaceListingType.vehicle => 'Temiz kullanilmis arac', MarketplaceListingType.home => 'Modern kiralik ev', MarketplaceListingType.saleEvent => 'Topluluk satis etkinligi', MarketplaceListingType.bundle => 'Secili urun paketi', MarketplaceListingType.item => 'Topluluktan ozel urun' };
    final category = switch (type) { MarketplaceListingType.vehicle => 'Arac', MarketplaceListingType.home => 'Ev & Emlak', MarketplaceListingType.saleEvent => 'Etkinlik', MarketplaceListingType.bundle => 'Coklu urun', MarketplaceListingType.item => 'Diger' };
    return MarketplaceAnalysisSuggestion(title: label, category: category, suggestedPrice: type == MarketplaceListingType.vehicle ? 8500 : type == MarketplaceListingType.home ? 1800 : 45, description: mediaUrls.isEmpty ? 'Urunun durumu ve teslim ayrintilarini ekleyin.' : 'Fotografa gore olusturulan taslak aciklama. Urun detaylarini yayina almadan once kontrol edin.');
  }
}
