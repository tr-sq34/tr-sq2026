import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_remote_image.dart';
import '../../application/story_controller.dart';
import '../../domain/entities/feed_extensions.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/entities/content_report.dart';
import '../../domain/repositories/content_moderation_repository.dart';
import '../widgets/content_report_sheet.dart';

/// Bir slaytın ekranda kalma süresi.
///
/// Fotoğraf kendini anlatmıyor: adres, tarih, fiyat gibi şeyler okunacaksa
/// birkaç saniye yetmiyor. Bu yüzden slayt bir dakika duruyor; acelesi olan
/// zaten sağa dokunup geçiyor.
const Duration _slideDuration = Duration(seconds: 60);

/// Tam ekran Story görüntüleyici.
class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen({
    super.key,
    required this.controller,
    required this.initialStoryId,
    required this.moderationRepository,
  });

  final StoryController controller;
  final String initialStoryId;

  /// A story disappears in 24 hours, which is exactly the window a report has
  /// to be filed in. The service copies the media reference into the report so
  /// expiry does not take the evidence with it.
  final ContentModerationRepository moderationRepository;

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  late final AnimationController _progress;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _index = widget.controller.items.indexWhere(
      (item) => item.id == widget.initialStoryId,
    );
    if (_index < 0) _index = 0;
    // `keepPage: false`: açılacak slaytı dokunulan Story belirliyor, sayfa
    // deposunda kalmış eski bir numara değil.
    _pageController = PageController(initialPage: _index, keepPage: false);
    _progress = AnimationController(vsync: this, duration: _slideDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _goNext();
      });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markCurrentViewed();
      _progress.forward();
    });
  }

  @override
  void dispose() {
    _progress.dispose();
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
    _progress
      ..reset()
      ..forward();
    final items = widget.controller.items;
    if (value >= items.length - 3) widget.controller.loadMore();
  }

  /// Süre dolduğunda ya da sağ yarıya dokunulduğunda çalışır. Son slayttan
  /// sonra görüntüleyici kapanıyor: baştan başlamak, biten bir şeyi bitmemiş
  /// gibi göstermek olurdu.
  void _goNext() {
    final last = widget.controller.items.length - 1;
    if (_index >= last) {
      Navigator.of(context).maybePop();
      return;
    }
    _pageController.animateToPage(
      _index + 1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _goPrevious() {
    if (_index <= 0) {
      _progress
        ..reset()
        ..forward();
      return;
    }
    _pageController.animateToPage(
      _index - 1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _onTapUp(TapUpDetails details, double width) {
    // Sol üçte bir geri, kalanı ileri: baş parmağın doğal yeri sağ tarafta,
    // yani sık yapılan hareket ileri gitmek.
    if (details.localPosition.dx < width / 3) {
      _goPrevious();
    } else {
      _goNext();
    }
  }

  /// Bir tabaka açıkken sayaç durur, kapanınca kaldığı yerden devam eder:
  /// yanıt yazarken slaytın altından kayması, yanıtı yanlış Story'ye yazdırır.
  Future<void> _pausedWhile(Future<void> Function() action) async {
    _progress.stop();
    await action();
    if (mounted) _progress.forward();
  }

  Future<void> _openReply(StoryItem story) => _pausedWhile(() async {
    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StoryReplySheet(authorName: story.authorName),
    );
    if (message == null || !mounted) return;
    try {
      await widget.controller.sendReply(storyId: story.id, message: message);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Yanıtın ${story.authorName} kişisine gönderildi.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is UnsupportedError
                ? error.message ?? 'Yanıtın gönderilemedi.'
                : 'Yanıtın gönderilemedi.',
          ),
        ),
      );
    }
  });

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
      final safeIndex = _index.clamp(0, stories.length - 1);
      final current = stories[safeIndex];
      final width = MediaQuery.sizeOf(context).width;
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
              // Dokunma katmanı görselin üstünde ama başlık ve alt düğmelerin
              // altında duruyor: kapat düğmesine basmak slaytı ilerletmemeli.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: (details) => _onTapUp(details, width),
                  onLongPressStart: (_) => _progress.stop(),
                  onLongPressEnd: (_) => _progress.forward(),
                  onLongPressCancel: () => _progress.forward(),
                ),
              ),
              Positioned(
                top: 10,
                left: 12,
                right: 12,
                child: _StoryHeader(
                  stories: stories,
                  activeIndex: safeIndex,
                  current: current,
                  progress: _progress,
                  onClose: () => Navigator.of(context).pop(),
                  onReport: () => _pausedWhile(
                    () => showContentReportSheet(
                      context,
                      repository: widget.moderationRepository,
                      targetType: ContentReportTarget.story,
                      targetId: current.id,
                      subjectLabel: current.authorName,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 14,
                child: _StoryActions(
                  story: current,
                  onLike: (value) =>
                      widget.controller.setLiked(current.id, value),
                  onReply: () => _openReply(current),
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
    required this.progress,
    required this.onClose,
    required this.onReport,
  });
  final List<StoryItem> stories;
  final int activeIndex;
  final StoryItem current;
  final Animation<double> progress;
  final VoidCallback onClose;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          for (var index = 0; index < stories.length; index++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: index == stories.length - 1 ? 0 : 3,
                ),
                child: _ProgressBar(
                  // Geçilmiş slayt dolu, sıradakiler boş, içinde bulunulan
                  // slayt ise sayaçla birlikte doluyor.
                  fill: index < activeIndex
                      ? const AlwaysStoppedAnimation<double>(1)
                      : index > activeIndex
                      ? const AlwaysStoppedAnimation<double>(0)
                      : progress,
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
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          // Reporting sits next to close, on the story itself: a story is
          // gone in 24 hours, so a reporting path that needs the user to leave
          // the viewer and find it elsewhere is a path they will not finish.
          IconButton(
            onPressed: onReport,
            tooltip: 'Şikâyet et',
            icon: const Icon(Icons.flag_outlined, color: Colors.white),
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

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.fill});
  final Animation<double> fill;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: SizedBox(
      height: 3,
      child: AnimatedBuilder(
        animation: fill,
        builder: (context, _) => LinearProgressIndicator(
          value: fill.value.clamp(0.0, 1.0),
          minHeight: 3,
          backgroundColor: Colors.white.withValues(alpha: .38),
          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      ),
    ),
  );
}

class _StoryActions extends StatelessWidget {
  const _StoryActions({
    required this.story,
    required this.onLike,
    required this.onReply,
  });
  final StoryItem story;
  final ValueChanged<bool> onLike;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: FilledButton.tonalIcon(
          onPressed: onReply,
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
            story.isLiked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
          ),
        ),
      ),
      if (story.likeCount > 0)
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            '${story.likeCount}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
    ],
  );
}

/// Story'nin sahibine gidecek kısa yanıt.
class _StoryReplySheet extends StatefulWidget {
  const _StoryReplySheet({required this.authorName});
  final String authorName;

  @override
  State<_StoryReplySheet> createState() => _StoryReplySheetState();
}

class _StoryReplySheetState extends State<_StoryReplySheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final message = _controller.text.trim();
    if (message.isEmpty) return;
    Navigator.pop(context, message);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1823),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF3A3748),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '${widget.authorName} kişisine yanıt',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 1000,
            maxLines: 3,
            minLines: 1,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Bir şeyler yaz…',
              hintStyle: const TextStyle(color: Color(0xFF9C97AC)),
              counterStyle: const TextStyle(color: Color(0xFF9C97AC)),
              filled: true,
              fillColor: const Color(0xFF221F2E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Yanıtın yalnızca Story sahibine gider.',
                  style: TextStyle(color: Color(0xFF9C97AC), fontSize: 12),
                ),
              ),
              const SizedBox(width: 10),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) => FilledButton(
                  onPressed: value.text.trim().isEmpty ? null : _send,
                  child: const Text('Gönder'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
