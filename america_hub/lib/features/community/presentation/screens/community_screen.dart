import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';

import '../../../auth/domain/entities/app_user.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/pagination/paged_controller.dart';
import '../../../../core/widgets/app_image_source.dart';
import '../../../../core/widgets/app_remote_image.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_screen_header.dart';
import '../../../../core/widgets/app_state_views.dart';
import '../../../../core/widgets/paged_list_footer.dart';
import '../../application/community_feed_controller.dart';
import '../../application/story_controller.dart';
import '../../application/community_comments_controller.dart';
import '../../application/media_upload_controller.dart';
import '../../application/community_special_request_controller.dart';
import '../../../promotions/application/promotions_controller.dart';
import '../widgets/comments_sheet.dart';
import '../widgets/special_post_request_sheet.dart';
import '../../domain/repositories/content_moderation_repository.dart';
import '../widgets/content_report_sheet.dart';
import '../widgets/story_composer_sheet.dart';
import 'story_viewer_screen.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/entities/content_report.dart';
import '../../domain/entities/create_post_draft.dart';
import '../../domain/entities/post_media_upload.dart';
import '../../domain/services/post_access_policy.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({
    super.key,
    required this.controller,
    required this.storyController,
    required this.commentsController,
    required this.mediaUploadController,
    required this.specialRequestController,
    required this.moderationRepository,
    required this.promotionsController,
    this.viewer,
  });
  final CommunityFeedController controller;
  final StoryController storyController;
  final CommunityCommentsController commentsController;
  final MediaUploadController mediaUploadController;
  final CommunitySpecialRequestController specialRequestController;

  /// Story oluşturma akışındaki "Tanıtım Yap" adımı buradan gönderilir:
  /// paylaşılan görsel, sponsorlu alan talebinin de görseli olur.
  final PromotionsController promotionsController;

  /// The signed-in member, so the composer can say who is about to post. Null
  /// only in builds with no session, where the composer names nobody at all.
  final AppUser? viewer;

  /// Every post, comment and story below this point needs a way to be reported,
  /// so the repository is handed down rather than looked up: the widgets that
  /// need it are built inside list builders with no other access to the app's
  /// dependencies.
  final ContentModerationRepository moderationRepository;

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CreatePostSheet extends StatefulWidget {
  const _CreatePostSheet({required this.controller});
  final CommunityFeedController controller;

  @override
  State<_CreatePostSheet> createState() => _CreatePostSheetState();
}

class _CreatePostSheetState extends State<_CreatePostSheet> {
  final _textController = TextEditingController();
  PostVisibility _visibility = PostVisibility.friendsOnly;
  CommentsPolicy _commentsPolicy = CommentsPolicy.friendsOnly;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final draft = CreatePostDraft(
      message: _textController.text,
      visibility: _visibility,
      commentsPolicy: _commentsPolicy,
    );
    if (draft.validationError case final error?) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await widget.controller.createPost(draft);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Paylaşım gönderilemedi. Lütfen tekrar deneyin.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Center(
          child: Text(
            'Paylaşım oluştur',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _textController,
          maxLength: CommunityPost.maxMessageLength,
          minLines: 5,
          maxLines: 8,
          decoration: const InputDecoration(hintText: 'Ne düşünüyorsun?'),
        ),
        const Text(
          'Kimler görebilir?',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<PostVisibility>(
          segments: const [
            ButtonSegment(
              value: PostVisibility.friendsOnly,
              icon: Icon(Icons.people_outline_rounded),
              label: Text('Arkadaşlar'),
            ),
            ButtonSegment(
              value: PostVisibility.public,
              icon: Icon(Icons.public_rounded),
              label: Text('Herkese açık'),
            ),
          ],
          selected: {_visibility},
          onSelectionChanged: (value) =>
              setState(() => _visibility = value.first),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<CommentsPolicy>(
          value: _commentsPolicy,
          decoration: const InputDecoration(labelText: 'Yorumlar'),
          items: const [
            DropdownMenuItem(
              value: CommentsPolicy.everyone,
              child: Text('Herkes yorum yapabilir'),
            ),
            DropdownMenuItem(
              value: CommentsPolicy.friendsOnly,
              child: Text('Yalnız arkadaşlar'),
            ),
            DropdownMenuItem(
              value: CommentsPolicy.disabled,
              child: Text('Yorumlara kapalı'),
            ),
          ],
          onChanged: (value) => setState(() => _commentsPolicy = value!),
        ),
        const SizedBox(height: 18),
        AppButton(
          label: 'Paylaş',
          onPressed: _publish,
          isLoading: _isSubmitting,
          icon: Icons.send_rounded,
        ),
      ],
    ),
  );
}

class _CommunityScreenState extends State<CommunityScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.load();
    widget.storyController.load();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      if (widget.controller.isInitialLoading) {
        return const Column(
          children: [
            AppScreenHeader(
              title: 'Akış',
              subtitle: 'Arkadaşların ve topluluğun burada.',
            ),
            Expanded(child: AppLoadingView(label: 'Akış yükleniyor...')),
          ],
        );
      }
      if (widget.controller.state == PagedLoadState.failure &&
          widget.controller.items.isEmpty) {
        return Column(
          children: [
            const AppScreenHeader(
              title: 'Akış',
              subtitle: 'Arkadaşların ve topluluğun burada.',
            ),
            Expanded(
              child: AppErrorState(
                message: widget.controller.errorMessage ?? 'Akış yüklenemedi.',
                onRetry: widget.controller.load,
              ),
            ),
          ],
        );
      }
      return _Feed(
        controller: widget.controller,
        storyController: widget.storyController,
        commentsController: widget.commentsController,
        mediaUploadController: widget.mediaUploadController,
        specialRequestController: widget.specialRequestController,
        moderationRepository: widget.moderationRepository,
        promotionsController: widget.promotionsController,
        viewer: widget.viewer,
      );
    },
  );
}

class _Feed extends StatefulWidget {
  const _Feed({
    required this.controller,
    required this.storyController,
    required this.commentsController,
    required this.mediaUploadController,
    required this.specialRequestController,
    required this.moderationRepository,
    required this.promotionsController,
    this.viewer,
  });
  final CommunityFeedController controller;
  final StoryController storyController;
  final CommunityCommentsController commentsController;
  final MediaUploadController mediaUploadController;
  final CommunitySpecialRequestController specialRequestController;
  final ContentModerationRepository moderationRepository;
  final PromotionsController promotionsController;
  final AppUser? viewer;

