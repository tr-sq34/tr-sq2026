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
    this.createdAt,
  });
  final String id, title, category, condition, location, sellerName, imageUrl;
  final double price;
  final bool isSaved;
  final DateTime? createdAt;

  factory MarketplaceListingDto.fromJson(Map<String, dynamic> json) =>
      MarketplaceListingDto(
        id: json['id'] as String,
        title: json['title'] as String,
        category: json['category'] as String? ?? 'Diğer',
        price: (json['price'] as num?)?.toDouble() ?? 0,
        condition: json['condition'] as String? ?? '',
        location: json['location'] as String? ?? '',
        sellerName: json['sellerName'] as String? ?? '',
        imageUrl: json['imageUrl'] as String? ?? '',
        isSaved: json['isSaved'] as bool? ?? false,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
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
  );
}
