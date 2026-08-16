import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/state/async_state.dart';
import '../../../../core/widgets/app_state_views.dart';
import '../../application/community_comments_controller.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/entities/content_report.dart';
import '../../domain/repositories/content_moderation_repository.dart';
import 'content_report_sheet.dart';

/// Yorum listesi ve yazma alanı.
///
/// Akıştan çıkarılıp buraya taşındı, çünkü Haber Merkezi'nde de aynısı
/// isteniyor: "yorum yap editör yazı yazma kısmı akışdakiyle birebir aynı
/// olmalı." Kopyalanan bir editör bir gün ikisinden birinde değişir; paylaşılan
/// bir editör değişemez.
///
/// Bileşen yetki bilmez: kimin yorum yazabileceğine ve kimin silebileceğine
/// çağıran karar verir ([onSubmit], [canDelete]). Akış bu kararı
/// `PostAccessPolicy`'ye sorar, haber ise "kendi yorumun" kuralına.
class CommentsSheet extends StatefulWidget {
  const CommentsSheet({
    super.key,
    required this.targetId,
    required this.controller,
    required this.moderationRepository,
    required this.onSubmit,
    required this.onDelete,
    required this.canDelete,
    this.commentsEnabled = true,
    this.subtitle = 'Arkadaşlarınla sohbete katıl.',
    this.disabledMessage = 'Bu paylaşım yorumlara kapalı.',
  });

  /// Yorumların bağlı olduğu gönderi ya da haber kimliği.
  final String targetId;
  final CommunityCommentsController controller;
  final ContentModerationRepository moderationRepository;
  final Future<void> Function(String message, String? parentId) onSubmit;
  final ValueChanged<CommunityComment> onDelete;
  final bool Function(CommunityComment) canDelete;
  final bool commentsEnabled;
  final String subtitle;
  final String disabledMessage;

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _messageController = TextEditingController();
  final Set<String> _expandedReplyThreads = {};
  CommunityComment? _replyingTo;

  @override
  void initState() {
    super.initState();
    widget.controller.load(widget.targetId);
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    try {
      await widget.onSubmit(
        _messageController.text,
        _replyingTo?.parentId ?? _replyingTo?.id,
      );
      _messageController.clear();
      setState(() => _replyingTo = null);
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on ArgumentError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message?.toString() ?? 'Yorum gönderilemedi.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .68,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD8D5DF),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Yorumlar',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.commentsEnabled ? widget.subtitle : widget.disabledMessage,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              final state = widget.controller.state;
              if (state is AsyncLoading<List<CommunityComment>>) {
                return const AppLoadingView(label: 'Yorumlar yükleniyor...');
              }
              if (state is AsyncFailure<List<CommunityComment>>) {
                return AppErrorState(
                  message: state.message,
                  onRetry: () => widget.controller.load(widget.targetId),
                );
              }
              final comments = state is AsyncData<List<CommunityComment>>
                  ? state.value
                  : const <CommunityComment>[];
              if (comments.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.forum_outlined,
                  title: 'Henüz yorum yok',
                  message: 'Bu sohbete ilk sen katılabilirsin.',
                );
              }
              final roots = comments
                  .where((comment) => comment.parentId == null)
                  .toList(growable: false);
              return ListView.separated(
                itemCount: roots.length,
                separatorBuilder: (_, _) => const SizedBox(height: 16),
                itemBuilder: (_, index) {
                  final comment = roots[index];
                  final replies = comments
                      .where((item) => item.parentId == comment.id)
                      .toList(growable: false);
                  return _CommentThread(
                    comment: comment,
                    replies: replies,
                    expanded: _expandedReplyThreads.contains(comment.id),
                    onToggleReplies: () => setState(
                      () => _expandedReplyThreads.contains(comment.id)
                          ? _expandedReplyThreads.remove(comment.id)
                          : _expandedReplyThreads.add(comment.id),
                    ),
                    onReply: (item) => setState(() => _replyingTo = item),
                    onLike: widget.controller.toggleLike,
                    onDelete: widget.onDelete,
                    canDelete: widget.canDelete,
                    onReport: (item) => showContentReportSheet(
                      context,
                      repository: widget.moderationRepository,
                      targetType: ContentReportTarget.comment,
                      targetId: item.id,
                      subjectLabel: item.authorName,
                    ),
                  );
                },
              );
            },
          ),
        ),
        if (widget.commentsEnabled) ...[
          const Divider(height: 22),
          if (_replyingTo != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Text(
                    '@${_replyingTo!.authorName} kişisine yanıt veriyorsun',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _replyingTo = null),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFFE9E7EE)),
                  ),
                  child: TextField(
                    controller: _messageController,
                    maxLength: CommunityComment.maxMessageLength,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      counterText: '',
                      hintText: 'Yorum yaz...',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      fillColor: Colors.transparent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedBuilder(
                animation: widget.controller,
                builder: (context, _) => IconButton.filled(
                  onPressed: widget.controller.isSubmitting ? null : _submit,
                  icon: const Icon(Icons.send_rounded),
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

class _CommentThread extends StatelessWidget {
  const _CommentThread({
    required this.comment,
    required this.replies,
    required this.expanded,
    required this.onToggleReplies,
    required this.onReply,
    required this.onLike,
    required this.onDelete,
    required this.canDelete,
    required this.onReport,
  });
  final CommunityComment comment;
  final List<CommunityComment> replies;
  final bool expanded;
  final VoidCallback onToggleReplies;
  final ValueChanged<CommunityComment> onReply;
  final ValueChanged<String> onLike;
  final ValueChanged<CommunityComment> onDelete;
  final bool Function(CommunityComment) canDelete;
  final ValueChanged<CommunityComment> onReport;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _row(comment, isReply: false),
      _replyAction(comment, left: 42),
      if (replies.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 42, top: 8),
          child: TextButton(
            onPressed: onToggleReplies,
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              expanded ? 'Yanıtları gizle' : '${replies.length} yanıtı göster',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
      if (expanded)
        Padding(
          padding: const EdgeInsets.only(left: 30, top: 8),
          child: Column(
            children: [
              for (final reply in replies)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _row(reply, isReply: true),
                      _replyAction(reply, left: 38),
                    ],
                  ),
                ),
            ],
          ),
        ),
    ],
  );

  Widget _replyAction(CommunityComment target, {required double left}) =>
      Padding(
        padding: EdgeInsets.only(left: left, top: 3),
        child: TextButton(
          onPressed: () => onReply(target),
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            'Yanıt ver',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ),
      );

  Widget _row(CommunityComment item, {required bool isReply}) {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: isReply ? 14 : 16,
          backgroundColor: AppColors.primary.withValues(alpha: .14),
          child: Text(
            item.authorName.substring(0, 1),
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.authorName,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.message,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => onLike(item.id),
              icon: Icon(
                item.isLiked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: 18,
                color: item.isLiked
                    ? AppColors.accentRose
                    : AppColors.textMuted,
              ),
            ),
            Text(
              '${item.likes}',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            if (!canDelete(item))
              // Reporting is offered on other people's comments only, and as a
              // visible control rather than a long-press: an affordance nobody
              // can find is the same as no affordance at all.
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Şikâyet et',
                onPressed: () => onReport(item),
                icon: const Icon(
                  Icons.flag_outlined,
                  size: 16,
                  color: AppColors.textMuted,
                ),
              ),
          ],
        ),
      ],
    );
    if (!canDelete(item)) return row;
    return Dismissible(
      key: ValueKey('comment-${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 18),
        color: AppColors.accentRose,
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(item),
      child: row,
    );
  }
}
