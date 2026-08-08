import '../../../../core/cache/cache_store.dart';
import '../../../../core/pagination/cached_cursor_data_source.dart';
import '../../../../core/pagination/cursor_page.dart';
import '../../domain/entities/marketplace_listing.dart';
import '../../domain/repositories/marketplace_repository.dart';
import '../cache/marketplace_page_codec.dart';
import '../../domain/entities/marketplace_seller.dart';

class CachedMarketplaceRepository implements MarketplaceRepository {
  CachedMarketplaceRepository({required MarketplaceRepository remote, required CacheStore cacheStore}) : _remote = remote, _cached = CachedCursorDataSource(remote: remote, cacheStore: cacheStore, codec: MarketplacePageCodec(), namespace: 'marketplace.listings');
  final MarketplaceRepository _remote;
  final CachedCursorDataSource<MarketplaceListing> _cached;
  @override Future<CursorPage<MarketplaceListing>> fetchPage({String? cursor, int limit = 20}) => _cached.fetchPage(cursor: cursor, limit: limit);
  @override Future<List<MarketplaceListing>> getListings() => _remote.getListings();
  @override Future<MarketplaceSellerOverview> getSellerOverview() => _remote.getSellerOverview();
  @override Future<MarketplaceSellerProfile> getSellerProfile(String sellerId) => _remote.getSellerProfile(sellerId);
  @override Future<MarketplaceSellerAnalytics> getSellerAnalytics() => _remote.getSellerAnalytics();
  @override Future<List<MarketplaceListing>> getSellerListings(String sellerId) => _remote.getSellerListings(sellerId);
  @override Future<MarketplaceListing> publishListing(MarketplaceListingDraft draft) => _remote.publishListing(draft);
  @override Future<MarketplaceListing> setSaved(String listingId, bool value) => _remote.setSaved(listingId, value);
  @override Future<MarketplaceListing> setLiked(String listingId, bool value) => _remote.setLiked(listingId, value);
  @override Future<MarketplaceListing> registerShare(String listingId) => _remote.registerShare(listingId);
  @override Future<MarketplaceOffer> createOffer({required String listingId, required double amount}) => _remote.createOffer(listingId: listingId, amount: amount);
  @override Future<MarketplaceOffer> updateOfferStatus({required String offerId, required MarketplaceOfferStatus status, double? counterAmount}) => _remote.updateOfferStatus(offerId: offerId, status: status, counterAmount: counterAmount);
}
