import '../entities/marketplace_listing.dart';
import '../../../../core/pagination/cursor_data_source.dart';
import '../entities/marketplace_seller.dart';

abstract interface class MarketplaceRepository implements CursorDataSource<MarketplaceListing> {
  Future<List<MarketplaceListing>> getListings();
  Future<MarketplaceSellerOverview> getSellerOverview();
  Future<MarketplaceSellerProfile> getSellerProfile(String sellerId);
  Future<MarketplaceSellerAnalytics> getSellerAnalytics();
  Future<List<MarketplaceListing>> getSellerListings(String sellerId);
  Future<MarketplaceListing> publishListing(MarketplaceListingDraft draft);
  Future<MarketplaceListing> setSaved(String listingId, bool value);
  Future<MarketplaceListing> setLiked(String listingId, bool value);
  Future<MarketplaceListing> registerShare(String listingId);
  Future<MarketplaceOffer> createOffer({required String listingId, required double amount});
  Future<MarketplaceOffer> updateOfferStatus({required String offerId, required MarketplaceOfferStatus status, double? counterAmount});
}
