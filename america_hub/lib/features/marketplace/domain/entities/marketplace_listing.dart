import 'marketplace_seller.dart';

class MarketplaceListing {
  const MarketplaceListing({
    required this.id,
    required this.title,
    required this.category,
    required this.price,
    required this.condition,
    required this.location,
    required this.sellerName,
    required this.imageUrl,
    this.sellerId = 'user-demo',
    this.isSaved = false,
    this.isLiked = false,
    this.likeCount = 0,
    this.shareCount = 0,
    this.type = MarketplaceListingType.item,
    this.description = '',
    this.mediaUrls = const [],
    this.status = MarketplaceListingStatus.active,
    this.createdAt,
    this.isLocationApproximate = true,
    this.commentsEnabled = true,
    this.offersEnabled = true,
    this.isBoosted = false,
  });

  final String id;
  final String title;
  final String category;
  final double price;
  final String condition;
  final String location;
  final String sellerName;
  final String imageUrl;
  final String sellerId;
  final bool isSaved;
  final bool isLiked;
  final int likeCount;
  final int shareCount;
  final MarketplaceListingType type;
  final String description;
  final List<String> mediaUrls;
  final MarketplaceListingStatus status;
  final DateTime? createdAt;
  final bool isLocationApproximate;
  final bool commentsEnabled;
  final bool offersEnabled;
  final bool isBoosted;

  MarketplaceListing copyWith({bool? isSaved, bool? isLiked, int? likeCount, int? shareCount, MarketplaceListingStatus? status}) => MarketplaceListing(
        id: id,
        title: title,
        category: category,
        price: price,
        condition: condition,
        location: location,
        sellerName: sellerName,
        imageUrl: imageUrl,
        sellerId: sellerId,
        isSaved: isSaved ?? this.isSaved,
        isLiked: isLiked ?? this.isLiked,
        likeCount: likeCount ?? this.likeCount,
        shareCount: shareCount ?? this.shareCount,
        type: type,
        description: description,
        mediaUrls: mediaUrls,
        status: status ?? this.status,
        createdAt: createdAt,
        isLocationApproximate: isLocationApproximate,
        commentsEnabled: commentsEnabled,
        offersEnabled: offersEnabled,
        isBoosted: isBoosted,
      );
}
