import '../../domain/entities/marketplace_category.dart';
import '../../domain/entities/marketplace_listing.dart';

class MarketplaceListingDto {
  const MarketplaceListingDto({
    required this.id,
    required this.title,
    required this.category,
    required this.price,
    required this.condition,
    required this.location,
    required this.sellerName,
    required this.imageUrl,
    required this.isSaved,
    this.sellerId = '',
    this.description = '',
    this.isLiked = false,
    this.likeCount = 0,
    this.shareCount = 0,
    this.createdAt,
    this.mediaUrls = const [],
  });
  final String id, title, category, condition, location, sellerName, imageUrl;
  final double price;
  final bool isSaved;

  /// İlanın sahibi. Bunu okumadan her ilan aynı varsayılan kimliğe ait
  /// görünüyordu; ekran kendi ilanını yabancınınkinden ayıramıyordu.
  final String sellerId;
  final String description;
  final bool isLiked;
  final int likeCount;
  final int shareCount;
  final DateTime? createdAt;

  /// İlanın kendi fotoğrafları, satıcının seçtiği sırayla. Boş gelirse ilanda
  /// gerçekten fotoğraf yok demektir; ekran yerine bir stok görsel koymuyor.
  final List<String> mediaUrls;

  factory MarketplaceListingDto.fromJson(Map<String, dynamic> json) =>
      MarketplaceListingDto(
        id: json['id'] as String,
        title: json['title'] as String,
        // Kategori anahtar olarak geliyor; ekrandaki söz [MarketplaceCategory]
        // içinde duruyor. Eski ilanlar 'other' ile kayıtlı.
        category: json['category'] as String? ?? MarketplaceCategory.other.key,
        price: (json['price'] as num?)?.toDouble() ?? 0,
        condition: json['condition'] as String? ?? '',
        location: json['location'] as String? ?? '',
        sellerName: json['sellerName'] as String? ?? '',
        imageUrl: json['imageUrl'] as String? ?? '',
        isSaved: json['isSaved'] as bool? ?? false,
        sellerId: json['sellerId'] as String? ?? '',
        description: json['description'] as String? ?? '',
        isLiked: json['isLiked'] as bool? ?? false,
        likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
        shareCount: (json['shareCount'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
        mediaUrls: [
          for (final item in (json['media'] as List? ?? const []))
            if ((item as Map)['url'] is String) item['url'] as String,
        ],
      );

  MarketplaceListing toDomain() => MarketplaceListing(
    id: id,
    title: title,
    category: category,
    price: price,
    condition: condition,
    location: location,
    sellerName: sellerName,
    imageUrl: imageUrl,
    isSaved: isSaved,
    createdAt: createdAt,
    sellerId: sellerId.isEmpty ? 'user-demo' : sellerId,
    description: description,
    isLiked: isLiked,
    likeCount: likeCount,
    shareCount: shareCount,
    mediaUrls: mediaUrls,
  );
}
