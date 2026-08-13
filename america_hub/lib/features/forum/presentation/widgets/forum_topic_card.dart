import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../domain/entities/forum.dart';

/// Konu listesindeki tek kart. Ana sayfadaki trend şeridi de bunu kullanıyor:
/// iki yerde iki farklı kart çizmek, aynı konunun iki farklı sayıyla
/// görünmesiyle biten bir yol.
class ForumTopicCard extends StatelessWidget {
  const ForumTopicCard({
    super.key,
    required this.topic,
    required this.onTap,
    this.showCategory = true,
  });

  final ForumTopic topic;
  final VoidCallback onTap;
  final bool showCategory;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.surfaceBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (showCategory)
                  Flexible(
                    child: Text(
                      topic.categoryTitle.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .8,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                if (topic.isPinned) ...[
                  const SizedBox(width: 8),
                  const _Badge(
                    label: '📌 SABİT',
                    color: AppColors.accentEmerald,
                  ),
                ],
                if (topic.isHot) ...[
                  const SizedBox(width: 8),
                  const _Badge(
                    label: '🔥 SICAK TARTIŞMA',
                    color: AppColors.accentRose,
                  ),
                ],
                const Spacer(),
                Text(
                  _compact(topic.viewCount),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(width: 3),
                const Icon(
                  Icons.visibility_outlined,
                  size: 13,
                  color: AppColors.textMuted,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              topic.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                height: 1.3,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    // Yanıt varsa son yazan, yoksa konuyu açan: listede önemli
                    // olan konuşmanın nerede durduğu.
                    topic.lastReplyAuthorName != null
                        ? 'Son yanıt: ${topic.lastReplyAuthorName} '
                              '(${forumTimeAgo(topic.lastActivityAt)})'
                        : '${topic.authorName} • '
                              '${forumTimeAgo(topic.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  topic.isLocked
                      ? '🔒 Kapalı'
                      : '💬 ${topic.replyCount} Yanıt',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  /// 2412 → "2.4k": sayı kartın üst satırında yer kaplamasın.
  static String _compact(int value) => value < 1000
      ? '$value'
      : '${(value / 1000).toStringAsFixed(value < 10000 ? 1 : 0)}k';
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w800,
        letterSpacing: .5,
        color: color,
      ),
    ),
  );
}
