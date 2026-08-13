import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/state/async_state.dart';
import '../../../../core/widgets/app_state_views.dart';
import '../../../community/domain/entities/content_report.dart';
import '../../../community/domain/repositories/content_moderation_repository.dart';
import '../../../community/presentation/widgets/content_report_sheet.dart';
import '../../application/forum_controller.dart';
import '../../domain/entities/forum.dart';

/// Konunun kendisi ve altındaki yanıtlar.
///
/// Yanıt kutusu ekranın altında sabit duruyor: forumda okumakla yazmak arasında
/// bir sayfa geçişi olmamalı. Kilitli konuda kutu yerine sebebi yazıyor.
class ForumTopicScreen extends StatefulWidget {
  const ForumTopicScreen({
    super.key,
    required this.topicId,
    required this.controller,
    required this.moderationRepository,
    required this.viewerId,
  });

  final String topicId;
  final ForumController controller;
  final ContentModerationRepository moderationRepository;
  final String viewerId;

  @override
  State<ForumTopicScreen> createState() => _ForumTopicScreenState();
}

class _ForumTopicScreenState extends State<ForumTopicScreen> {
  final _reply = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Denetleyici ilk bildirimini beklemeden gönderiyor; bu kare çizilirken
    // istemek, çizim sırasında yeniden çizim istemek olurdu.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.controller.openTopicById(widget.topicId),
    );
  }

  @override
  void dispose() {
    _reply.dispose();
    widget.controller.closeTopic();
    super.dispose();
  }

  Future<void> _sendReply() async {
    final body = _reply.text.trim();
    if (body.isEmpty || widget.controller.isSending) return;
    try {
      await widget.controller.reply(widget.topicId, body);
      _reply.clear();
      if (mounted) FocusScope.of(context).unfocus();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yanıt gönderilemedi.')),
        );
      }
    }
  }

  Future<void> _report({
    required ContentReportTarget target,
    required String id,
    required String label,
  }) async {
    final filed = await showContentReportSheet(
      context,
      repository: widget.moderationRepository,
      targetType: target,
      targetId: id,
      subjectLabel: label,
    );
    if (filed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bildirimin moderasyona iletildi.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      title: const Text(
        'Konu',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
      ),
      actions: [
        AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            final topic = widget.controller.openTopic;
            if (topic == null || topic.authorId == widget.viewerId) {
              return const SizedBox.shrink();
            }
            return IconButton(
              tooltip: 'Bildir',
              icon: const Icon(Icons.flag_outlined, size: 20),
              onPressed: () => _report(
                target: ContentReportTarget.forumTopic,
                id: topic.id,
                label: topic.title,
              ),
            );
          },
        ),
      ],
    ),
    body: AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final topic = widget.controller.openTopic;
        return Column(
          children: [
            Expanded(
              child: topic == null
                  ? const AppLoadingView(label: 'Konu yükleniyor…')
                  : _buildBody(topic),
            ),
            if (topic != null) _buildReplyBar(topic),
          ],
        );
      },
    ),
  );

  Widget _buildBody(ForumTopic topic) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
    children: [
      _TopicHeader(
        topic: topic,
        onToggleLike: () => widget.controller.toggleTopicLike(topic.id),
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Text(
            '${topic.replyCount} yanıt',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      switch (widget.controller.replies) {
        AsyncLoading<List<ForumReply>>() => const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: AppLoadingView(label: 'Yanıtlar yükleniyor…'),
        ),
        AsyncFailure<List<ForumReply>>(:final message) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: AppErrorState(
            message: message,
            onRetry: () => widget.controller.openTopicById(topic.id),
          ),
        ),
        AsyncData<List<ForumReply>>(value: final replies) when replies.isEmpty =>
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'Henüz yanıt yok. İlk yazan sen ol.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
        AsyncData<List<ForumReply>>(value: final replies) => Column(
          children: [
            for (final reply in replies)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ReplyCard(
                  reply: reply,
                  isOwn: reply.authorId == widget.viewerId,
                  onToggleLike: () =>
                      widget.controller.toggleReplyLike(reply.id),
                  onReport: () => _report(
                    target: ContentReportTarget.forumReply,
                    id: reply.id,
                    label: reply.body,
                  ),
                ),
              ),
          ],
        ),
      },
    ],
  );

  Widget _buildReplyBar(ForumTopic topic) {
    if (topic.isLocked) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        color: Colors.white,
        child: const Text(
          '🔒 Bu konu kapatıldı; okunmaya devam ediyor ama yeni yanıt '
          'yazılamıyor.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
      );
    }
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.surfaceBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _reply,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Yanıtını yaz…',
                isDense: true,
                filled: true,
                fillColor: AppColors.background,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: widget.controller.isSending ? null : _sendReply,
            style: IconButton.styleFrom(backgroundColor: AppColors.primary),
            icon: const Icon(Icons.send_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _TopicHeader extends StatelessWidget {
  const _TopicHeader({required this.topic, required this.onToggleLike});

  final ForumTopic topic;
  final VoidCallback onToggleLike;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.surfaceBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          topic.categoryTitle.toUpperCase(),
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: .8,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          topic.title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            height: 1.3,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${topic.authorName} • ${forumTimeAgo(topic.createdAt)} • '
          '${topic.viewCount} görüntülenme',
          style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
        ),
        const SizedBox(height: 12),
        Text(
          topic.body,
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _LikeButton(
              isLiked: topic.isLiked,
              count: topic.likeCount,
              onPressed: onToggleLike,
            ),
          ],
        ),
      ],
    ),
  );
}

class _ReplyCard extends StatelessWidget {
  const _ReplyCard({
    required this.reply,
    required this.isOwn,
    required this.onToggleLike,
    required this.onReport,
  });

  final ForumReply reply;
  final bool isOwn;
  final VoidCallback onToggleLike;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: reply.isAcceptedAnswer
            ? AppColors.accentEmerald.withValues(alpha: .5)
            : AppColors.surfaceBorder,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                reply.authorName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (reply.isAcceptedAnswer)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Text(
                  '✓ İşe yarayan yanıt',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accentEmerald,
                  ),
                ),
              ),
            Text(
              forumTimeAgo(reply.createdAt),
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          reply.body,
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.45,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _LikeButton(
              isLiked: reply.isLiked,
              count: reply.likeCount,
              onPressed: onToggleLike,
            ),
            const Spacer(),
            // Kendi yazdığını bildirmenin anlamı yok.
            if (!isOwn)
              TextButton(
                onPressed: onReport,
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Bildir',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

class _LikeButton extends StatelessWidget {
  const _LikeButton({
    required this.isLiked,
    required this.count,
    required this.onPressed,
  });

  final bool isLiked;
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      minimumSize: Size.zero,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      foregroundColor: isLiked ? AppColors.primary : AppColors.textSecondary,
    ),
    icon: Icon(
      isLiked ? Icons.thumb_up_rounded : Icons.thumb_up_outlined,
      size: 15,
    ),
    label: Text(
      '$count',
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );
}
