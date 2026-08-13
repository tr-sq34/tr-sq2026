import 'package:flutter/material.dart';

import '../../../../core/state/async_state.dart';
import '../../application/forum_controller.dart';
import '../../domain/entities/forum.dart';

/// Ana sayfadaki "Forumda trend tartışmalar" şeridi.
///
/// Buradaki kart uydurulmuş bir tartışmayı gösteriyordu: başlık da, "48 yanıt"
/// da, son yazan da elle yazılmıştı ve hiçbir yere gitmiyordu. Artık forumun
/// kendi verisini okuyor — şeritteki konu, dokununca açılan konunun ta kendisi.
class ForumTrendingSection extends StatelessWidget {
  const ForumTrendingSection({
    super.key,
    required this.controller,
    required this.onOpenForum,
    required this.onOpenTopic,
  });

  final ForumController controller;

  /// null kategori: "Tüm Forum".
  final ValueChanged<String?> onOpenForum;
  final ValueChanged<ForumTopic> onOpenTopic;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final topics = switch (controller.trending) {
        AsyncData<List<ForumTopic>>(:final value) => value,
        _ => const <ForumTopic>[],
      };
      // Forum boşken başlığı tek başına göstermenin anlamı yok.
      if (topics.isEmpty) return const SizedBox.shrink();
      final categories = switch (controller.categories) {
        AsyncData<List<ForumCategory>>(:final value) => value,
        _ => const <ForumCategory>[],
      };
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.whatshot_rounded,
                      size: 14,
                      color: Color(0xFFFBBF24),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'FORUMDA TREND TARTIŞMALAR',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF334155),
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: () => onOpenForum(null),
                  child: const Text(
                    'Tüm Forum >',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6355D8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 30,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  GestureDetector(
                    onTap: () => onOpenForum(null),
                    child: const _FilterChip(label: '🔥 Tümü', isActive: true),
                  ),
                  for (final category in categories.take(4)) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => onOpenForum(category.id),
                      child: _FilterChip(
                        label: '${category.emoji} ${category.title}',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (final topic in topics) ...[
              _TopicPreviewCard(topic: topic, onTap: () => onOpenTopic(topic)),
              if (topic != topics.last) const SizedBox(height: 10),
            ],
          ],
        ),
      );
    },
  );
}

class _TopicPreviewCard extends StatelessWidget {
  const _TopicPreviewCard({required this.topic, required this.onTap});

  final ForumTopic topic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F3FF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    topic.categoryTitle.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF6355D8),
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              // Rozet bir editör kararı değil: son gün içinde konuşulmaya devam
              // eden ve yanıt almış konular alıyor.
              if (topic.isHot) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '🔥 SICAK TARTIŞMA',
                    style: TextStyle(
                      color: Color(0xFFF43F5E),
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              const Icon(
                Icons.visibility_outlined,
                size: 12,
                color: Color(0xFF94A3B8),
              ),
              const SizedBox(width: 4),
              Text(
                _compactCount(topic.viewCount),
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            topic.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Color(0xFF0F172A),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFFF1F5F9), height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  topic.lastReplyAuthorName != null
                      ? 'Son yanıt: ${topic.lastReplyAuthorName} '
                            '(${forumTimeAgo(topic.lastActivityAt)})'
                      : '${topic.authorName} • '
                            '${forumTimeAgo(topic.createdAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 10,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '💬 ${topic.replyCount} Yanıt',
                  style: const TextStyle(
                    color: Color(0xFF6355D8),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  /// 2412 → "2.4k": sayı kartın üst satırında yer kaplamasın.
  static String _compactCount(int value) => value < 1000
      ? '$value'
      : '${(value / 1000).toStringAsFixed(value < 10000 ? 1 : 0)}k';
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, this.isActive = false});

  final String label;
  final bool isActive;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(
      color: isActive ? const Color(0xFF6355D8) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: isActive ? const Color(0xFF6355D8) : const Color(0xFFE2E8F0),
      ),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: isActive ? Colors.white : const Color(0xFF64748B),
        fontSize: 10,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}
