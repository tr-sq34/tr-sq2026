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

/// İlanı en çok kaydedilen ilan. Kaydeden yoksa gösterilecek bir şey de yok.
class MarketplaceTopListing {
  const MarketplaceTopListing({required this.id, required this.title, required this.saves});
  final String id;
  final String title;
  final int saves;
}

/// Satış merkezinin sayıları.
///
/// Burada yalnızca Çarşı'nın gerçekten tuttuğu şeyler var: duruma göre ilan
/// sayıları ve o ilanlara gelen kaydetme, beğeni, paylaşım. Görüntülenme,
/// mesaj ve teklif yok - bu sistemde ilan görüntülenmesini sayan bir yer
/// bulunmuyor, mesajlar başka bir serviste duruyor, teklif için ise hiç tablo
/// yok. Bunlar sıfır olarak gösterilmiyor; ekranda hiç yer almıyorlar, çünkü
/// "sıfır" bir cevaptır ve yanlış bir cevaptır.
class MarketplaceSellerDashboard {
  const MarketplaceSellerDashboard({required this.sellerId, required this.activeListings, required this.reservedListings, required this.soldListings, required this.draftListings, required this.saves, required this.likes, required this.shares, required this.saves7d, required this.likes7d, required this.shares7d, this.topListing});
  final String sellerId;
  final int activeListings;
  final int reservedListings;
  final int soldListings;
  final int draftListings;
  final int saves;
  final int likes;
  final int shares;
  final int saves7d;
  final int likes7d;
  final int shares7d;
  final MarketplaceTopListing? topListing;

  bool get hasWeeklyActivity => saves7d > 0 || likes7d > 0 || shares7d > 0;
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
  const MarketplaceListingDraft({required this.type, this.title = '', this.price, this.description = '', this.category = '', this.location = '', this.mediaUrls = const [], this.mediaIds = const [], this.fields = const {}, this.hideExactLocation = true, this.commentsEnabled = true, this.autoReplyEnabled = false});
  final MarketplaceListingType type;
  final String title;
  final double? price;
  final String description;
  final String category;
  final String location;

  /// Önizlemede çizilen adresler. Bunlar süreli imzalı adresler: yarın açılan
  /// bir taslakta artık çalışmayabilirler, o yüzden sunucuya giden şey bunlar
  /// değil [mediaIds].
  final List<String> mediaUrls;

  /// Yüklenip taraması biten fotoğrafların kimlikleri, seçildikleri sırayla.
  /// İlk sıradaki kapak oluyor.
  final List<String> mediaIds;
  final Map<String, String> fields;
  final bool hideExactLocation;
  final bool commentsEnabled;
  final bool autoReplyEnabled;

  MarketplaceListingDraft copyWith({String? title, double? price, String? description, String? category, String? location, List<String>? mediaUrls, List<String>? mediaIds, Map<String, String>? fields, bool? hideExactLocation, bool? commentsEnabled, bool? autoReplyEnabled}) => MarketplaceListingDraft(type: type, title: title ?? this.title, price: price ?? this.price, description: description ?? this.description, category: category ?? this.category, location: location ?? this.location, mediaUrls: mediaUrls ?? this.mediaUrls, mediaIds: mediaIds ?? this.mediaIds, fields: fields ?? this.fields, hideExactLocation: hideExactLocation ?? this.hideExactLocation, commentsEnabled: commentsEnabled ?? this.commentsEnabled, autoReplyEnabled: autoReplyEnabled ?? this.autoReplyEnabled);
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
