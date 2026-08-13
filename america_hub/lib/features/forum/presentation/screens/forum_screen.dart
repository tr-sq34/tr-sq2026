import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/state/async_state.dart';
import '../../../../core/widgets/app_state_views.dart';
import '../../../community/domain/repositories/content_moderation_repository.dart';
import '../../application/forum_controller.dart';
import '../../domain/entities/forum.dart';
import '../widgets/forum_topic_card.dart';
import '../widgets/topic_composer_sheet.dart';
import 'forum_topic_screen.dart';

/// Sağ çeker menüdeki Forum.
///
/// Akıştan ayrı durmasının sebebi ömrü: akış bugünün gündemi, forum ise bir yıl
/// sonra da aranıp bulunacak bir soru-cevap arşivi. Bu yüzden burada kategori
/// var, "sıcak tartışma" rozeti var, ama Story ve beğeni akışı yok.
class ForumScreen extends StatefulWidget {
  const ForumScreen({
    super.key,
    required this.controller,
    required this.moderationRepository,
    required this.viewerId,
    this.initialCategoryId,
  });

  final ForumController controller;
  final ContentModerationRepository moderationRepository;
  final String viewerId;

  /// Ana sayfadaki trend şeridinden gelindiğinde o kategori seçili açılıyor.
  final String? initialCategoryId;

  @override
  State<ForumScreen> createState() => _ForumScreenState();
}

class _ForumScreenState extends State<ForumScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.loadTopics(categoryId: widget.initialCategoryId);
      widget.controller.load();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 320) {
      widget.controller.loadMoreTopics();
    }
  }

  Future<void> _openTopic(ForumTopic topic) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ForumTopicScreen(
          topicId: topic.id,
          controller: widget.controller,
          moderationRepository: widget.moderationRepository,
          viewerId: widget.viewerId,
        ),
      ),
    );
  }

  Future<void> _composeTopic() async {
    final categories = switch (widget.controller.categories) {
      AsyncData<List<ForumCategory>>(:final value) => value,
      _ => const <ForumCategory>[],
    };
    if (categories.isEmpty) return;
    final topic = await showTopicComposerSheet(
      context,
      controller: widget.controller,
      categories: categories,
      initialCategoryId: widget.controller.categoryId ?? categories.first.id,
    );
    if (topic != null && mounted) await _openTopic(topic);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      title: const Text(
        'Forum',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
      ),
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _composeTopic,
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.edit_rounded, size: 18),
      label: const Text(
        'Konu aç',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    body: AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => Column(
        children: [
          _CategoryBar(
            categories: switch (widget.controller.categories) {
              AsyncData<List<ForumCategory>>(:final value) => value,
              _ => const <ForumCategory>[],
            },
            selectedId: widget.controller.categoryId,
            onSelected: (id) => widget.controller.loadTopics(categoryId: id),
          ),
          _SortBar(
            sort: widget.controller.sort,
            onSelected: (sort) => widget.controller.loadTopics(
              categoryId: widget.controller.categoryId,
              sort: sort,
            ),
          ),
          Expanded(child: _buildList()),
        ],
      ),
    ),
  );

  Widget _buildList() => switch (widget.controller.topics) {
    AsyncLoading<List<ForumTopic>>() => const AppLoadingView(
      label: 'Konular yükleniyor…',
    ),
    AsyncFailure<List<ForumTopic>>(:final message) => AppErrorState(
      message: message,
      onRetry: () =>
          widget.controller.loadTopics(categoryId: widget.controller.categoryId),
    ),
    AsyncData<List<ForumTopic>>(value: final topics) when topics.isEmpty =>
      AppEmptyState(
        icon: Icons.forum_rounded,
        title: 'Burada henüz konu yok',
        message:
            'İlk soruyu sen sor. Bir yıl sonra aynı soruyu arayan biri senin '
            'yazdığını bulacak.',
        actionLabel: 'Konu aç',
        onAction: _composeTopic,
      ),
    AsyncData<List<ForumTopic>>(value: final topics) => RefreshIndicator(
      onRefresh: () =>
          widget.controller.loadTopics(categoryId: widget.controller.categoryId),
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: topics.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) => ForumTopicCard(
          topic: topics[index],
          onTap: () => _openTopic(topics[index]),
        ),
      ),
    ),
  };
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.categories,
    required this.selectedId,
    required this.onSelected,
  });

  final List<ForumCategory> categories;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        _chip(label: '🔥 Tümü', value: null),
        for (final category in categories)
          _chip(
            label: '${category.emoji} ${category.title}',
            value: category.id,
          ),
      ],
    ),
  );

  Widget _chip({required String label, required String? value}) {
    final isSelected = selectedId == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => onSelected(value),
        showCheckmark: false,
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primary.withValues(alpha: .12),
        side: BorderSide(
          color: isSelected ? AppColors.primary : AppColors.surfaceBorder,
        ),
        labelStyle: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: isSelected ? AppColors.primary : AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _SortBar extends StatelessWidget {
  const _SortBar({required this.sort, required this.onSelected});

  final ForumTopicSort sort;
  final ValueChanged<ForumTopicSort> onSelected;

  static const _labels = {
    ForumTopicSort.latestActivity: 'Son hareket',
    ForumTopicSort.newest: 'En yeni',
    ForumTopicSort.mostReplies: 'En çok yanıt',
  };

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 12, 6),
    child: Row(
      children: [
        const Text(
          'Sırala',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: .6,
            color: AppColors.textMuted,
          ),
        ),
        const Spacer(),
        PopupMenuButton<ForumTopicSort>(
          initialValue: sort,
          onSelected: onSelected,
          itemBuilder: (_) => [
            for (final entry in _labels.entries)
              PopupMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _labels[sort]!,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
              const Icon(
                Icons.arrow_drop_down_rounded,
                color: AppColors.primary,
                size: 20,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
