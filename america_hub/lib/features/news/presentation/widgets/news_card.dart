import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_remote_image.dart';
import '../../domain/entities/news_article.dart';

/// Haber Merkezi listesindeki kart.
///
/// Ana sayfadaki manşet şeridi bu kartı kullanmaz — orası dar bir şerit — ama
/// ikisi de aynı [NewsArticle] alanlarını okur; sayaçlar tek yerden geldiği için
/// listede beğenip geri dönünce şerit de aynı sayıyı gösterir.
class NewsCard extends StatelessWidget {
  const NewsCard({super.key, required this.article, required this.onTap});

  final NewsArticle article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.surfaceBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (article.imageUrl case final String url)
              SizedBox(
                height: 158,
                width: double.infinity,
                child: AppRemoteImage(
                  imageUrl: url,
                  semanticLabel: article.title,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      NewsCategoryChip(category: article.category),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          article.timeLabel(),
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                      if (article.regionCode case final String region)
                        Text(
                          region,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    article.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      height: 1.3,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    article.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _Counter(
                        icon: Icons.thumb_up_alt_outlined,
                        value: article.likeCount,
                        highlighted:
                            article.viewerReaction == NewsReaction.like,
                      ),
                      const SizedBox(width: 14),
                      _Counter(
                        icon: Icons.thumb_down_alt_outlined,
                        value: article.dislikeCount,
                        highlighted:
                            article.viewerReaction == NewsReaction.dislike,
                      ),
                      const SizedBox(width: 14),
                      _Counter(
                        icon: Icons.mode_comment_outlined,
                        value: article.commentCount,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class NewsCategoryChip extends StatelessWidget {
  const NewsCategoryChip({super.key, required this.category});

  final NewsCategory category;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      category.label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: AppColors.primary,
      ),
    ),
  );
}

class _Counter extends StatelessWidget {
  const _Counter({
    required this.icon,
    required this.value,
    this.highlighted = false,
  });

  final IconData icon;
  final int value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color = highlighted ? AppColors.primary : AppColors.textMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Text(
          '$value',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
