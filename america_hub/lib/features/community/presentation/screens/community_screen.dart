import 'dart:async';

import 'package:flutter/material.dart';

import '../../../auth/domain/entities/app_user.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_image_source.dart';
import '../../../../core/widgets/app_remote_image.dart';
import '../../../../core/widgets/app_screen_header.dart';
import '../../../../core/widgets/app_state_views.dart';
import '../../../../core/widgets/paged_list_footer.dart';
import '../../application/community_feed_controller.dart';
import '../../application/story_controller.dart';
import '../../application/community_comments_controller.dart';
import '../../application/media_upload_controller.dart';
import '../../application/community_special_request_controller.dart';
// Haber kartının üstündeki kategori etiketi haberin kendi sözlüğünden okunuyor;
// akış, "gundem" kodunu kendi başına "Gündem" diye çevirmeye kalkmıyor.
import '../../../news/domain/entities/news_article.dart';
import '../../../profile/application/friendship_controller.dart';
import '../../../profile/domain/entities/friendship.dart';
import '../../../promotions/application/promotions_controller.dart';
import '../widgets/post_requests_sheet.dart';
import '../widgets/special_post_request_sheet.dart';
import '../../domain/repositories/content_moderation_repository.dart';
import '../widgets/content_report_sheet.dart';
import '../widgets/post_comments.dart';
import '../widgets/story_composer_sheet.dart';
import 'post_composer_screen.dart';
import 'story_viewer_screen.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/entities/feed_extensions.dart';
import '../../domain/entities/content_report.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({
    super.key,
    required this.controller,
    required this.storyController,
    required this.commentsController,
    required this.mediaUploadController,
    required this.specialRequestController,
    required this.friendshipController,
    required this.moderationRepository,
    required this.promotionsController,
    this.viewer,
    this.viewerRegion,
    this.onOpenArticle,
  });
  final CommunityFeedController controller;
  final StoryController storyController;
  final CommunityCommentsController commentsController;
  final MediaUploadController mediaUploadController;
  final CommunitySpecialRequestController specialRequestController;

  /// Arkadaşlık isteği akıştan gönderiliyor: uygulamada başka bir üyenin
  /// profilini açan hiçbir ekran yok, karşılaşma yeri burası.
  final FriendshipController friendshipController;

  /// Story oluşturma akışındaki "Tanıtım Yap" adımı buradan gönderilir:
  /// paylaşılan görsel, sponsorlu alan talebinin de görseli olur.
  final PromotionsController promotionsController;

  /// The signed-in member, so the composer can say who is about to post. Null
  /// only in builds with no session, where the composer names nobody at all.
  final AppUser? viewer;

  /// Üyenin seçtiği eyalet, kabuktaki ana sayfa özetinden okunuyor. Yalnızca
  /// boş "Yakınındakiler" sekmesinin doğru cümleyi kurabilmesi için: kimse
  /// paylaşmadığı için mi boş, yoksa üye şehrini hiç eklemediği için mi?
  final String? Function()? viewerRegion;

  /// Akıştaki haber kartına dokunulduğunda haberi açar. Haber ekranı kendi
  /// denetleyicilerini istiyor ve onlar kabukta duruyor; akış ekranı yalnızca
  /// haberin kimliğini söylüyor. Null ise kart dokunulmaz kalır - hiçbir yere
  /// gitmeyen bir kart açılmaz.
  final void Function(String articleId)? onOpenArticle;

  /// Every post, comment and story below this point needs a way to be reported,
  /// so the repository is handed down rather than looked up: the widgets that
  /// need it are built inside list builders with no other access to the app's
  /// dependencies.
  final ContentModerationRepository moderationRepository;

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  @override
  void initState() {
    super.initState();
    // Story şeridi ana sayfada da duruyor; ikisi tek denetleyiciyi paylaşıyor.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.controller.load();
      widget.storyController.load();
    });
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
      // Yükleyemeyen bir sekme artık bütün ekranı kaplamıyor. Eskiden
      // "Takip ettiklerin" cevapsız kalınca akışın tamamı hata ekranına
      // dönüşüyordu: Story rayı da sekme şeridi de kayboluyor, üye çalışan
      // sekmeye dönemiyordu. Hata artık kendi sekmesinin içinde duruyor.
      return _Feed(
        controller: widget.controller,
        storyController: widget.storyController,
        commentsController: widget.commentsController,
        mediaUploadController: widget.mediaUploadController,
        specialRequestController: widget.specialRequestController,
        friendshipController: widget.friendshipController,
        moderationRepository: widget.moderationRepository,
        promotionsController: widget.promotionsController,
        viewer: widget.viewer,
        viewerRegion: widget.viewerRegion,
        onOpenArticle: widget.onOpenArticle,
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
    required this.friendshipController,
    required this.moderationRepository,
    required this.promotionsController,
    this.viewer,
    this.viewerRegion,
    this.onOpenArticle,
  });
  final CommunityFeedController controller;
  final StoryController storyController;
  final CommunityCommentsController commentsController;
  final MediaUploadController mediaUploadController;
  final CommunitySpecialRequestController specialRequestController;
  final FriendshipController friendshipController;
  final ContentModerationRepository moderationRepository;
  final PromotionsController promotionsController;
  final AppUser? viewer;
  final String? Function()? viewerRegion;
  final void Function(String articleId)? onOpenArticle;

  @override
  State<_Feed> createState() => _FeedState();
}

