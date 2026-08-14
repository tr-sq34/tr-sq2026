import '../../domain/entities/marketplace_listing.dart';
import '../../domain/repositories/marketplace_repository.dart';
import '../../../../core/pagination/cursor_page.dart';
import '../../domain/entities/marketplace_seller.dart';

class MockMarketplaceRepository implements MarketplaceRepository {
  final List<MarketplaceListing> _listings = [
    MarketplaceListing(id: 'listing-1', title: 'El yapımı çay seti', category: 'Ev & Mutfak', price: 32, condition: 'Yeni gibi', location: 'New York, NY', sellerName: 'Zeynep A.', imageUrl: 'https://images.unsplash.com/photo-1544787219-7f47ccb76574?auto=format&fit=crop&w=700&q=80'),
    MarketplaceListing(id: 'listing-2', title: 'Vintage kilim', category: 'Ev & Dekor', price: 145, condition: 'İyi durumda', location: 'Chicago, IL', sellerName: 'Can B.', imageUrl: 'https://images.unsplash.com/photo-1505693416388-ac5ce068fe85?auto=format&fit=crop&w=700&q=80', isSaved: true),
    MarketplaceListing(id: 'listing-3', title: 'Türk yemek kitapları', category: 'Kitap', price: 18, condition: 'Yeni gibi', location: 'Austin, TX', sellerName: 'Deniz K.', imageUrl: 'https://images.unsplash.com/photo-1543002588-bfa74002ed7e?auto=format&fit=crop&w=700&q=80'),
    MarketplaceListing(id: 'listing-4', title: 'Tavla seti', category: 'Koleksiyon', price: 54, condition: 'Yeni', location: 'Los Angeles, CA', sellerName: 'Emre T.', imageUrl: 'https://images.unsplash.com/photo-1529699211952-734e80c4d42b?auto=format&fit=crop&w=700&q=80'),
  ];
  final List<MarketplaceOffer> _offers = [];

  @override
  Future<CursorPage<MarketplaceListing>> fetchPage({String? cursor, int limit = 20}) async {
    final start = int.tryParse(cursor ?? '0') ?? 0;
    final end = (start + limit).clamp(0, _listings.length).toInt();
    return CursorPage(items: _listings.sublist(start, end), nextCursor: end < _listings.length ? '$end' : null);
  }

  @override
  Future<List<MarketplaceListing>> getListings() async => _listings;

  @override
  Future<MarketplaceSellerDashboard> getSellerDashboard() async {
    final active = _listings.where((item) => item.status == MarketplaceListingStatus.active).toList();
    final best = [..._listings]..sort((a, b) => b.likeCount.compareTo(a.likeCount));
    return MarketplaceSellerDashboard(
      sellerId: 'user-demo',
      activeListings: active.length,
      reservedListings: _listings.where((item) => item.status == MarketplaceListingStatus.reserved).length,
      soldListings: _listings.where((item) => item.status == MarketplaceListingStatus.sold).length,
      draftListings: 0,
      saves: _listings.where((item) => item.isSaved).length,
      likes: _listings.fold(0, (sum, item) => sum + item.likeCount),
      shares: _listings.fold(0, (sum, item) => sum + item.shareCount),
      saves7d: _listings.where((item) => item.isSaved).length,
      likes7d: _listings.fold(0, (sum, item) => sum + item.likeCount),
      shares7d: _listings.fold(0, (sum, item) => sum + item.shareCount),
      topListing: best.isEmpty ? null : MarketplaceTopListing(id: best.first.id, title: best.first.title, saves: best.first.likeCount),
    );
  }

