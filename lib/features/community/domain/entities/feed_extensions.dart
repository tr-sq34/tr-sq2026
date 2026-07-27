import 'community_post.dart';

enum FeedMode { forYou, nearby, following }

enum StoryVisibility { network, public }

enum PollSelectionMode { single, multiple }

class ApproximateLocation {
  const ApproximateLocation({
    required this.city,
    required this.region,
    this.latitude,
    this.longitude,
    this.geohash,
  });
  final String city;
  final String region;
  final double? latitude;
  final double? longitude;

  /// A coarse geospatial cell only; never use this value to render exact GPS.
  final String? geohash;
  String get label => region.isEmpty ? city : '$city, $region';
}

class PollOption {
  const PollOption({required this.id, required this.label, this.votes = 0});
  final String id;
  final String label;
  final int votes;
}

class CommunityPoll {
  const CommunityPoll({
    required this.id,
    required this.question,
    required this.options,
    required this.selectionMode,
    this.endsAt,
    this.selectedOptionIds = const <String>{},
  });
  final String id;
  final String question;
  final List<PollOption> options;
  final PollSelectionMode selectionMode;
  final DateTime? endsAt;
  final Set<String> selectedOptionIds;
  bool get isClosed => endsAt != null && !endsAt!.isAfter(DateTime.now());
}

class MarketplacePostReference {
  const MarketplacePostReference({
    required this.listingId,
    required this.title,
    required this.price,
    required this.thumbnailUrl,
    required this.approximateLocation,
  });
  final String listingId;
  final String title;
  final double price;
  final String? thumbnailUrl;
  final ApproximateLocation approximateLocation;
}

class StoryItem {
  const StoryItem({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.media,
    required this.createdAt,
    required this.expiresAt,
    required this.visibility,
    this.isLiked = false,
    this.likeCount = 0,
    this.viewCount = 0,
    this.isViewed = false,
  });
  final String id;
  final String authorId;
  final String authorName;
  final PostMedia media;
  final DateTime createdAt;
  final DateTime expiresAt;
  final StoryVisibility visibility;
  final bool isLiked;
  final int likeCount;
  final int viewCount;
  final bool isViewed;
  bool get isExpired => !expiresAt.isAfter(DateTime.now());
  StoryItem copyWith({
    bool? isLiked,
    int? likeCount,
    int? viewCount,
    bool? isViewed,
  }) => StoryItem(
    id: id,
    authorId: authorId,
    authorName: authorName,
    media: media,
    createdAt: createdAt,
    expiresAt: expiresAt,
    visibility: visibility,
    isLiked: isLiked ?? this.isLiked,
    likeCount: likeCount ?? this.likeCount,
    viewCount: viewCount ?? this.viewCount,
    isViewed: isViewed ?? this.isViewed,
  );
}

class CreateStoryDraft {
  const CreateStoryDraft({
    required this.media,
    required this.visibility,
    required this.ttl,
  });
  final PostMedia media;
  final StoryVisibility visibility;
  final Duration ttl;
  String? get validationError => switch (ttl.inHours) {
    6 || 12 || 24 => null,
    _ => 'Story süresi 6, 12 veya 24 saat olmalıdır.',
  };
}