class _FeedState extends State<_Feed> {
  /// Kimin paylaşımı "benim" sayılacağı, kimin yorumu silinebileceği buradan
  /// çıkıyor. Sabit 'local-user' yazdığı sürece gerçek bir hesapla girildiğinde
  /// üye kendi paylaşımının silme düğmesini göremiyordu.
  String get _viewerId => widget.viewer?.id ?? 'local-user';

  /// Üç sekme yan yana duran üç sayfa: parmakla sağa sola kaydırmak da
  /// sekmeye dokunmakla aynı şeyi yapıyor.
  final _pageController = PageController();
  _FeedFilter _filter = _FeedFilter.forYou;
  /// Akıştaki kutu da alt bardaki ➕ da artık aynı editörü açıyor: iki ayrı
  /// düzenleyici, iki ayrı eksik demekti (tabakada anket sahteydi, tam ekran
  /// akışta anket hiç yoktu).
  Future<void> _openComposer(PostComposerPreset preset) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => PostComposerScreen(
            feedController: widget.controller,
            mediaUploadController: widget.mediaUploadController,
            viewer: widget.viewer,
            preset: preset,
            loadTaggablePeople: () async => [
              for (final contact
                  in await widget.storyController.loadAudienceContacts())
                TaggedUser(id: contact.id, displayName: contact.displayName),
            ],
          ),
        ),
      );

  /// Yorum tabakası artık paylaşılan bir bileşen; akışa özgü olan yalnızca
  /// erişim politikası, o da buradan geçiriliyor.
  ///
  /// Haber kartı bunun dışında: onun yorumları haberin altındaki yorumlar ve
  /// haber ekranında zaten okunuyor. Akışta ikinci bir tabaka açmak, aynı iş
  /// parçacığını iki ayrı yerden okumak olurdu.
  void _openComments(CommunityPost post) {
    final article = post.newsReference;
    if (article != null && widget.onOpenArticle != null) {
      widget.onOpenArticle!(article.articleId);
      return;
    }
    openPostComments(
      context: context,
      post: post,
      controller: widget.commentsController,
      moderationRepository: widget.moderationRepository,
      viewerId: _viewerId,
    );
  }

  Future<void> _vote(
    String postId,
    String pollId,
    Set<String> optionIds,
  ) async {
    try {
      await widget.controller.voteOnPoll(
        postId: postId,
        pollId: pollId,
        optionIds: optionIds,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Oyun kaydedilemedi. Tekrar dene.')),
      );
    }
  }

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

  /// Arkadaşlık isteği. Karşı taraf da istek göndermişse sunucu bunu doğrudan
  /// arkadaşlığa çeviriyor, o yüzden mesaj dönen duruma bakıyor.
  Future<void> _addFriend(CommunityPost post) async {
    final messenger = ScaffoldMessenger.of(context);
    final sent = await widget.friendshipController.send(post.ownerId);
    if (!mounted) return;
    if (!sent) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.friendshipController.errorMessage ??
                'İstek şu anda gönderilemedi.',
          ),
        ),
      );
      return;
    }
    final becameFriends =
        widget.friendshipController.statusOf(post.ownerId) ==
        FriendshipStatus.friends;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          becameFriends
              ? '${post.authorName} ile artık arkadaşsınız.'
              : 'Arkadaşlık isteği gönderildi.',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _selectFilter(_FeedFilter value) {
    if (value == _filter) return;
    setState(() => _filter = value);
    unawaited(widget.controller.setMode(value.mode));
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
                  child: _ReferenceComposer(onCompose: _openComposer),
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
              onPageChanged: (value) {
                final filter = _FeedFilter.values[value];
                setState(() => _filter = filter);
                unawaited(widget.controller.setMode(filter.mode));
              },
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
    final loading = widget.controller.isLoadingMode(filter.mode);
    final failed = widget.controller.hasFailedMode(filter.mode);
    return RefreshIndicator(
      onRefresh: widget.controller.refresh,
      child: ListView(
        key: PageStorageKey('feed-${filter.name}'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 12, bottom: 28),
        children: [
          // Boş liste üç ayrı şey olabiliyor ve üçü aynı ekranı hak etmiyor:
          // henüz gelmedi, gelemedi, ya da gerçekten boş.
          if (posts.isEmpty && loading) const _FeedSkeleton(),
          if (posts.isEmpty && failed)
            _FeedFailureState(
              message: widget.controller.errorMessage ?? 'Akış yüklenemedi.',
              onRetry: widget.controller.load,
            ),
          if (posts.isEmpty && !loading && !failed)
            _FeedEmptyState(
              filter: filter,
              hasLocality: widget.viewerRegion?.call() != null,
            ),
          for (final post in posts)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _PostCard(
                post: post,
                onToggleLike: widget.controller.toggleLike,
                specialRequestController: widget.specialRequestController,
                friendshipController: widget.friendshipController,
                // Kendi paylaşımına arkadaşlık isteği gönderilemez ve kimliği
                // bilinmeyen bir yazara da: sunucu ikisini de reddeder. Haber
                // Bülteni de eklenemez; arkasında bir üye yok.
                onAddFriend:
                    post.isNewsBulletin ||
                        post.isAuthor ||
                        post.ownerId == _viewerId ||
                        post.ownerId.isEmpty ||
                        post.ownerId == 'local-user'
                    ? null
                    : () => _addFriend(post),
                moderationRepository: widget.moderationRepository,
                // Sunucu artık hem yazanın kimliğini hem de doğrudan cevabı
                // gönderiyor. İkisi de duruyor çünkü ikisi ayrı soruya cevap
                // veriyor: `isAuthor` oturum henüz okunmamışken de doğru,
                // `ownerId` ise sahte kipteki paylaşımlar için tek ölçü.
                onDelete: post.isAuthor || post.ownerId == _viewerId
                    ? () => _deletePost(post)
                    : null,
                onOpenComments: () => _openComments(post),
                onOpenArticle: widget.onOpenArticle,
                onVote: _vote,
              ),
            ),
          PagedListFooter<CommunityPost>(controller: widget.controller),
        ],
      ),
    );
  }

  /// Süzme sunucuda yapılıyor; ekranın gösterdiği liste, açık olan sekme için
  /// gelen liste. Sekme değişince denetleyici listeyi boşaltıp yeniden yüklüyor,
  /// o yüzden kaydırma sırasında öteki sayfa boş duruyor.
  List<CommunityPost> _postsFor(_FeedFilter filter) =>
      widget.controller.itemsFor(filter.mode);
}

