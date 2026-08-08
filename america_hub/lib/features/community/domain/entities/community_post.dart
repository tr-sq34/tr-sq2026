import 'dart:typed_data';

import 'feed_extensions.dart';

enum PostVisibility { public, friendsOnly }

enum CommentsPolicy { everyone, friendsOnly, disabled }

enum PostStatus { published, deleted, underReview }

enum PostMediaType { image, video }

enum CommunityPostPurpose {
  standard,
  imeceHelp,
  travelerMatch,
  anonymousAdvice,
}

class TravelerMatchDetails {
  const TravelerMatchDetails({
    required this.from,
    required this.to,
    required this.travelAt,
    required this.packageDetails,
    this.note,
  });
  final String from;
  final String to;
  final DateTime travelAt;
  final String packageDetails;
  final String? note;
}

class CommunityBadge {
  const CommunityBadge({required this.label, this.icon = '✦'});
  final String label;
  final String icon;
}

class PostMedia {
  const PostMedia({
    required this.id,
    required this.type,
    required this.url,
    this.thumbnailUrl,
    this.durationSeconds,
    this.previewBytes,
  });
  final String id;
  final PostMediaType type;
  final String url;
  final String? thumbnailUrl;
  final int? durationSeconds;

  /// Mock/local aşamada görseli anında göstermek için; canlı API yanıtında boş olur.
  final Uint8List? previewBytes;
}

class TaggedUser {
  const TaggedUser({required this.id, required this.displayName});
  final String id;
  final String displayName;
}

class PostLocation {
  const PostLocation({
    required this.placeId,
    required this.displayName,
    this.city,
  });
  final String placeId;
  final String displayName;
  final String? city;
}

enum CommentStatus { published, deleted, underReview }

class CommunityComment {
  const CommunityComment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.authorName,
    required this.message,
    required this.createdAt,
    this.parentId,
    this.likes = 0,
    this.isLiked = false,
    this.status = CommentStatus.published,
    this.deletedAt,
  });

  static const maxMessageLength = 1000;
  final String id;
  final String postId;
  final String authorId;
  final String authorName;
  final String message;
  final DateTime createdAt;
  final String? parentId;
  final int likes;
  final bool isLiked;
  final CommentStatus status;
  final DateTime? deletedAt;

  bool get isDeleted => status == CommentStatus.deleted || deletedAt != null;

  CommunityComment copyWith({
    CommentStatus? status,
    DateTime? deletedAt,
    int? likes,
    bool? isLiked,
  }) => CommunityComment(
    id: id,
    postId: postId,
    authorId: authorId,
    authorName: authorName,
    message: message,
    createdAt: createdAt,
    parentId: parentId,
    likes: likes ?? this.likes,
    isLiked: isLiked ?? this.isLiked,
    status: status ?? this.status,
    deletedAt: deletedAt ?? this.deletedAt,
  );
}

class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.authorName,
    required this.location,
    required this.timeLabel,
    required this.message,
    required this.likes,
    required this.comments,
    this.ownerId = 'local-user',
    this.visibility = PostVisibility.friendsOnly,
    this.commentsPolicy = CommentsPolicy.friendsOnly,
    this.status = PostStatus.published,
    this.media = const [],
    this.taggedUsers = const [],
    this.postLocation,
    this.isLiked = false,
    this.deletedAt,
    this.purpose = CommunityPostPurpose.standard,
    this.travelerMatch,
    this.badge,
    this.isSaved = false,
    this.saves = 0,
    this.shares = 0,
    this.approximateLocation,
    this.poll,
    this.marketplaceReference,
  });

  static const maxMessageLength = 2200;
  final String id, authorName, location, timeLabel, message, ownerId;
  final int likes, comments;
  final PostVisibility visibility;
  final CommentsPolicy commentsPolicy;
  final PostStatus status;
  final List<PostMedia> media;
  final List<TaggedUser> taggedUsers;
  final PostLocation? postLocation;
  final bool isLiked;
  final DateTime? deletedAt;
  final CommunityPostPurpose purpose;
  final TravelerMatchDetails? travelerMatch;
  final CommunityBadge? badge;
  final bool isSaved;
  final int saves;
  final int shares;
  final ApproximateLocation? approximateLocation;
  final CommunityPoll? poll;
  final MarketplacePostReference? marketplaceReference;

  bool get isDeleted => status == PostStatus.deleted || deletedAt != null;

  CommunityPost copyWith({
    int? likes,
    bool? isLiked,
    bool? isSaved,
    int? saves,
    int? shares,
    CommunityPoll? poll,
    PostStatus? status,
    DateTime? deletedAt,
  }) => CommunityPost(
    id: id,
    authorName: authorName,
    location: location,
    timeLabel: timeLabel,
    message: message,
    likes: likes ?? this.likes,
    comments: comments,
    ownerId: ownerId,
    visibility: visibility,
    commentsPolicy: commentsPolicy,
    status: status ?? this.status,
    media: media,
    taggedUsers: taggedUsers,
    postLocation: postLocation,
    isLiked: isLiked ?? this.isLiked,
    deletedAt: deletedAt ?? this.deletedAt,
    purpose: purpose,
    travelerMatch: travelerMatch,
    badge: badge,
    isSaved: isSaved ?? this.isSaved,
    saves: saves ?? this.saves,
    shares: shares ?? this.shares,
    approximateLocation: approximateLocation,
    poll: poll ?? this.poll,
    marketplaceReference: marketplaceReference,
  );
}
