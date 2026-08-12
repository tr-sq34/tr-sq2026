import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_remote_image.dart';
import '../../../../core/widgets/app_state_views.dart';
import '../../../community/application/community_comments_controller.dart';
import '../../../community/domain/repositories/content_moderation_repository.dart';
import '../../../community/presentation/widgets/comments_sheet.dart';
import '../../application/news_controller.dart';
import '../../domain/entities/news_article.dart';
import '../widgets/news_card.dart';

/// Haberin kendisi: gövde, beğen/beğenme ve yorumlar.
///
/// Yorum bölümü akıştaki [CommentsSheet]'in ta kendisidir — istenen buydu:
/// "yorum yap editör yazı yazma kısmı akışdakiyle birebir aynı olmalı."
class NewsArticleScreen extends StatefulWidget {
  const NewsArticleScreen({
    super.key,
    required this.articleId,
    required this.controller,
    required this.commentsController,
    required this.moderationRepository,
    required this.viewerId,
  });

  final String articleId;
  final NewsController controller;
  final CommunityCommentsController commentsController;
  final ContentModerationRepository moderationRepository;

  /// Yorumu kimin silebileceğini belirler: haberde kural tek satır, kendi
  /// yorumunu silersin. Sunucu da aynı kuralı ayrıca uygular.
  final String viewerId;

  @override
  State<NewsArticleScreen> createState() => _NewsArticleScreenState();
}

class _NewsArticleScreenState extends State<NewsArticleScreen> {
  late Future<NewsArticle> _article;

  @override
  void initState() {
    super.initState();
    _article = widget.controller.openArticle(widget.articleId);
  }

  void _reload() =>
      setState(() => _article = widget.controller.openArticle(widget.articleId));

  Future<void> _react(NewsReaction reaction) async {
    try {
      await widget.controller.react(widget.articleId, reaction);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tepkin kaydedilemedi.')),
        );
      }
    }
  }

  void _openComments(NewsArticle article) => showAppBottomSheet(
    context: context,
    child: CommentsSheet(
      targetId: article.id,
      controller: widget.commentsController,
      moderationRepository: widget.moderationRepository,
      commentsEnabled: article.commentsEnabled,
      subtitle: 'Bu haber hakkında ne düşünüyorsun?',
      disabledMessage: 'Bu haber yorumlara kapalı.',
      onSubmit: (message, parentId) async {
        await widget.commentsController.submitComment(
          targetId: article.id,
          message: message,
          parentId: parentId,
        );
        widget.controller.registerComment(article.id);
      },
      onDelete: widget.commentsController.removeComment,
      canDelete: (comment) => comment.authorId == widget.viewerId,
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      title: const Text(
        'Haber',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
      ),
    ),
    body: FutureBuilder<NewsArticle>(
      future: _article,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppErrorState(
            message: 'Haber açılamadı.',
            onRetry: _reload,
          );
        }
        if (!snapshot.hasData) {
          return const AppLoadingView(label: 'Haber yükleniyor…');
        }
        // Sayaçlar denetleyicide durur: beğeni listedeki kaydı da güncellediği
        // için gösterilecek hâl her zaman oradan okunur.
        return AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) => _ArticleBody(
            article:
                widget.controller.opened(widget.articleId) ?? snapshot.data!,
            onReact: _react,
            onOpenComments: _openComments,
          ),
        );
      },
    ),
  );
}

class _ArticleBody extends StatelessWidget {
  const _ArticleBody({
    required this.article,
    required this.onReact,
    required this.onOpenComments,
  });

  final NewsArticle article;
  final ValueChanged<NewsReaction> onReact;
  final ValueChanged<NewsArticle> onOpenComments;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(child: _content()),
      // Beğen/beğenme ve yorumlar sabit bir şeritte: gövde uzun olduğu için
      // yazının sonuna gömülmüş bir satır, uzun haberlerde hiç görülmezdi.
      _ActionBar(
        article: article,
        onReact: onReact,
        onOpenComments: onOpenComments,
      ),
    ],
  );

  Widget _content() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
    children: [
      if (article.imageUrl case final String url)
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: 200,
            width: double.infinity,
            child: AppRemoteImage(imageUrl: url, semanticLabel: article.title),
          ),
        ),
      if (article.imageUrl != null) const SizedBox(height: 16),
      Row(
        children: [
          NewsCategoryChip(category: article.category),
          const SizedBox(width: 8),
          Text(
            article.timeLabel(),
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Text(
        article.title,
        style: const TextStyle(
          fontSize: 22,
          height: 1.25,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        article.authorName,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: 16),
      Text(
        article.summary,
        style: const TextStyle(
          fontSize: 15,
          height: 1.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: 16),
      // Gövde paragraf paragraf: sunucu düz metin saklıyor, boş satır paragrafı
      // ayırıyor.
      for (final paragraph in (article.body ?? '').split('\n\n'))
        if (paragraph.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              paragraph.trim(),
              style: const TextStyle(
                fontSize: 15,
                height: 1.6,
                color: AppColors.textPrimary,
              ),
            ),
          ),
    ],
  );
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.article,
    required this.onReact,
    required this.onOpenComments,
  });

  final NewsArticle article;
  final ValueChanged<NewsReaction> onReact;
  final ValueChanged<NewsArticle> onOpenComments;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
    decoration: const BoxDecoration(
      color: AppColors.surface,
      border: Border(top: BorderSide(color: AppColors.surfaceBorder)),
    ),
    child: SafeArea(
      top: false,
      child: Row(
        children: [
          _ReactionButton(
            icon: Icons.thumb_up_alt_rounded,
            label: '${article.likeCount}',
            active: article.viewerReaction == NewsReaction.like,
            onTap: () => onReact(NewsReaction.like),
          ),
          const SizedBox(width: 10),
          _ReactionButton(
            icon: Icons.thumb_down_alt_rounded,
            label: '${article.dislikeCount}',
            active: article.viewerReaction == NewsReaction.dislike,
            onTap: () => onReact(NewsReaction.dislike),
          ),
          const Spacer(),
          // Dar ekranda kısalır, taşmaz: sayaç her zaman görünür kalmalı.
          Flexible(
            child: _ReactionButton(
              icon: Icons.mode_comment_outlined,
              label: 'Yorumlar (${article.commentCount})',
              active: false,
              onTap: () => onOpenComments(article),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.textSecondary;
    return Material(
      color: active
          ? AppColors.primary.withValues(alpha: .1)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active ? AppColors.primary : AppColors.surfaceBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