/// Sekme şeridini akışın tepesine çiviler.
class _FeedFiltersHeader extends SliverPersistentHeaderDelegate {
  const _FeedFiltersHeader({required this.selected, required this.onSelected});
  final _FeedFilter selected;
  final ValueChanged<_FeedFilter> onSelected;

  @override
  double get minExtent => _feedFilterStripHeight;

  @override
  double get maxExtent => _feedFilterStripHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      _ReferenceFeedFilters(selected: selected, onSelected: onSelected);

  @override
  bool shouldRebuild(_FeedFiltersHeader oldDelegate) =>
      oldDelegate.selected != selected;
}

class _FeedEmptyState extends StatelessWidget {
  const _FeedEmptyState({required this.filter, this.hasLocality = true});
  final _FeedFilter filter;

  /// Üye şehrini eklediyse boş "Yakınındakiler" gerçekten boş demek; eklemediyse
  /// sekmenin sorabileceği bir soru yok. İkisine aynı cümleyi yazmak, ikincisini
  /// bir yanlışlık gibi gösteriyor.
  final bool hasLocality;

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
            _FeedFilter.nearby => hasLocality
                ? 'Bulunduğun eyalette henüz paylaşım yok.'
                : 'Şehrini eklemedin, bu yüzden burası boş.',
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

/// Sekmenin ilk sayfası yoldayken görünen iskelet.
///
/// Dönen bir çark ekranın ortasında hiçbir şey anlatmıyordu; kart hatları
/// gelecek olanın biçimini gösteriyor, liste dolduğunda da ekran yerinden
/// oynamıyor. Kıpırdayan bir parıltı yok: akış sınanırken sonsuz bir animasyon
/// testleri kilitler ve boş bir sekmede göz yorar.
class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var index = 0; index < 3; index++)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE9EAF0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _SkeletonBox(width: 38, height: 38, radius: 19),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        _SkeletonBox(width: 120, height: 11),
                        SizedBox(height: 7),
                        _SkeletonBox(width: 76, height: 9),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const _SkeletonBox(width: double.infinity, height: 10),
                const SizedBox(height: 8),
                const _SkeletonBox(width: double.infinity, height: 10),
                const SizedBox(height: 8),
                const _SkeletonBox(width: 180, height: 10),
                if (index == 0) ...[
                  const SizedBox(height: 14),
                  const _SkeletonBox(width: double.infinity, height: 150, radius: 14),
                ],
              ],
            ),
          ),
        ),
    ],
  );
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    this.radius = 6,
  });
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: const Color(0xFFEDEDF2),
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

