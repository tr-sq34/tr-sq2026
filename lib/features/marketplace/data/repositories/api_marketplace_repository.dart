import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_response.dart';
import '../../../../core/pagination/cursor_page.dart';
import '../../domain/entities/marketplace_listing.dart';
import '../../domain/repositories/marketplace_repository.dart';
import '../dtos/marketplace_listing_dto.dart';
import '../../domain/entities/marketplace_seller.dart';

class ApiMarketplaceRepository implements MarketplaceRepository {
  ApiMarketplaceRepository({required ApiClient client}) : _client = client;
  final ApiClient _client;

  @override
  Future<CursorPage<MarketplaceListing>> fetchPage({String? cursor, int limit = 20}) async {
    final response = await _client.get<Map<String, dynamic>>(ApiEndpoints.marketplaceListings, queryParameters: {'cursor': cursor, 'limit': limit});
    final envelope = ApiResponse<List<MarketplaceListing>>.fromJson(response.data!, (raw) => (raw as List).map((item) => MarketplaceListingDto.fromJson(item as Map<String, dynamic>).toDomain()).toList());
    return CursorPage(items: envelope.data, nextCursor: envelope.nextCursor);
  }

  @override
  Future<List<MarketplaceListing>> getListings() async => (await fetchPage()).items;
  @override Future<MarketplaceSellerOverview> getSellerOverview() => throw UnimplementedError('Seller overview endpoint is not configured.');
  @override Future<MarketplaceSellerProfile> getSellerProfile(String sellerId) => throw UnimplementedError('Seller profile endpoint is not configured.');
  @override Future<MarketplaceSellerAnalytics> getSellerAnalytics() => throw UnimplementedError('Seller analytics endpoint is not configured.');
  @override Future<List<MarketplaceListing>> getSellerListings(String sellerId) => throw UnimplementedError('Seller listings endpoint is not configured.');
  @override Future<MarketplaceListing> publishListing(MarketplaceListingDraft draft) => throw UnimplementedError('Publish listing endpoint is not configured.');
  @override Future<MarketplaceListing> setSaved(String listingId, bool value) => throw UnimplementedError('Save listing endpoint is not configured.');
  @override Future<MarketplaceListing> setLiked(String listingId, bool value) => throw UnimplementedError('Like listing endpoint is not configured.');
  @override Future<MarketplaceListing> registerShare(String listingId) => throw UnimplementedError('Share listing endpoint is not configured.');
  @override Future<MarketplaceOffer> createOffer({required String listingId, required double amount}) => throw UnimplementedError('Offers endpoint is not configured.');
  @override Future<MarketplaceOffer> updateOfferStatus({required String offerId, required MarketplaceOfferStatus status, double? counterAmount}) => throw UnimplementedError('Offers endpoint is not configured.');
}
