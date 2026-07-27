import '../entities/community_post.dart';

abstract final class PostAccessPolicy {
  static bool canView({required CommunityPost post, required String viewerId, required bool isFriend}) {
    if (post.isDeleted || post.status == PostStatus.underReview) return false;
    if (post.ownerId == viewerId) return true;
    return post.visibility == PostVisibility.public || isFriend;
  }

  static bool canComment({required CommunityPost post, required String viewerId, required bool isFriend}) {
    if (!canView(post: post, viewerId: viewerId, isFriend: isFriend)) return false;
    return switch (post.commentsPolicy) {
      CommentsPolicy.disabled => false,
      CommentsPolicy.everyone => true,
      CommentsPolicy.friendsOnly => post.ownerId == viewerId || isFriend,
    };
  }

  static bool canDeleteComment({required CommunityComment comment, required CommunityPost post, required String viewerId}) =>
      comment.authorId == viewerId || post.ownerId == viewerId;
}
