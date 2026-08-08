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
  Future<CursorPage<MarketplaceListing>> fetchPage({
    String? cursor,
    int limit = 20,
  }) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.marketplaceListings,
      queryParameters: {'cursor': cursor, 'limit': limit},
    );
    final envelope = ApiResponse<List<MarketplaceListing>>.fromJson(
      response.data!,
      (raw) => (raw as List)
          .map(
            (item) => MarketplaceListingDto.fromJson(
              item as Map<String, dynamic>,
            ).toDomain(),
          )
          .toList(),
    );
    return CursorPage(items: envelope.data, nextCursor: envelope.nextCursor);
  }

  @override
  Future<List<MarketplaceListing>> getListings() async =>
      (await fetchPage()).items;
  @override
  Future<MarketplaceSellerOverview> getSellerOverview() async =>
      const MarketplaceSellerOverview(
        activeListings: 0,
        views: 0,
        saves: 0,
        pendingOffers: 0,
        pendingMessages: 0,
        totalSales: 0,
      );

  @override
  Future<MarketplaceSellerProfile> getSellerProfile(String sellerId) async =>
      MarketplaceSellerProfile(
        userId: sellerId,
        displayName: 'TurkSquare üyesi',
        city: '',
        memberSince: DateTime.now(),
        activeListingCount: 0,
        completedSales: 0,
        rating: 0,
        reviewCount: 0,
        responseRate: 0,
        averageResponseMinutes: 0,
        identityStatus: MarketplaceVerificationStatus.unverified,
        phoneStatus: MarketplaceVerificationStatus.unverified,
        emailStatus: MarketplaceVerificationStatus.unverified,
      );

  @override
  Future<MarketplaceSellerAnalytics> getSellerAnalytics() async =>
      const MarketplaceSellerAnalytics(
        active: 0,
        reserved: 0,
        sold: 0,
        draft: 0,
        views7d: 0,
        views30d: 0,
        saves7d: 0,
        messages7d: 0,
        offers7d: 0,
        shareCount: 0,
        topListingTitle: 'Henüz ilan yok',
        insights: [],
      );

  @override
  Future<List<MarketplaceListing>> getSellerListings(String sellerId) =>
      getListings();

  @override
  Future<MarketplaceListing> publishListing(
    MarketplaceListingDraft draft,
  ) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.marketplaceListings,
      data: {
        'title': draft.title,
        'description': draft.description,
        'price': draft.price,
        'city': draft.location.isEmpty ? null : draft.location,
      },
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? const {};
    return MarketplaceListing(
      id: data['id'] as String,
      title: draft.title,
      category: draft.category.isEmpty ? 'Diğer' : draft.category,
      price: draft.price ?? 0,
      condition: draft.fields['condition'] ?? '',
      location: draft.location,
      sellerName: 'Siz',
      imageUrl: draft.mediaUrls.isEmpty ? '' : draft.mediaUrls.first,
      description: draft.description,
      mediaUrls: draft.mediaUrls,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<MarketplaceListing> setSaved(String listingId, bool value) =>
      throw UnimplementedError('Save listing endpoint is not configured.');
  @override
  Future<MarketplaceListing> setLiked(String listingId, bool value) =>
      throw UnimplementedError('Like listing endpoint is not configured.');
  @override
  Future<MarketplaceListing> registerShare(String listingId) =>
      throw UnimplementedError('Share listing endpoint is not configured.');
  @override
  Future<MarketplaceOffer> createOffer({
    required String listingId,
    required double amount,
  }) => throw UnimplementedError('Offers endpoint is not configured.');
  @override
  Future<MarketplaceOffer> updateOfferStatus({
    required String offerId,
    required MarketplaceOfferStatus status,
    double? counterAmount,
  }) => throw UnimplementedError('Offers endpoint is not configured.');
}
