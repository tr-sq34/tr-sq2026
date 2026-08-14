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
  /// Satış merkezinin sayıları. Buradaki her şey daha önce sabit sıfır
  /// döndüren yerel bir karşılıktı: üç ilanına on bir kaydetme gelmiş bir
  /// üyeye "hiç yok" yazıyordu ve bu, boş bir panelden daha kötü, çünkü bir
  /// cevap gibi okunuyordu.
  @override
  Future<MarketplaceSellerDashboard> getSellerDashboard() async {
    final response = await _client.get<Map<String, dynamic>>(
      '/marketplace/me/overview',
    );
    final data = response.data!['data'] as Map<String, dynamic>;
    int count(String key) => (data[key] as num?)?.toInt() ?? 0;
    final top = data['topListing'] as Map<String, dynamic>?;
    return MarketplaceSellerDashboard(
      sellerId: data['sellerId'] as String? ?? '',
      activeListings: count('activeListings'),
      reservedListings: count('reservedListings'),
      soldListings: count('soldListings'),
      draftListings: count('draftListings'),
      saves: count('saves'),
      likes: count('likes'),
      shares: count('shares'),
      saves7d: count('saves7d'),
      likes7d: count('likes7d'),
      shares7d: count('shares7d'),
      topListing: top == null
          ? null
          : MarketplaceTopListing(
              id: top['id'] as String,
              title: top['title'] as String,
              saves: (top['saves'] as num?)?.toInt() ?? 0,
            ),
    );
  }

  /// Sunucu yalnızca bildiğini gönderiyor: ad, seçilen şehir, açık ilan sayısı
  /// ve kimlik doğrulaması. Puan, yanıt süresi ve satış sayısı bu sistemde
  /// henüz hiçbir yerde tutulmuyor; uydurulmuş bir "5 üzerinden 0", cevapsız
  /// kalmaktan daha kötü bir cevap olurdu. Ekran bu alanları hiç göstermiyor.
  @override
  Future<MarketplaceSellerProfile> getSellerProfile(String sellerId) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/marketplace/sellers/$sellerId',
    );
    final data = response.data!['data'] as Map<String, dynamic>;
    return MarketplaceSellerProfile(
      userId: data['id'] as String? ?? sellerId,
      displayName: data['displayName'] as String? ?? 'TurkSquare üyesi',
      city: data['city'] as String? ?? '',
      memberSince: null,
      activeListingCount: (data['activeListingCount'] as num?)?.toInt() ?? 0,
      completedSales: 0,
      rating: 0,
      reviewCount: 0,
      responseRate: 0,
      averageResponseMinutes: 0,
      identityStatus: data['identityVerified'] == true
          ? MarketplaceVerificationStatus.verified
          : MarketplaceVerificationStatus.unverified,
      phoneStatus: MarketplaceVerificationStatus.unverified,
      emailStatus: MarketplaceVerificationStatus.unverified,
    );
  }

  /// Satıcının kendi ilanları. Burası bugüne kadar tüm Çarşı'yı döndürüyordu:
  /// yabancının sayfası TurkSquare'deki her ilanı onunmuş gibi gösteriyordu.
  @override
  Future<List<MarketplaceListing>> getSellerListings(String sellerId) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.marketplaceListings,
      queryParameters: {'sellerId': sellerId, 'limit': 50},
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
    return envelope.data;
  }

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
        // Sunucuya adres değil kimlik gidiyor: hangi fotoğrafın kime ait
        // olduğuna ve taramadan geçip geçmediğine orada bakılıyor.
        if (draft.mediaIds.isNotEmpty) 'mediaIds': draft.mediaIds,
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

  /// Kaydetme ve beğeni bir durum, bir artış değil: kopan bağlantıda tekrarlanan
  /// dokunuş ilk dokunuşla aynı sonuca varıyor. Sunucu güncel ilanı geri
  /// döndürüyor, sayacı burada tahmin etmiyoruz.
  Future<MarketplaceListing> _react(
    String listingId,
    String kind,
    bool value,
  ) async {
    final response = await _client.put<Map<String, dynamic>>(
      '/marketplace/listings/$listingId/reactions/$kind',
      data: {'enabled': value},
    );
    return MarketplaceListingDto.fromJson(
      response.data!['data'] as Map<String, dynamic>,
    ).toDomain();
  }

  @override
  Future<MarketplaceListing> setSaved(String listingId, bool value) =>
      _react(listingId, 'save', value);
  @override
  Future<MarketplaceListing> setLiked(String listingId, bool value) =>
      _react(listingId, 'like', value);

  @override
  Future<MarketplaceListing> registerShare(String listingId) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/marketplace/listings/$listingId/shares',
    );
    return MarketplaceListingDto.fromJson(
      response.data!['data'] as Map<String, dynamic>,
    ).toDomain();
  }

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