  @override
  State<_Feed> createState() => _FeedState();
}

class _FeedState extends State<_Feed> {
  /// Üç sekme yan yana duran üç sayfa: parmakla sağa sola kaydırmak da
  /// sekmeye dokunmakla aynı şeyi yapıyor.
  final _pageController = PageController();
  _FeedFilter _filter = _FeedFilter.forYou;
  Future<void> _openComposer() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReferenceCreatePostSheet(
      controller: widget.controller,
      mediaUploadController: widget.mediaUploadController,
      viewer: widget.viewer,
    ),
  );

  /// Yorum tabakası artık paylaşılan bir bileşen; akışa özgü olan yalnızca
  /// erişim politikası, o da buradan geçiriliyor.
  void _openComments(CommunityPost post) => showAppBottomSheet(
    context: context,
    child: CommentsSheet(
      targetId: post.id,
      controller: widget.commentsController,
      moderationRepository: widget.moderationRepository,
      commentsEnabled: post.commentsPolicy != CommentsPolicy.disabled,
      onSubmit: (message, parentId) => widget.commentsController.addComment(
        post: post,
        viewerId: 'local-user',
        isFriend: true,
        message: message,
        parentId: parentId,
      ),
      onDelete: (comment) => widget.commentsController.deleteComment(
        comment: comment,
        post: post,
        viewerId: 'local-user',
      ),
      canDelete: (comment) => PostAccessPolicy.canDeleteComment(
        comment: comment,
        post: post,
        viewerId: 'local-user',
      ),
    ),
  );

  Future<void> _deletePost(CommunityPost post) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paylaşım silinsin mi?'),
        content: const Text(
          'Bu işlem paylaşımı Akıştan ve profilindeki Akışlar bölümünden kaldırır.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (shouldDelete == true) await widget.controller.deletePost(post.id);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _selectFilter(_FeedFilter value) {
    if (value == _filter) return;
    setState(() => _filter = value);
    if (!_pageController.hasClients) return;
    _pageController.animateToPage(
      value.index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  /// Sonsuz akış artık tek bir kaydırma denetleyicisine bağlı değil: üç
  /// sayfanın da kendi listesi var, o yüzden hangisi sona yaklaşırsa o
  /// bildirim üzerinden sonraki sayfa isteniyor.
  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis == Axis.vertical &&
        notification.metrics.extentAfter < 360) {
      widget.controller.loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const _ReferenceFeedHeader(),
      Expanded(
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          // Story rayı ve düzenleyici yukarı kaydırıldığında kayboluyor,
          // sekme şeridi ise tepede kalıyor: yatay kaydırırken hangi
          // sekmede olduğunu görmek gerekiyor.
          child: NestedScrollView(
            headerSliverBuilder: (context, _) => [
              SliverToBoxAdapter(
                child: _StoryRail(
                  controller: widget.storyController,
                  mediaUploadController: widget.mediaUploadController,
                  moderationRepository: widget.moderationRepository,
                  promotionsController: widget.promotionsController,
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: _ReferenceComposer(onTap: _openComposer),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _FeedFiltersHeader(
                  selected: _filter,
                  onSelected: _selectFilter,
                ),
              ),
            ],
            body: PageView(
              controller: _pageController,
              onPageChanged: (value) =>
                  setState(() => _filter = _FeedFilter.values[value]),
              children: [
                for (final filter in _FeedFilter.values) _feedPage(filter),
              ],
            ),
          ),
        ),
      ),
    ],
  );

  Widget _feedPage(_FeedFilter filter) {
    final posts = _postsFor(filter);
    return RefreshIndicator(
      onRefresh: widget.controller.refresh,
      child: ListView(
        key: PageStorageKey('feed-${filter.name}'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 12, bottom: 28),
        children: [
          if (posts.isEmpty && !widget.controller.isInitialLoading)
            _FeedEmptyState(filter: filter),
          for (final post in posts)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _PostCard(
                post: post,
                onToggleLike: widget.controller.toggleLike,
                specialRequestController: widget.specialRequestController,
                moderationRepository: widget.moderationRepository,
                onDelete: post.ownerId == 'local-user'
                    ? () => _deletePost(post)
                    : null,
                onOpenComments: () => _openComments(post),
              ),
            ),
          PagedListFooter<CommunityPost>(controller: widget.controller),
        ],
      ),
    );
  }

  List<CommunityPost> _postsFor(_FeedFilter filter) => switch (filter) {
    _FeedFilter.forYou => widget.controller.items,
    _FeedFilter.nearby =>
      widget.controller.items
          .where((post) => post.location.contains('New York'))
          .toList(growable: false),
    _FeedFilter.following =>
      widget.controller.items
          .where((post) => post.ownerId != 'local-user')
          .toList(growable: false),
  };
}

/// Sekme şeridini akışın tepesine çiviler.
class _FeedFiltersHeader extends SliverPersistentHeaderDelegate {
  const _FeedFiltersHeader({required this.selected, required this.onSelected});
  final _FeedFilter selected;
  final ValueChanged<_FeedFilter> onSelected;

  @override
  double get minExtent => 48;

  @override
  double get maxExtent => 48;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      _ReferenceFeedFilters(selected: selected, onSelected: onSelected);

  @override
  bool shouldRebuild(_FeedFiltersHeader oldDelegate) =>
      oldDelegate.selected != selected;
}