  @override
  Future<MarketplaceSellerProfile> getSellerProfile(String sellerId) async => MarketplaceSellerProfile(
        userId: sellerId,
        displayName: sellerId == 'user-demo' ? 'Ahmet Yılmaz' : 'Can B.',
        city: 'New York, NY',
        memberSince: DateTime(2023, 4, 1),
        activeListingCount: _listings.where((item) => item.status == MarketplaceListingStatus.active).length,
        completedSales: 37,
        rating: 4.8,
        reviewCount: 24,
        responseRate: 96,
        averageResponseMinutes: 18,
        identityStatus: MarketplaceVerificationStatus.verified,
        phoneStatus: MarketplaceVerificationStatus.verified,
        emailStatus: MarketplaceVerificationStatus.verified,
        badges: [
          MarketplaceSellerBadge(id: 'identity', label: 'Kimliği doğrulandı', description: 'Kimlik doğrulaması tamamlandı.', icon: 'verified', level: MarketplaceSellerBadgeLevel.trusted, earnedAt: DateTime(2023, 4, 1)),
          MarketplaceSellerBadge(id: 'responsive', label: 'Hızlı yanıtlayan', description: 'Genellikle 30 dakika içinde yanıt verir.', icon: 'bolt', level: MarketplaceSellerBadgeLevel.trusted, earnedAt: DateTime(2025, 8, 1)),
          MarketplaceSellerBadge(id: 'pickup', label: 'Güvenilir teslim alma', description: 'Başarılı yerel teslim geçmişi.', icon: 'handshake', level: MarketplaceSellerBadgeLevel.premium, earnedAt: DateTime(2026, 1, 1)),
          MarketplaceSellerBadge(id: 'community', label: 'Topluluk emektarı', description: 'Toplulukta 3. yılı.', icon: 'groups', level: MarketplaceSellerBadgeLevel.foundation, earnedAt: DateTime(2026, 4, 1)),
        ],
      );

  @override
  Future<List<MarketplaceListing>> getSellerListings(String sellerId) async => _listings.where((item) => item.sellerId == sellerId || sellerId != 'user-demo').toList();

  @override
  Future<MarketplaceListing> publishListing(MarketplaceListingDraft draft) async {
    final listing = MarketplaceListing(id: 'listing-${DateTime.now().microsecondsSinceEpoch}', title: draft.title, category: draft.category.isEmpty ? 'Diger' : draft.category, price: draft.price ?? 0, condition: draft.fields['condition'] ?? 'Yeni gibi', location: draft.location.isEmpty ? 'New York, NY' : draft.location, sellerName: 'Ahmet Yilmaz', imageUrl: draft.mediaUrls.isEmpty ? 'https://images.unsplash.com/photo-1556742049-0cfed4f6a45d?auto=format&fit=crop&w=700&q=80' : draft.mediaUrls.first, mediaUrls: draft.mediaUrls, description: draft.description, type: draft.type, commentsEnabled: draft.commentsEnabled, createdAt: DateTime.now());
    _listings.insert(0, listing);
    return listing;
  }

  @override
  Future<MarketplaceListing> setSaved(String listingId, bool value) async => _updateListing(listingId, (item) => item.copyWith(isSaved: value));

  @override
  Future<MarketplaceListing> setLiked(String listingId, bool value) async => _updateListing(listingId, (item) => item.copyWith(isLiked: value, likeCount: item.likeCount + (value ? 1 : -1)));

  @override
  Future<MarketplaceListing> registerShare(String listingId) async => _updateListing(listingId, (item) => item.copyWith(shareCount: item.shareCount + 1));

  Future<MarketplaceListing> _updateListing(String id, MarketplaceListing Function(MarketplaceListing item) update) async {
    final index = _listings.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('İlan bulunamadı.');
    final updated = update(_listings[index]);
    _listings[index] = updated;
    return updated;
  }

  @override
  Future<MarketplaceOffer> createOffer({required String listingId, required double amount}) async {
    final offer = MarketplaceOffer(id: 'offer-${DateTime.now().microsecondsSinceEpoch}', listingId: listingId, amount: amount, status: MarketplaceOfferStatus.pending, createdAt: DateTime.now());
    _offers.add(offer);
    return offer;
  }

  @override
  Future<MarketplaceOffer> updateOfferStatus({required String offerId, required MarketplaceOfferStatus status, double? counterAmount}) async {
    final index = _offers.indexWhere((item) => item.id == offerId);
    if (index < 0) throw StateError('Teklif bulunamadi.');
    final previous = _offers[index];
    final updated = MarketplaceOffer(id: previous.id, listingId: previous.listingId, amount: previous.amount, status: status, createdAt: previous.createdAt, counterAmount: counterAmount);
    _offers[index] = updated;
    return updated;
  }
}
