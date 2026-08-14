import 'package:flutter/material.dart';

import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../application/community_comments_controller.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/services/post_access_policy.dart';
import '../../domain/repositories/content_moderation_repository.dart';
import 'comments_sheet.dart';

/// Bir paylaşımın yorum tabakasını açar.
///
/// Akış bunu karta dokunulduğunda yapıyor, bildirimler ise "paylaşımına yorum
/// yapıldı" satırına dokunulduğunda. İki yerde iki ayrı kurulum, bir gün
/// birinde silme yetkisinin unutulması demekti; kurulum burada tek yerde.
Future<void> openPostComments({
  required BuildContext context,
  required CommunityPost post,
  required CommunityCommentsController controller,
  required ContentModerationRepository moderationRepository,
  required String viewerId,
  String? subtitle,
}) => showAppBottomSheet<void>(
  context: context,
  child: CommentsSheet(
    targetId: post.id,
    controller: controller,
    moderationRepository: moderationRepository,
    commentsEnabled: post.commentsPolicy != CommentsPolicy.disabled,
    subtitle: subtitle ?? 'Arkadaşlarınla sohbete katıl.',
    onSubmit: (message, parentId) => controller.addComment(
      post: post,
      viewerId: viewerId,
      isFriend: true,
      message: message,
      parentId: parentId,
    ),
    onDelete: (comment) => controller.deleteComment(
      comment: comment,
      post: post,
      viewerId: viewerId,
    ),
    canDelete: (comment) => PostAccessPolicy.canDeleteComment(
      comment: comment,
      post: post,
      viewerId: viewerId,
    ),
  ),
);