class _FeedEmptyState extends StatelessWidget {
  const _FeedEmptyState({required this.filter});
  final _FeedFilter filter;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 60, 28, 28),
    child: Column(
      children: [
        Icon(
          switch (filter) {
            _FeedFilter.forYou => Icons.auto_awesome_outlined,
            _FeedFilter.nearby => Icons.near_me_outlined,
            _FeedFilter.following => Icons.group_outlined,
          },
          size: 34,
          color: AppColors.textMuted,
        ),
        const SizedBox(height: 10),
        Text(
          switch (filter) {
            _FeedFilter.forYou => 'Akışta henüz paylaşım yok.',
            _FeedFilter.nearby => 'Yakınında henüz paylaşım yok.',
            _FeedFilter.following =>
              'Takip ettiklerinden henüz paylaşım yok.',
          },
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

enum _FeedFilter { forYou, nearby, following }

/// Direct Flutter translation of the reference HTML's feed header.
class _ReferenceFeedHeader extends StatelessWidget {
  const _ReferenceFeedHeader();

  @override
  Widget build(BuildContext context) => Container(
    height: 62,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Color(0xFFE9EAF0))),
    ),
    child: Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF6B54E8),
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(
            Icons.explore_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Topluluk Akışı',
                style: TextStyle(
                  fontSize: 17,
                  height: 1.05,
                  color: Color(0xFF17151C),
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 5),
              Row(
                children: [
                  Icon(Icons.circle, size: 7, color: Color(0xFF12A885)),
                  SizedBox(width: 5),
                  Text(
                    '28 yeni paylaşım',
                    style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFF777381),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ReferenceFeedFilters extends StatelessWidget {
  const _ReferenceFeedFilters({
    required this.selected,
    required this.onSelected,
  });
  final _FeedFilter selected;
  final ValueChanged<_FeedFilter> onSelected;

  @override
  Widget build(BuildContext context) => Container(
    height: 48,
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(0, 8, 8, 7),
    child: Row(
      children: [
        _ReferenceFilter(
          label: 'Senin İçin',
          active: selected == _FeedFilter.forYou,
          onTap: () => onSelected(_FeedFilter.forYou),
        ),
        const SizedBox(width: 7),
        _ReferenceFilter(
          label: 'Yakınındakiler',
          active: selected == _FeedFilter.nearby,
          onTap: () => onSelected(_FeedFilter.nearby),
        ),
        const SizedBox(width: 7),
        _ReferenceFilter(
          label: 'Takip ettiklerin',
          active: selected == _FeedFilter.following,
          onTap: () => onSelected(_FeedFilter.following),
        ),
        // Sağda bir filtre düğmesi vardı, hiçbir şey yapmıyordu; sekmeler
        // zaten filtrenin kendisi. Boş bir düğme, çalıştığını sanıp basan
        // üyeye yalan söylüyor.
      ],
    ),
  );
}

class _ReferenceFilter extends StatelessWidget {
  const _ReferenceFilter({
    required this.label,
    this.active = false,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Container(
      height: 29,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? const Color(0xFF6B54E8) : const Color(0xFFF1F1F4),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: active ? Colors.white : const Color(0xFF706C78),
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _StoryRail extends StatelessWidget {
  const _StoryRail({
    required this.controller,
    required this.mediaUploadController,
    required this.moderationRepository,
    required this.promotionsController,
  });
  final StoryController controller;
  final MediaUploadController mediaUploadController;
  final ContentModerationRepository moderationRepository;
  final PromotionsController promotionsController;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final railItems = controller.railItems;
      return SizedBox(
        height: 106,
        child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        scrollDirection: Axis.horizontal,
        itemCount: railItems.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 9),
        itemBuilder: (_, index) {
          if (index == 0) {
            return InkWell(
              // Duzenleyici kendi koyu yuzeyini ciziyor; buradaki saydam arka
              // plan yalnizca o yuzeyin ust kose yuvarlaklarini goruniyor
              // kiliyor. Perde de koyulasiyor ki arkadaki akis dikkat
              // dagitmasin.
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                backgroundColor: Colors.transparent,
                barrierColor: const Color(0xCC000000),
                builder: (_) => StoryComposerSheet(
                  storyController: controller,
                  mediaUploadController: mediaUploadController,
                  promotionsController: promotionsController,
                ),
              ),
              borderRadius: BorderRadius.circular(11),
              child: Container(
                width: 74,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDEAFF),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: const Color(0xFFD8D2FF)),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Color(0xFF6B54E8),
                      child: Icon(Icons.add_rounded, color: Colors.white),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Story Ekle',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF4937BC),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          index -= 1;
          final item = railItems[index];
          if (index >= railItems.length - 3) controller.loadMore();
          return GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => StoryViewerScreen(
                  controller: controller,
                  initialStoryId: item.id,
                  moderationRepository: moderationRepository,
                ),
              ),
            ),
            child: SizedBox(
              width: 74,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AppRemoteImage(
                      imageUrl: item.media.thumbnailUrl ?? item.media.url,
                      semanticLabel: '${item.authorName} hikayesi',
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x11000000), Color(0xB9000000)],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 7,
                      top: 7,
                      child: CircleAvatar(
                        radius: 11,
                        backgroundColor: Colors.white,
                        child: Text(
                          item.authorName.isEmpty
                              ? '?'
                              : item.authorName.substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF6B54E8),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 9,
                      child: Text(
                        item.authorName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      );
    },
  );
}

class _ReferenceCreatePostSheet extends StatefulWidget {
  const _ReferenceCreatePostSheet({
    required this.controller,
    required this.mediaUploadController,
    this.viewer,
  });
  final CommunityFeedController controller;
  final MediaUploadController mediaUploadController;
  final AppUser? viewer;
  @override
  State<_ReferenceCreatePostSheet> createState() =>
      _ReferenceCreatePostSheetState();
}

class _ReferenceCreatePostSheetState extends State<_ReferenceCreatePostSheet> {
  final _text = TextEditingController();
  bool _sending = false;
  PostVisibility _visibility = PostVisibility.public;
  bool _hasPoll = false;
  String? _location;
  String? _price;
  String? _tag;
  final _picker = ImagePicker();
  final List<XFile> _photos = [];
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final extras = [
      if (_hasPoll) 'Anket',
      if (_location != null) _location!,
      if (_price != null) 'Fiyat: $_price',
      if (_tag != null) '#$_tag',
    ];
    final draft = CreatePostDraft(
      message: [
        _text.text.trim(),
        ...extras.map((item) => '[$item]'),
      ].where((item) => item.isNotEmpty).join(' '),
      visibility: _visibility,
      commentsPolicy: CommentsPolicy.friendsOnly,
      media: widget.mediaUploadController.readyMedia,
    );
    if (draft.validationError case final error?) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.controller.createPost(draft);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Paylaşım gönderilemedi. Lütfen tekrar deneyin.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickPhotos() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galeriden seç'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Kamerayı aç'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    if (source == ImageSource.camera) {
      await _capturePhoto();
      return;
    }
    final files = await _picker.pickMultiImage(imageQuality: 85);
    if (files.isEmpty || !mounted) return;
    final selected = files.take(10 - _photos.length).toList(growable: false);
    setState(() => _photos.addAll(selected));
    for (final file in selected) {
      final size = await file.length();
      await widget.mediaUploadController.upload(
        MediaUploadRequest(
          localUri: file.path,
          media: PostMediaUpload(
            localId: file.name,
            type: PostMediaType.image,
            fileName: file.name,
            mimeType: 'image/jpeg',
            sizeBytes: size,
          ),
        ),
      );
    }
  }

  Future<void> _capturePhoto() async {
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (photo == null || !mounted) return;
      final size = await photo.length();
      setState(() => _photos.add(photo));
      await widget.mediaUploadController.upload(
        MediaUploadRequest(
          localUri: photo.path,
          media: PostMediaUpload(
            localId: photo.name,
            type: PostMediaType.image,
            fileName: photo.name,
            mimeType: 'image/jpeg',
            sizeBytes: size,
          ),
        ),
      );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kamera açılamadı. İzinleri kontrol edin.'),
          ),
        );
    }
  }

  Future<void> _useCurrentLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied)
        permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever)
        throw StateError('Konum izni verilmedi.');
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      );
      if (!mounted) return;
      setState(
        () => _location =
            'Yaklaşık konum · ${position.latitude.toStringAsFixed(2)}, ${position.longitude.toStringAsFixed(2)}',
      );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Konum alınamadı. Konumu yazarak ekleyebilirsiniz.'),
          ),
        );
    }
  }

  Future<void> _setTextValue({
    required String title,
    required void Function(String value) onSaved,
  }) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
          decoration: const InputDecoration(hintText: 'Bilgiyi girin'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && value.trim().isNotEmpty && mounted)
      setState(() => onSaved(value.trim()));
  }

  @override
  Widget build(BuildContext context) => Container(
    height: MediaQuery.sizeOf(context).height * .91,
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFF3F6FA),
              ),
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
            const Expanded(
              child: Text(
                'Yeni Paylaşım Oluştur',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
            FilledButton(
              onPressed: _sending ? null : _publish,
              style: FilledButton.styleFrom(
                minimumSize: const Size(70, 36),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                backgroundColor: const Color(0xFF5D43D6),
              ),
              child: const Text(
                'Paylaş',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFFEDEAFF),
              child: widget.viewer == null
                  ? const Icon(Icons.person_rounded, color: Color(0xFF705BE9))
                  : Text(
                      widget.viewer!.initials,
                      style: const TextStyle(
                        color: Color(0xFF705BE9),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            // The member's own name and audience. There is no handle in the
            // domain, so the second line says where the post goes instead of
            // showing a username nobody actually has.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.viewer?.fullName ?? 'Sen',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    _visibility == PostVisibility.public
                        ? 'Herkese açık'
                        : 'Sadece arkadaşlar',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF8B9AB3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            children: [
              Icon(Icons.public, size: 15, color: Color(0xFF00A884)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Herkese Açık',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4B5563),
                  ),
                ),
              ),
              Icon(Icons.expand_more_rounded, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: TextField(
            controller: _text,
            maxLength: CommunityPost.maxMessageLength,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration: const InputDecoration(
              counterText: '',
              hintText:
                  'Toplulukla ne paylaşmak istersin? Detaylıca yazabilirsin...',
              hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
            ),
          ),
        ),
        if (_photos.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(
              spacing: 6,
              children: [
                for (final photo in _photos)
                  InputChip(
                    label: Text(photo.name, overflow: TextOverflow.ellipsis),
                    onDeleted: () => setState(() {
                      _photos.remove(photo);
                      widget.mediaUploadController.remove(photo.name);
                    }),
                  ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GÖNDERİNE EKLE',
                style: TextStyle(
                  fontSize: 10,
                  color: Color(0xFF8B9AB3),
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 9),
              Row(
                children: [
                  _SheetAction(
                    Icons.image_outlined,
                    'Fotoğraf',
                    Color(0xFF10B981),
                    onTap: _pickPhotos,
                  ),
                  SizedBox(width: 8),
                  _SheetAction(
                    Icons.location_on_outlined,
                    'Konum',
                    Color(0xFFF05269),
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      builder: (sheetContext) => SafeArea(
                        child: Wrap(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.my_location_outlined),
                              title: const Text(
                                'Mevcut yaklaşık konumu kullan',
                              ),
                              onTap: () {
                                Navigator.pop(sheetContext);
                                _useCurrentLocation();
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.search_rounded),
                              title: const Text('Konumu yazarak ekle'),
                              onTap: () {
                                Navigator.pop(sheetContext);
                                _setTextValue(
                                  title: 'Konum ekle',
                                  onSaved: (value) => _location = value,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  _SheetAction(
                    Icons.bar_chart_rounded,
                    'Anket',
                    const Color(0xFF5D43D6),
                    onTap: () => setState(() => _hasPoll = !_hasPoll),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  _SheetAction(
                    Icons.sell_outlined,
                    'Fiyat Ekle',
                    Color(0xFF5D43D6),
                    onTap: () => _setTextValue(
                      title: 'Fiyat ekle',
                      onSaved: (value) => _price = value,
                    ),
                  ),
                  SizedBox(width: 8),
                  _SheetAction(
                    Icons.tag_rounded,
                    'Etiket',
                    Color(0xFF5D43D6),
                    onTap: () => _setTextValue(
                      title: 'Etiket ekle',
                      onSaved: (value) => _tag = value.replaceAll('#', ''),
                    ),
                  ),
                  Spacer(),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SheetAction extends StatelessWidget {
  const _SheetAction(this.icon, this.label, this.color, {this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

class _ReferenceComposerLegacy extends StatelessWidget {
  const _ReferenceComposerLegacy({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 76,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08000000),
              blurRadius: 5,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFF0EEFF),
              ),
              child: const Icon(
                Icons.person_rounded,
                size: 22,
                color: Color(0xFF705BE9),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Ne düşünüyorsun?',
                style: TextStyle(
                  color: Color(0xFF9B98A8),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(
              Icons.image_outlined,
              color: Color(0xFF705BE9),
              size: 22,
            ),
            const SizedBox(width: 13),
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 17),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF6B54E8),
                borderRadius: BorderRadius.circular(23),
              ),
              child: const Text(
                'Paylaş',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ReferenceComposer extends StatelessWidget {
  const _ReferenceComposer({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 112,
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 9),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE4E6ED)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 18,
                  backgroundColor: Color(0xFFEDEAFF),
                  child: Icon(
                    Icons.person_rounded,
                    color: Color(0xFF705BE9),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Topluluğa bir şey sor veya paylaş...',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: Color(0xFF8893A9)),
                  ),
                ),
                const Icon(
                  Icons.edit_outlined,
                  color: Color(0xFF6355D8),
                  size: 19,
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: Color(0xFFE8EAF0)),
            const SizedBox(height: 8),
            const Row(
              children: [
                _ComposerAction(
                  icon: Icons.help_outline_rounded,
                  label: 'Soru Sor',
                  color: Color(0xFF5D55DB),
                ),
                SizedBox(width: 7),
                _ComposerAction(
                  icon: Icons.storefront_outlined,
                  label: 'Çarşı İlanı',
                  color: Color(0xFF5D55DB),
                ),
                SizedBox(width: 7),
                _ComposerAction(
                  icon: Icons.bar_chart_rounded,
                  label: 'Anket',
                  color: Color(0xFFF59E0B),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _ComposerAction extends StatelessWidget {
  const _ComposerAction({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color == const Color(0xFFF59E0B)
            ? const Color(0xFFFFFBEB)
            : const Color(0xFFF5F4FF),
        border: Border.all(color: color.withValues(alpha: .25)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ),
  );
}

class _FeedHeader extends StatelessWidget {
  const _FeedHeader({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 11),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Color(0xFFE8EAF0))),
    ),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(11),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: .25),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.explore_rounded,
            size: 19,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Topluluk AkÄ±ÅŸÄ±',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.circle, size: 7, color: AppColors.accentEmerald),
                  SizedBox(width: 5),
                  Text(
                    '28 yeni paylaÅŸÄ±m',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onCreate,
          tooltip: 'PaylaÅŸÄ±m oluÅŸtur',
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFFF0EEFF),
            foregroundColor: AppColors.primary,
          ),
          icon: const Icon(Icons.add_rounded, size: 19),
        ),
      ],
    ),
  );
}

class _PublicStories extends StatelessWidget {
  const _PublicStories();

  @override
  Widget build(BuildContext context) {
    const entries = [
      (
        'Elif',
        'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=240&q=80',
      ),
      (
        'Mert',
        'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&w=240&q=80',
      ),
      (
        'Zeynep',
        'https://images.unsplash.com/photo-1516280440614-37939bbacd81?auto=format&fit=crop&w=240&q=80',
      ),
      (
        'Can',
        'https://images.unsplash.com/photo-1540189549336-e6e99c3679fe?auto=format&fit=crop&w=240&q=80',
      ),
    ];
    return SizedBox(
      height: 132,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        scrollDirection: Axis.horizontal,
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, index) {
          final item = entries[index];
          return SizedBox(
            width: 74,
            child: Column(
              children: [
                Container(
                  height: 106,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: .4),
                      width: 2,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: AppRemoteImage(
                          imageUrl: item.$2,
                          semanticLabel: '${item.$1} hikayesi',
                        ),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x12000000), Color(0x77000000)],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 7,
                        top: 7,
                        child: CircleAvatar(
                          radius: 11,
                          backgroundColor: Colors.white,
                          child: Text(
                            item.$1.substring(0, 1),
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 7,
                        child: Text(
                          item.$1,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OpenComposerCard extends StatelessWidget {
  const _OpenComposerCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x100E0B18),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 19,
            backgroundColor: Color(0xFFEEF2FF),
            child: Icon(Icons.person_rounded, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Ne düşünüyorsun?',
              style: TextStyle(fontSize: 16, color: Color(0xFF9CA3AF)),
            ),
          ),
          const Icon(Icons.image_outlined, color: AppColors.primary, size: 21),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.all(Radius.circular(22)),
            ),
            child: const Text(
              'Paylaş',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _InlineComposer extends StatefulWidget {
  const _InlineComposer({
    required this.controller,
    required this.mediaUploadController,
    required this.expanded,
    required this.onExpand,
    required this.onCollapse,
  });
  final CommunityFeedController controller;
  final MediaUploadController mediaUploadController;
  final bool expanded;
  final VoidCallback onExpand;
  final VoidCallback onCollapse;

  @override
  State<_InlineComposer> createState() => _InlineComposerState();
}

class _InlineComposerState extends State<_InlineComposer> {
  final _text = TextEditingController();
  PostVisibility _visibility = PostVisibility.friendsOnly;
  CommentsPolicy _comments = CommentsPolicy.friendsOnly;
  final List<TaggedUser> _taggedUsers = [];
  final List<XFile> _pickedMedia = [];
  final Set<String> _videoMediaIds = {};
  final _picker = ImagePicker();
  PostLocation? _location;
  bool _isSending = false;
  bool _hasContent = false;
  String? _mentionQuery;
  bool _isChoosingLocation = false;
  final _locationText = TextEditingController();
  static const _mentionCandidates = [
    TaggedUser(id: 'friend-elif', displayName: 'Elif Demir'),
    TaggedUser(id: 'friend-mert', displayName: 'Mert Kaya'),
    TaggedUser(id: 'friend-zeynep', displayName: 'Zeynep Arslan'),
  ];

  @override
  void initState() {
    super.initState();
    _text.addListener(_onTextChanged);
    widget.mediaUploadController.addListener(_onUploadChanged);
  }

  void _onUploadChanged() {
    if (mounted) setState(() {});
  }

  @override
  void _onTextChanged() {
    final value = _text.value;
    final prefix = value.text.substring(
      0,
      value.selection.baseOffset.clamp(0, value.text.length),
    );
    final match = RegExp(r'@([A-Za-z0-9_çÇğĞıİöÖşŞüÜ]*)$').firstMatch(prefix);
    setState(() {
      _hasContent = value.text.trim().isNotEmpty;
      _mentionQuery = match?.group(1);
    });
  }

  void _insertMention() {
    final selection = _text.selection;
    final position = selection.baseOffset < 0
        ? _text.text.length
        : selection.baseOffset;
    _text.value = _text.value.copyWith(
      text:
          '${_text.text.substring(0, position)}@${_text.text.substring(position)}',
      selection: TextSelection.collapsed(offset: position + 1),
    );
  }

  void _selectMention(TaggedUser user) {
    final value = _text.value;
    final prefix = value.text.substring(
      0,
      value.selection.baseOffset.clamp(0, value.text.length),
    );
    final start = prefix.lastIndexOf('@');
    _text.value = value.copyWith(
      text:
          '${value.text.substring(0, start)}@${user.displayName} ${value.text.substring(value.selection.baseOffset)}',
      selection: TextSelection.collapsed(
        offset: start + user.displayName.length + 2,
      ),
    );
    setState(() {
      if (!_taggedUsers.any((item) => item.id == user.id))
        _taggedUsers.add(user);
      _mentionQuery = null;
    });
  }

  void dispose() {
    widget.mediaUploadController.removeListener(_onUploadChanged);
    _text.removeListener(_onTextChanged);
    _text.dispose();
    _locationText.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final draft = CreatePostDraft(
      message: _text.text,
      visibility: _visibility,
      commentsPolicy: _comments,
      taggedUsers: _taggedUsers,
      location: _location,
      media: widget.mediaUploadController.readyMedia,
    );
    if (draft.validationError case final error?) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _isSending = true);
    try {
      await widget.controller.createPost(draft);
      _text.clear();
      _pickedMedia.clear();
      _videoMediaIds.clear();
      widget.mediaUploadController.clear();
      widget.onCollapse();
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _pickMedia() async {
    final isVideo = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Fotoğraf seç'),
              onTap: () => Navigator.pop(context, false),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Video seç'),
              onTap: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
    if (isVideo == null || !mounted) return;
    if (isVideo) {
      if (_videoMediaIds.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bir paylaşımda yalnızca bir video ekleyebilirsin.'),
          ),
        );
        return;
      }
      final video = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 2),
      );
      if (mounted && video != null) {
        _pickedMedia.add(video);
        _videoMediaIds.add(video.name);
        await _upload(video, PostMediaType.video);
      }
      return;
    }
    final images = await _picker.pickMultiImage(imageQuality: 85);
    if (mounted && images.isNotEmpty) {
      final selected = images
          .take(10 - _pickedMedia.length)
          .toList(growable: false);
      _pickedMedia.addAll(selected);
      for (final image in selected) {
        await _upload(image, PostMediaType.image);
      }
    }
  }

  Future<void> _upload(XFile file, PostMediaType type) async {
    final byteCount = await file.length();
    final mimeType = type == PostMediaType.video ? 'video/mp4' : 'image/jpeg';
    final request = MediaUploadRequest(
      localUri: file.path,
      media: PostMediaUpload(
        localId: file.name,
        type: type,
        fileName: file.name,
        mimeType: mimeType,
        sizeBytes: byteCount,
      ),
    );
    await widget.mediaUploadController.upload(request);
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: const [
        BoxShadow(
          color: Color(0x120E0B18),
          blurRadius: 18,
          offset: Offset(0, 7),
        ),
      ],
    ),
    child: Column(
      children: [
        Row(
          children: [
            const CircleAvatar(
              radius: 19,
              backgroundColor: Color(0xFFE9E5F7),
              child: Icon(Icons.person_rounded, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: widget.expanded
                  ? TextField(
                      controller: _text,
                      autofocus: true,
                      minLines: 2,
                      maxLines: 5,
                      maxLength: CommunityPost.maxMessageLength,
                      style: const TextStyle(
                        fontSize: 17,
                        height: 1.45,
                        color: AppColors.textPrimary,
                      ),
                      decoration: const InputDecoration(
                        counterText: '',
                        hintText: 'Ne düşünüyorsun?',
                        hintStyle: TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 17,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    )
                  : InkWell(
                      onTap: widget.onExpand,
                      borderRadius: BorderRadius.circular(22),
                      child: Container(
                        height: 40,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: const BoxDecoration(),
                        child: const Text(
                          'Ne düşünüyorsun?',
                          style: TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
            ),
            if (!widget.expanded) ...[
              const SizedBox(width: 6),
              IconButton(
                onPressed: widget.onExpand,
                icon: const Icon(
                  Icons.image_outlined,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 2),
              _shareButton(onPressed: widget.onExpand, enabled: true),
            ],
          ],
        ),
        if (widget.expanded) ...[
          const Divider(height: 22),
          if (_mentionQuery != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    for (final user in _mentionCandidates.where(
                      (user) => user.displayName.toLowerCase().contains(
                        _mentionQuery!.toLowerCase(),
                      ),
                    ))
                      ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: const Color(0xFFEEF2FF),
                          child: Text(
                            user.displayName.substring(0, 1),
                            style: const TextStyle(color: AppColors.primary),
                          ),
                        ),
                        title: Text(
                          user.displayName,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onTap: () => _selectMention(user),
                      ),
                  ],
                ),
              ),
            ),
          if (_isChoosingLocation)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: _locationText,
                autofocus: true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  hintText: 'Mekân veya adres ara',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.my_location_outlined, size: 18),
                    onPressed: () => setState(() {
                      _location = const PostLocation(
                        placeId: 'current-location',
                        displayName: 'Mevcut konum',
                      );
                      _isChoosingLocation = false;
                    }),
                  ),
                ),
                onSubmitted: (value) => setState(() {
                  if (value.trim().isNotEmpty)
                    _location = PostLocation(
                      placeId: value.trim().toLowerCase().replaceAll(' ', '-'),
                      displayName: value.trim(),
                    );
                  _isChoosingLocation = false;
                }),
              ),
            ),
          if (_location != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (_location != null)
                    InputChip(
                      backgroundColor: const Color(0xFFEEF2FF),
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      avatar: const Icon(Icons.location_on_outlined, size: 16),
                      label: Text(_location!.displayName),
                      onDeleted: () => setState(() => _location = null),
                    ),
                ],
              ),
            ),
          if (_location != null) const SizedBox(height: 8),
          if (_pickedMedia.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 6,
                children: [for (final media in _pickedMedia) _mediaChip(media)],
              ),
            ),
          if (_pickedMedia.isNotEmpty) const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                onPressed: _pickedMedia.length >= 10 ? null : _pickMedia,
                icon: const Icon(
                  Icons.image_outlined,
                  color: Color(0xFF6B7280),
                ),
                tooltip: 'Görsel veya video ekle',
              ),
              IconButton(
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                onPressed: _insertMention,
                icon: const Icon(
                  Icons.alternate_email_rounded,
                  color: Color(0xFF6B7280),
                ),
                tooltip: 'Kişi etiketle',
              ),
              IconButton(
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    setState(() => _isChoosingLocation = !_isChoosingLocation),
                icon: const Icon(
                  Icons.location_on_outlined,
                  color: Color(0xFF6B7280),
                ),
                tooltip: 'Konum ekle',
              ),
              const Spacer(),
              PopupMenuButton<PostVisibility>(
                tooltip: 'Görünürlük',
                iconSize: 20,
                padding: EdgeInsets.zero,
                icon: Icon(
                  _visibility == PostVisibility.public
                      ? Icons.public_rounded
                      : Icons.people_outline_rounded,
                  color: const Color(0xFF6B7280),
                ),
                onSelected: (value) => setState(() => _visibility = value),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: PostVisibility.friendsOnly,
                    child: Text('Sadece arkadaşlar'),
                  ),
                  PopupMenuItem(
                    value: PostVisibility.public,
                    child: Text('Herkese açık'),
                  ),
                ],
              ),
              PopupMenuButton<CommentsPolicy>(
                tooltip: 'Yorum ayarı',
                iconSize: 20,
                padding: EdgeInsets.zero,
                icon: Icon(
                  _comments == CommentsPolicy.disabled
                      ? Icons.comments_disabled_outlined
                      : Icons.mode_comment_outlined,
                  color: const Color(0xFF6B7280),
                ),
                onSelected: (value) => setState(() => _comments = value),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: CommentsPolicy.everyone,
                    child: Text('Herkes yorum yapabilir'),
                  ),
                  PopupMenuItem(
                    value: CommentsPolicy.friendsOnly,
                    child: Text('Arkadaşlar yorum yapabilir'),
                  ),
                  PopupMenuItem(
                    value: CommentsPolicy.disabled,
                    child: Text('Yorumları kapat'),
                  ),
                ],
              ),
              _shareButton(
                onPressed:
                    _isSending ||
                        widget.mediaUploadController.hasPendingUploads ||
                        !_hasContent && _pickedMedia.isEmpty
                    ? null
                    : _send,
                enabled:
                    (_hasContent || _pickedMedia.isNotEmpty) &&
                    !widget.mediaUploadController.hasPendingUploads,
              ),
            ],
          ),
        ],
      ],
    ),
  );

  Widget _mediaChip(XFile media) {
    final progress = widget.mediaUploadController.progressById[media.name];
    final retryable =
        progress?.status == MediaUploadStatus.failed ||
        progress?.status == MediaUploadStatus.rejected;
    final label = retryable
        ? '${media.name} · Tekrar dene'
        : progress?.status == MediaUploadStatus.uploading
        ? '${media.name} ${((progress?.fraction ?? 0) * 100).round()}%'
        : media.name;
    return InputChip(
      backgroundColor: const Color(0xFFEEF2FF),
      side: BorderSide.none,
      label: Text(label, overflow: TextOverflow.ellipsis),
      onPressed: retryable
          ? () => widget.mediaUploadController.retry(media.name)
          : null,
      onDeleted: () => setState(() {
        _pickedMedia.remove(media);
        _videoMediaIds.remove(media.name);
        widget.mediaUploadController.remove(media.name);
      }),
    );
  }

  Widget _shareButton({
    required VoidCallback? onPressed,
    required bool enabled,
  }) => FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: enabled
          ? AppColors.primary
          : AppColors.primary.withValues(alpha: .24),
      foregroundColor: Colors.white,
      minimumSize: const Size(76, 40),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      shape: const StadiumBorder(),
      elevation: 0,
    ),
    child: _isSending
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        : const Text('Paylaş', style: TextStyle(fontWeight: FontWeight.w800)),
  );
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.onToggleLike,
    required this.onOpenComments,
    required this.specialRequestController,
    required this.moderationRepository,
    this.onDelete,
  });
  final CommunityPost post;
  final ValueChanged<String> onToggleLike;
  final VoidCallback onOpenComments;
  final CommunitySpecialRequestController specialRequestController;
  final ContentModerationRepository moderationRepository;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE5E7EB)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x090F172A),
          blurRadius: 8,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.primary.withValues(alpha: .16),
              child: Text(
                post.authorName.substring(0, 1),
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
                    post.authorName,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${post.location} · ${post.timeLabel}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(
                Icons.more_horiz_rounded,
                color: AppColors.textMuted,
              ),
              onSelected: (value) {
                if (value == 'delete') onDelete?.call();
                // Was a snackbar that promised a review nobody was doing. It
                // now files a real report against the post id, which is what
                // the moderation queue and the 24-hour deadline hang off.
                if (value == 'report')
                  showContentReportSheet(
                    context,
                    repository: moderationRepository,
                    targetType: ContentReportTarget.post,
                    targetId: post.id,
                    subjectLabel: post.authorName,
                  );
              },
              itemBuilder: (_) => [
                if (onDelete != null)
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Paylaşımı sil'),
                  ),
                // Only offered on someone else's post: the service rejects a
                // self-report, so showing it there would be a dead end.
                if (onDelete == null)
                  const PopupMenuItem(
                    value: 'report',
                    child: Text('Şikâyet et'),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (post.purpose != CommunityPostPurpose.standard)
          _PostPurposeBanner(
            purpose: post.purpose,
            traveler: post.travelerMatch,
          ),
        if (post.purpose != CommunityPostPurpose.standard)
          const SizedBox(height: 10),
        if (post.purpose == CommunityPostPurpose.imeceHelp ||
            post.purpose == CommunityPostPurpose.travelerMatch)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                backgroundColor: Colors.transparent,
                builder: (_) => SpecialPostRequestSheet(
                  post: post,
                  controller: specialRequestController,
                ),
              ),
              icon: Icon(
                post.purpose == CommunityPostPurpose.travelerMatch
                    ? Icons.luggage_outlined
                    : Icons.volunteer_activism_outlined,
                size: 18,
              ),
              label: Text(
                post.purpose == CommunityPostPurpose.travelerMatch
                    ? 'Eşleşme isteği gönder'
                    : 'Destek teklif et',
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
          ),
        _ExpandablePostText(message: post.message),
        if (post.media.isNotEmpty) ...[
          const SizedBox(height: 12),
          _PostMediaStrip(media: post.media),
        ],
        if (post.postLocation != null) ...[
          const SizedBox(height: 10),
          Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF5F7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on_rounded, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    post.postLocation!.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const Icon(Icons.map_outlined, color: AppColors.textMuted),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        const Divider(height: 1, color: Color(0xFFE8EAF0)),
        const SizedBox(height: 3),
        Row(
          children: [
            TextButton.icon(
              onPressed: () => onToggleLike(post.id),
              icon: Icon(
                post.isLiked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: 18,
                color: post.isLiked
                    ? AppColors.accentRose
                    : AppColors.textSecondary,
              ),
              label: Text(
                '${post.likes}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
            ),
            const SizedBox(width: 6),
            TextButton.icon(
              onPressed: onOpenComments,
              icon: const Icon(
                Icons.chat_bubble_outline_rounded,
                color: AppColors.textSecondary,
                size: 18,
              ),
              label: Text(
                '${post.comments}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
            ),
            const Spacer(),
            IconButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('PaylaÅŸÄ±m baÄŸlantÄ±sÄ± kopyalandÄ±.'),
                ),
              ),
              tooltip: 'PaylaÅŸ',
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.reply_rounded,
                size: 19,
                color: AppColors.textSecondary,
              ),
            ),
            IconButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('PaylaÅŸÄ±m kaydedildi.')),
              ),
              tooltip: 'Kaydet',
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.bookmark_border_rounded,
                size: 19,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _PostPurposeBanner extends StatelessWidget {
  const _PostPurposeBanner({required this.purpose, this.traveler});
  final CommunityPostPurpose purpose;
  final TravelerMatchDetails? traveler;

  @override
  Widget build(BuildContext context) {
    final data = switch (purpose) {
      CommunityPostPurpose.imeceHelp => (
        const Color(0xFFFFF3D6),
        Icons.volunteer_activism_outlined,
        'İmece / Yardım',
        'Yakınındaki topluluktan destek istiyor',
      ),
      CommunityPostPurpose.travelerMatch => (
        const Color(0xFFE9F6FF),
        Icons.luggage_outlined,
        'Bavulda Yer Var',
        traveler == null
            ? 'Yolculuk paylaşımı'
            : '${traveler!.from} → ${traveler!.to}',
      ),
      CommunityPostPurpose.anonymousAdvice => (
        const Color(0xFFF1ECFF),
        Icons.visibility_off_outlined,
        'Anonim Dertleşme',
        'Güvenli ve isimsiz tavsiye paylaşımı',
      ),
      CommunityPostPurpose.standard => (
        Colors.transparent,
        Icons.article_outlined,
        '',
        '',
      ),
    };
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: data.$1,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(data.$2, size: 19, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.$3,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                Text(
                  data.$4,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpandablePostText extends StatefulWidget {
  const _ExpandablePostText({required this.message});
  final String message;

  @override
  State<_ExpandablePostText> createState() => _ExpandablePostTextState();
}

class _ExpandablePostTextState extends State<_ExpandablePostText> {
  static const _previewLength = 230;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isLong = widget.message.runes.length > _previewLength;
    final preview = isLong && !_expanded
        ? String.fromCharCodes(
            widget.message.runes.take(_previewLength),
          ).trimRight()
        : widget.message;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          preview,
          style: const TextStyle(
            color: AppColors.textPrimary,
            height: 1.5,
            fontSize: 14,
          ),
        ),
        if (isLong)
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.only(top: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              _expanded ? 'Daha az göster' : '… devamını oku',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
      ],
    );
  }
}

/// Paylaşımın fotoğraflarını, kaçı varsa o kadarını gösterir.
class _PostMediaStrip extends StatefulWidget {
  const _PostMediaStrip({required this.media});
  final List<PostMedia> media;

  @override
  State<_PostMediaStrip> createState() => _PostMediaStripState();
}

class _PostMediaStripState extends State<_PostMediaStrip> {
  /// `keepPage: false`: her paylaşım ilk fotoğrafından açılmalı. Varsayılan
  /// davranışta sayfa numarası akışın sayfa deposuna yazılıyor ve kart yeniden
  /// kurulduğunda şerit ortasından, hatta sonuncudan başlıyordu.
  final _controller = PageController(keepPage: false);
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 1.35,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: media.length,
              onPageChanged: (value) => setState(() => _index = value),
              itemBuilder: (_, index) => _PostMediaFrame(media: media[index]),
            ),
            if (media.length > 1) ...[
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xAA000000),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_index + 1}/${media.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var dot = 0; dot < media.length; dot++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.symmetric(horizontal: 2.5),
                        width: dot == _index ? 7 : 5,
                        height: dot == _index ? 7 : 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: dot == _index
                              ? Colors.white
                              : Colors.white.withValues(alpha: .5),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Tek bir kare. Galeriden yeni seçilmiş bir fotoğrafın elimizde yalnızca
/// cihazdaki yolu oluyor; eskiden burası adresi http ile başlamayan her şeyi
/// "3 medya eklendi" yazısına çevirdiği için paylaşımın görseli hiç
/// görünmüyordu. Artık çözümlemeyi [appImageProvider] yapıyor, yer tutucu da
/// yalnızca gerçekten çizilemeyen kare için kalıyor.
class _PostMediaFrame extends StatelessWidget {
  const _PostMediaFrame({required this.media});
  final PostMedia media;

  @override
  Widget build(BuildContext context) {
    final bytes = media.previewBytes;
    final source = media.thumbnailUrl ?? media.url;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (bytes != null)
          Image.memory(bytes, fit: BoxFit.cover)
        else if (appImageProvider(source) != null)
          AppRemoteImage(
            imageUrl: source,
            semanticLabel: 'Paylaşım medyası',
          )
        else
          const _PendingMedia(),
        if (media.type == PostMediaType.video)
          const Center(
            child: CircleAvatar(
              radius: 24,
              backgroundColor: Color(0xAA000000),
              child: Icon(Icons.play_arrow_rounded, color: Colors.white),
            ),
          ),
      ],
    );
  }
}

class _PendingMedia extends StatelessWidget {
  const _PendingMedia();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Color(0xFFF1EFFF),
    child: Center(
      child: Icon(Icons.image_outlined, color: AppColors.primary, size: 30),
    ),
  );
}
