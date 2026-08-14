import '../entities/marketplace_listing.dart';
import '../../../../core/pagination/cursor_data_source.dart';
import '../entities/marketplace_seller.dart';

abstract interface class MarketplaceRepository implements CursorDataSource<MarketplaceListing> {
  Future<List<MarketplaceListing>> getListings();

  /// Tek bir ilan, kimliğiyle. Bildirimden gelen kişi ilanı listede aramak
  /// zorunda kalmasın diye. Satılmış ya da kaldırılmış ilan yanıt vermiyor:
  /// artık işlem yapılamayacak bir sayfayı açmanın anlamı yok.
  Future<MarketplaceListing> getListing(String listingId);
  Future<MarketplaceSellerDashboard> getSellerDashboard();
  Future<MarketplaceSellerProfile> getSellerProfile(String sellerId);
  Future<List<MarketplaceListing>> getSellerListings(String sellerId);
  Future<MarketplaceListing> publishListing(MarketplaceListingDraft draft);
  Future<MarketplaceListing> setSaved(String listingId, bool value);
  Future<MarketplaceListing> setLiked(String listingId, bool value);
  Future<MarketplaceListing> registerShare(String listingId);
  Future<MarketplaceOffer> createOffer({required String listingId, required double amount});
  Future<MarketplaceOffer> updateOfferStatus({required String offerId, required MarketplaceOfferStatus status, double? counterAmount});
}
