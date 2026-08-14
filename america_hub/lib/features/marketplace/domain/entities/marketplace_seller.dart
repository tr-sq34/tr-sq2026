enum MarketplaceListingType { item, bundle, vehicle, home, saleEvent }
enum MarketplaceListingStatus { draft, active, reserved, sold }
enum MarketplaceOfferStatus { pending, accepted, declined, countered }
enum MarketplaceVerificationStatus { unverified, pending, verified }
enum MarketplaceSellerBadgeLevel { foundation, trusted, premium }

class MarketplaceSellerBadge {
  const MarketplaceSellerBadge({required this.id, required this.label, required this.description, required this.icon, required this.level, required this.earnedAt, this.isPublic = true});
  final String id;
  final String label;
  final String description;
  final String icon;
  final MarketplaceSellerBadgeLevel level;
  final DateTime earnedAt;
  final bool isPublic;
}

class MarketplaceSellerProfile {
  const MarketplaceSellerProfile({required this.userId, required this.displayName, required this.city, required this.memberSince, required this.activeListingCount, required this.completedSales, required this.rating, required this.reviewCount, required this.responseRate, required this.averageResponseMinutes, required this.identityStatus, required this.phoneStatus, required this.emailStatus, this.avatarUrl, this.badges = const []});
  final String userId;
  final String displayName;
  final String city;

  /// Bilinmiyorsa boş. Bu sistemde üyeliğin başladığı tarihi tutan bir kayıt
  /// yok; "Katılım: bugün" yazmaktansa o satır hiç görünmüyor.
  final DateTime? memberSince;
  final int activeListingCount;
  final int completedSales;
  final double rating;
  final int reviewCount;
  final int responseRate;
  final int averageResponseMinutes;
  final MarketplaceVerificationStatus identityStatus;
  final MarketplaceVerificationStatus phoneStatus;
  final MarketplaceVerificationStatus emailStatus;
  final String? avatarUrl;
  final List<MarketplaceSellerBadge> badges;
}

class MarketplaceListingInsight {
  const MarketplaceListingInsight({required this.listingId, required this.title, required this.message, required this.actionLabel, required this.priority});
  final String listingId;
  final String title;
  final String message;
  final String actionLabel;
  final int priority;
}

class MarketplaceSellerAnalytics {
  const MarketplaceSellerAnalytics({required this.active, required this.reserved, required this.sold, required this.draft, required this.views7d, required this.views30d, required this.saves7d, required this.messages7d, required this.offers7d, required this.shareCount, required this.topListingTitle, required this.insights});
  final int active;
  final int reserved;
  final int sold;
  final int draft;
  final int views7d;
  final int views30d;
  final int saves7d;
  final int messages7d;
  final int offers7d;
  final int shareCount;
  final String topListingTitle;
  final List<MarketplaceListingInsight> insights;
}

class MarketplaceSellerOverview {
  const MarketplaceSellerOverview({required this.activeListings, required this.views, required this.saves, required this.pendingOffers, required this.pendingMessages, required this.totalSales});
  final int activeListings;
  final int views;
  final int saves;
  final int pendingOffers;
  final int pendingMessages;
  final double totalSales;
}

class MarketplaceOffer {
  const MarketplaceOffer({required this.id, required this.listingId, required this.amount, required this.status, required this.createdAt, this.counterAmount});
  final String id;
  final String listingId;
  final double amount;
  final MarketplaceOfferStatus status;
  final DateTime createdAt;
  final double? counterAmount;
}

class MarketplaceListingDraft {
  const MarketplaceListingDraft({required this.type, this.title = '', this.price, this.description = '', this.category = '', this.location = '', this.mediaUrls = const [], this.fields = const {}, this.hideExactLocation = true, this.commentsEnabled = true, this.autoReplyEnabled = false});
  final MarketplaceListingType type;
  final String title;
  final double? price;
  final String description;
  final String category;
  final String location;
  final List<String> mediaUrls;
  final Map<String, String> fields;
  final bool hideExactLocation;
  final bool commentsEnabled;
  final bool autoReplyEnabled;

  MarketplaceListingDraft copyWith({String? title, double? price, String? description, String? category, String? location, List<String>? mediaUrls, Map<String, String>? fields, bool? hideExactLocation, bool? commentsEnabled, bool? autoReplyEnabled}) => MarketplaceListingDraft(type: type, title: title ?? this.title, price: price ?? this.price, description: description ?? this.description, category: category ?? this.category, location: location ?? this.location, mediaUrls: mediaUrls ?? this.mediaUrls, fields: fields ?? this.fields, hideExactLocation: hideExactLocation ?? this.hideExactLocation, commentsEnabled: commentsEnabled ?? this.commentsEnabled, autoReplyEnabled: autoReplyEnabled ?? this.autoReplyEnabled);
}

class MarketplaceAnalysisSuggestion {
  const MarketplaceAnalysisSuggestion({required this.title, required this.category, required this.suggestedPrice, required this.description});
  final String title;
  final String category;
  final double suggestedPrice;
  final String description;
}

abstract interface class MarketplaceListingAnalyzer {
  Future<MarketplaceAnalysisSuggestion> analyze({required MarketplaceListingType type, required List<String> mediaUrls});
}