/// Cevapsız kalan sekme.
///
/// Eskiden başarısız istek bütün ekranı kaplıyordu: sekme şeridi de kaybolduğu
/// için üye çalışan öteki sekmelere geçemiyordu. Hata artık ait olduğu sekmenin
/// içinde duruyor.
class _FeedFailureState extends StatelessWidget {
  const _FeedFailureState({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 32),
    child: AppErrorState(
      message: message,
      onRetry: () => unawaited(onRetry()),
    ),
  );
}

enum _FeedFilter {
  forYou(FeedMode.forYou, 'Senin İçin', Icons.auto_awesome_rounded),
  nearby(FeedMode.nearby, 'Yakınındakiler', Icons.near_me_rounded),
  following(FeedMode.following, 'Takip ettiklerin', Icons.group_rounded);

  const _FeedFilter(this.mode, this.label, this.icon);
  final FeedMode mode;
  final String label;
  final IconData icon;
}

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

  /// Şerit yatay kayıyor: üç etiket, büyük yazı tipi seçen bir cihazda ekrana
  /// sığmıyor ve sabit bir satırda taşma çizgisine dönüşüyordu.
  @override
  Widget build(BuildContext context) => Container(
    height: _feedFilterStripHeight,
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Color(0xFFEFEFF3))),
    ),
    // ListView değil: tembel liste görünmeyen sekmeyi hiç kurmuyor, dar bir
    // ekranda üçüncü sekme ağaçta bile olmuyordu. Üç öğe için hepsini kurmanın
    // maliyeti yok.
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // Sol boşluk kartlarınkiyle aynı: şerit kartların hizasında başlıyor.
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      child: Row(
        children: [
          for (final filter in _FeedFilter.values) ...[
            _ReferenceFilter(
              label: filter.label,
              icon: filter.icon,
              active: selected == filter,
              onTap: () => onSelected(filter),
            ),
            if (filter != _FeedFilter.values.last) const SizedBox(width: 8),
          ],
          // Sağda bir filtre düğmesi vardı, hiçbir şey yapmıyordu; sekmeler
          // zaten filtrenin kendisi. Boş bir düğme, çalıştığını sanıp basan
          // üyeye yalan söylüyor.
        ],
      ),
    ),
  );
}

