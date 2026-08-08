import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_remote_image.dart';
import '../../application/story_controller.dart';
import '../../domain/entities/feed_extensions.dart';
import '../../domain/entities/community_post.dart';

/// Full-screen, API-backed story viewer. It deliberately contains no fake
/// messaging transport: replies will be enabled after the Matrix DM gateway
/// is available to the signed-in member.
class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen({
    super.key,
    required this.controller,
    required this.initialStoryId,
  });

  final StoryController controller;
  final String initialStoryId;

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  late final PageController _pageController;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _index = widget.controller.items.indexWhere(
      (item) => item.id == widget.initialStoryId,
    );
    if (_index < 0) _index = 0;
    _pageController = PageController(initialPage: _index);
    WidgetsBinding.instance.addPostFrameCallback((_) => _markCurrentViewed());
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _markCurrentViewed() {
    final items = widget.controller.items;
    if (_index >= 0 && _index < items.length) {
      widget.controller.markViewed(items[_index].id);
    }
  }

  void _onPageChanged(int value) {
    setState(() => _index = value);
    _markCurrentViewed();
    final items = widget.controller.items;
    if (value >= items.length - 3) widget.controller.loadMore();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final stories = widget.controller.items;
      if (stories.isEmpty) {
        return const Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Center(
              child: Text(
                'Gösterilecek Story bulunamadı.',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        );
      }
      final safeIndex = _index.clamp(0, stories.length - 1) as int;
      final current = stories[safeIndex];
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _pageController,
                itemCount: stories.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (_, index) => _StoryCanvas(story: stories[index]),
              ),
              Positioned(
                top: 10,
                left: 12,
                right: 12,
                child: _StoryHeader(
                  stories: stories,
                  activeIndex: safeIndex,
                  current: current,
                  onClose: () => Navigator.of(context).pop(),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 14,
                child: _StoryActions(
                  story: current,
                  onLike: (value) => widget.controller.setLiked(
                    current.id,
                    value,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _StoryCanvas extends StatelessWidget {
  const _StoryCanvas({required this.story});
  final StoryItem story;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      if (story.media.previewBytes != null)
        Image.memory(story.media.previewBytes!, fit: BoxFit.cover)
      else
        AppRemoteImage(
          imageUrl: story.media.thumbnailUrl ?? story.media.url,
          semanticLabel: '${story.authorName} Story medyası',
        ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x77000000), Color(0x00000000), Color(0x99000000)],
            stops: [0, .45, 1],
          ),
        ),
      ),
      if (story.media.type == PostMediaType.video)
        const Center(
          child: CircleAvatar(
            radius: 32,
            backgroundColor: Color(0x99000000),
            child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 42),
          ),
        ),
    ],
  );
}

class _StoryHeader extends StatelessWidget {
  const _StoryHeader({
    required this.stories,
    required this.activeIndex,
    required this.current,
    required this.onClose,
  });
  final List<StoryItem> stories;
  final int activeIndex;
  final StoryItem current;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          for (var index = 0; index < stories.length; index++)
            Expanded(
              child: Container(
                height: 3,
                margin: EdgeInsets.only(right: index == stories.length - 1 ? 0 : 3),
                decoration: BoxDecoration(
                  color: index <= activeIndex
                      ? Colors.white
                      : Colors.white.withValues(alpha: .38),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white.withValues(alpha: .95),
            child: Text(
              current.authorName.isEmpty
                  ? '?'
                  : current.authorName.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              current.authorName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            onPressed: onClose,
            tooltip: 'Kapat',
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ],
      ),
    ],
  );
}

class _StoryActions extends StatelessWidget {
  const _StoryActions({required this.story, required this.onLike});
  final StoryItem story;
  final ValueChanged<bool> onLike;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: FilledButton.tonalIcon(
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Story yanıtları güvenli Mesajlar altyapısı açıldığında etkinleşecek.'),
            ),
          ),
          icon: const Icon(Icons.send_outlined),
          label: const Text('Yanıt yaz'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: .94),
            foregroundColor: AppColors.textPrimary,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Semantics(
        button: true,
        label: story.isLiked ? 'Beğeniyi geri al' : 'Story beğen',
        child: IconButton.filled(
          onPressed: () => onLike(!story.isLiked),
          style: IconButton.styleFrom(
            backgroundColor: story.isLiked
                ? const Color(0xFFE87393)
                : Colors.white.withValues(alpha: .94),
            foregroundColor: story.isLiked ? Colors.white : AppColors.accentRose,
          ),
          icon: Icon(
            story.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          ),
        ),
      ),
      if (story.likeCount > 0)
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            '${story.likeCount}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ),
    ],
  );
}