const double _feedFilterStripHeight = 52;

class _ReferenceFilter extends StatelessWidget {
  const _ReferenceFilter({
    required this.label,
    required this.icon,
    this.active = false,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(17),
    child: Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? const Color(0xFF6B54E8) : const Color(0xFFF1F1F4),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: active ? Colors.white : const Color(0xFF706C78),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: active ? Colors.white : const Color(0xFF706C78),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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

class _ReferenceComposer extends StatelessWidget {
  const _ReferenceComposer({required this.onCompose});

  /// Kutunun kendisi de altındaki üç kısayol da aynı editörü açıyor; kısayollar
  /// yalnızca editörü hangi ayarla açacağını söylüyor. Eskiden bu üç düğme
  /// hiçbir şey yapmıyordu, kutuya dokunmakla aynı yere bile gitmiyorlardı.
  final void Function(PostComposerPreset preset) onCompose;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: () => onCompose(PostComposerPreset.standard),
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
            Row(
              children: [
                _ComposerAction(
                  icon: Icons.help_outline_rounded,
                  label: 'Soru Sor',
                  color: const Color(0xFF5D55DB),
                  onTap: () => onCompose(PostComposerPreset.question),
                ),
                const SizedBox(width: 7),
                _ComposerAction(
                  icon: Icons.storefront_outlined,
                  label: 'Çarşı İlanı',
                  color: const Color(0xFF5D55DB),
                  onTap: () => onCompose(PostComposerPreset.marketplace),
                ),
                const SizedBox(width: 7),
                _ComposerAction(
                  icon: Icons.bar_chart_rounded,
                  label: 'Anket',
                  color: const Color(0xFFF59E0B),
                  onTap: () => onCompose(PostComposerPreset.poll),
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
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
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
    ),
  );
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.onToggleLike,
    required this.onOpenComments,
    required this.specialRequestController,
    required this.friendshipController,
    required this.moderationRepository,
    required this.onVote,
    this.onDelete,
    this.onAddFriend,
    this.onOpenArticle,
  });
  final CommunityPost post;
  final ValueChanged<String> onToggleLike;
  final VoidCallback onOpenComments;

  /// (postId, pollId, seçilen seçenekler) — anket kartı sayaçları kendi
  /// uydurmuyor, oy sunucuya gidiyor ve dönen dağılım gösteriliyor.
  final void Function(String postId, String pollId, Set<String> optionIds)
  onVote;
  final CommunitySpecialRequestController specialRequestController;
  final FriendshipController friendshipController;
  final ContentModerationRepository moderationRepository;
  final VoidCallback? onDelete;

  /// Null: kendi paylaşımı ya da yazarı belli olmayan bir paylaşım.
  final VoidCallback? onAddFriend;

  /// Haber kartında dolu. Null ise kart dokunulmaz kalır.
  final void Function(String articleId)? onOpenArticle;

  @override
  Widget build(BuildContext context) {
    final article = post.newsReference;
    // Karta dokunmak haberi açar. Gidilecek bir yer yoksa dokunma da yok:
    // hiçbir şey yapmayan bir dokunuş, kırık bir bağlantıdan farksız.
    final openArticle = article != null && onOpenArticle != null
        ? () => onOpenArticle!(article.articleId)
        : null;
    return GestureDetector(
      onTap: openArticle,
      behavior: HitTestBehavior.opaque,
      child: _card(context, article),
    );
  }

  Widget _card(BuildContext context, NewsPostReference? article) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: article == null
            ? const Color(0xFFE5E7EB)
            : AppColors.primary.withValues(alpha: .28),
      ),
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
            // Haber Bülteni'nin baş harfi yok: bu bir kişi değil. Gazete
            // simgesi imzanın kendisi, altındaki isim de tıklanmıyor -
            // açılacak bir profil olmadığı için.
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.primary.withValues(
                alpha: article == null ? .16 : .22,
              ),
              child: article == null
                  ? Text(
                      post.authorName.substring(0, 1),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  : const Icon(
                      Icons.newspaper_rounded,
                      size: 20,
                      color: AppColors.primary,
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          post.authorName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (article != null) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.verified_rounded,
                          size: 15,
                          color: AppColors.primary,
                        ),
                      ],
                    ],
                  ),
                  Text(
                    article == null
                        ? [
                            if (post.location.isNotEmpty) post.location,
                            post.relativeTime,
                          ].join(' · ')
                        : '${NewsCategory.fromCode(article.category).label} · ${post.relativeTime}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedBuilder(
              animation: friendshipController,
              builder: (context, _) => PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  color: AppColors.textMuted,
                ),
                onSelected: (value) {
                  if (value == 'delete') onDelete?.call();
                  if (value == 'friend') onAddFriend?.call();
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
                  // Durumu bilinen bir ilişkide "Arkadaş ekle" yazmak yanlış
                  // olurdu: zaten arkadaşsanız ya da istek beklemedeyse
                  // düğme bunu söylüyor ve tıklanmıyor.
                  if (onAddFriend != null)
                    PopupMenuItem(
                      value: 'friend',
                      enabled:
                          friendshipController.statusOf(post.ownerId) ==
                          FriendshipStatus.none,
                      child: Text(
                        switch (friendshipController.statusOf(post.ownerId)) {
                          FriendshipStatus.friends => 'Arkadaşınız',
                          FriendshipStatus.pendingOutgoing => 'İstek gönderildi',
                          FriendshipStatus.pendingIncoming =>
                            'Sana istek gönderdi',
                          FriendshipStatus.blocked => 'Engellendi',
                          FriendshipStatus.none => 'Arkadaş ekle',
                        },
                      ),
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
        // Sahibinin tarafı: gelen istekler. Bu düğmeye kadar istekleri okuyan
        // bir yer yoktu, o yüzden kimse yanıtlayamıyordu.
        if (post.isAuthor &&
            (post.purpose == CommunityPostPurpose.imeceHelp ||
                post.purpose == CommunityPostPurpose.travelerMatch))
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                backgroundColor: Colors.transparent,
                builder: (_) => PostRequestsSheet(
                  post: post,
                  controller: specialRequestController,
                ),
              ),
              icon: const Icon(Icons.mark_email_unread_outlined, size: 18),
              label: const Text('Gelen istekler'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
          ),
        // Kendi ilanına istek göndermek diye bir şey yok: düğme sahibine
        // gösterilmiyordu değil, gösteriliyordu - ve dokunulunca kendine
        // "Eşleşme isteği gönder" diyordu.
        if (!post.isAuthor &&
            (post.purpose == CommunityPostPurpose.imeceHelp ||
                post.purpose == CommunityPostPurpose.travelerMatch))
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
        // Haberin başlığı akışta da başlık gibi duruyor. Altındaki metin
        // haberin özeti; kartın tamamı zaten habere götürüyor.
        if (article != null && article.title.isNotEmpty) ...[
          Text(
            article.title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 16,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 6),
        ],
        _ExpandablePostText(message: post.message),
        if (post.media.isNotEmpty) ...[
          const SizedBox(height: 12),
          _PostMediaStrip(media: post.media),
        ],
        if (post.poll case final poll?) ...[
          const SizedBox(height: 12),
          _PollCard(
            poll: poll,
            onVote: (optionIds) => onVote(post.id, poll.id, optionIds),
          ),
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
        // Kartın tamamı habere götürüyor ama dokunulabildiği görünmüyor;
        // bu satır onu söylüyor.
        if (article != null) ...[
          const SizedBox(height: 10),
          const Row(
            children: [
              Text(
                'Haberin tamamını oku',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(width: 4),
              Icon(
                Icons.arrow_forward_rounded,
                size: 14,
                color: AppColors.primary,
              ),
            ],
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

/// Akıştaki anket.
///
/// Oy verilmeden önce seçenekler dokunulabilir satır, sonrasında dağılımı
/// gösteren çubuk. Anket kapandıysa sonuç doğrudan görünüyor: kapanmış bir
/// ankette "oy ver" göstermek, çalışmayacak bir düğme göstermek olurdu.
class _PollCard extends StatefulWidget {
  const _PollCard({required this.poll, required this.onVote});
  final CommunityPoll poll;
  final ValueChanged<Set<String>> onVote;

  @override
  State<_PollCard> createState() => _PollCardState();
}

class _PollCardState extends State<_PollCard> {
  final Set<String> _pending = {};

  CommunityPoll get _poll => widget.poll;
  bool get _hasVoted => _poll.selectedOptionIds.isNotEmpty;
  bool get _showResults => _hasVoted || _poll.isClosed;
  int get _totalVotes =>
      _poll.options.fold(0, (total, option) => total + option.votes);

  void _toggle(String optionId) => setState(() {
    if (_poll.selectionMode == PollSelectionMode.single) {
      _pending
        ..clear()
        ..add(optionId);
      return;
    }
    if (!_pending.remove(optionId)) _pending.add(optionId);
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      border: Border.all(color: const Color(0xFFE2E8F0)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final option in _poll.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _showResults
                ? _PollResultRow(
                    label: option.label,
                    votes: option.votes,
                    total: _totalVotes,
                    isMine: _poll.selectedOptionIds.contains(option.id),
                  )
                : InkWell(
                    onTap: () => _toggle(option.id),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(
                          color: _pending.contains(option.id)
                              ? AppColors.primary
                              : const Color(0xFFE2E8F0),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _pending.contains(option.id)
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked,
                            size: 18,
                            color: _pending.contains(option.id)
                                ? AppColors.primary
                                : const Color(0xFFCBD5E1),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              option.label,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        Row(
          children: [
            Text(
              _poll.isClosed
                  ? '$_totalVotes oy · Anket kapandı'
                  : '$_totalVotes oy',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            const Spacer(),
            if (!_showResults)
              FilledButton(
                onPressed: _pending.isEmpty
                    ? null
                    : () => widget.onVote(Set.unmodifiable(_pending)),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Oy ver'),
              ),
          ],
        ),
      ],
    ),
  );
}

class _PollResultRow extends StatelessWidget {
  const _PollResultRow({
    required this.label,
    required this.votes,
    required this.total,
    required this.isMine,
  });
  final String label;
  final int votes;
  final int total;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : votes / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (isMine) ...[
              const Icon(
                Icons.check_circle_rounded,
                size: 15,
                color: AppColors.primary,
              ),
              const SizedBox(width: 5),
            ],
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isMine ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
            Text(
              '%${(fraction * 100).round()}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: const Color(0xFFE7E9F2),
            valueColor: AlwaysStoppedAnimation(
              isMine ? AppColors.primary : const Color(0xFFB9BFD6),
            ),
          ),
        ),
      ],
    );
  }
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
