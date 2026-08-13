import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../community/application/community_feed_controller.dart';
import '../../../community/application/story_controller.dart';
import '../../../community/application/community_comments_controller.dart';
import '../../../community/application/media_upload_controller.dart';
import '../../../community/domain/repositories/community_repository.dart';
import '../../../community/application/community_special_request_controller.dart';
import '../../../events/application/events_controller.dart';
import '../../../marketplace/application/marketplace_controller.dart';
import '../../../profile/application/profile_controller.dart';
import '../../../journey/application/journey_controller.dart';
import '../../../journey/presentation/screens/journey_screen.dart';
import '../../../community/domain/repositories/content_moderation_repository.dart';
import '../../../community/presentation/screens/community_screen.dart';
import '../../../community/domain/entities/community_post.dart';
import '../../../community/presentation/screens/post_composer_screen.dart';
import '../../../marketplace/presentation/screens/marketplace_screen.dart';
import '../../../forum/application/forum_controller.dart';
import '../../../forum/domain/entities/forum.dart';
import '../../../forum/presentation/screens/forum_screen.dart';
import '../../../forum/presentation/screens/forum_topic_screen.dart';
import '../../../news/application/news_controller.dart';
import '../../../news/presentation/screens/news_article_screen.dart';
import '../../../news/presentation/screens/news_center_screen.dart';
import '../../../notifications/application/notifications_controller.dart';
import '../../../notifications/presentation/screens/notifications_screen.dart';
import '../../../promotions/application/promotions_controller.dart';
import '../../../promotions/domain/entities/promotion.dart';
import '../../../promotions/presentation/widgets/promotion_detail_sheet.dart';
import '../../../community/domain/entities/feed_extensions.dart';
import '../../../community/presentation/screens/story_viewer_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import 'discover_screen.dart';
import '../widgets/app_top_bar.dart';
import '../../application/community_home_controller.dart';
import '../../../verification/application/member_capabilities_controller.dart';
import '../../../../app/router/app_routes.dart';
import '../../../auth/application/auth_controller.dart';

class MainLayoutScreen extends StatefulWidget {
  const MainLayoutScreen({
    super.key,
    required this.communityController,
    required this.storyController,
    required this.commentsController,
    required this.mediaUploadController,
    required this.postCommands,
    required this.specialRequestController,
    required this.contentModerationRepository,
    required this.eventsController,
    required this.marketplaceController,
    required this.profileController,
    required this.journeyController,
    required this.onSignOut,
    required this.homeController,
    required this.memberCapabilitiesController,
    required this.authController,
    required this.notificationsController,
    required this.newsController,
    required this.newsCommentsController,
    required this.promotionsController,
    required this.forumController,
  });
  final CommunityFeedController communityController;
  final StoryController storyController;
  final CommunityCommentsController commentsController;
  final MediaUploadController mediaUploadController;
  final CommunityPostCommands postCommands;
  final CommunitySpecialRequestController specialRequestController;
  final ContentModerationRepository contentModerationRepository;
  final EventsController eventsController;
  final MarketplaceController marketplaceController;
  final ProfileController profileController;
  final JourneyController journeyController;
  final Future<void> Function() onSignOut;
  final CommunityHomeController homeController;
  final MemberCapabilitiesController memberCapabilitiesController;
  final AuthController authController;
  final NotificationsController notificationsController;
  final NewsController newsController;

  /// Haber yorumları için kurulmuş denetleyici; akıştakiyle aynı sınıf, ayrı
  /// depo.
  final CommunityCommentsController newsCommentsController;

  /// Sponsorlu Story yuvası ve "Sana Özel Öne Çıkanlar" kartları.
  final PromotionsController promotionsController;

  /// Çeker menüdeki Forum ile ana sayfadaki trend şeridi aynı denetleyiciyi
  /// okur; bir konuyu şeritten açıp beğenmek listede de görünür.
  final ForumController forumController;

  @override
  State<MainLayoutScreen> createState() => _MainLayoutScreenState();
}

class _MainLayoutScreenState extends State<MainLayoutScreen>
    with SingleTickerProviderStateMixin {
  var _currentIndex = 0;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late List<Widget> _pages;

  List<Widget> _buildPages() => [
    DiscoverScreen(
      controller: widget.homeController,
      onOpenBadges: _openBadges,
      newsController: widget.newsController,
      onOpenArticle: (article) => _openArticle(article.id),
      onOpenNewsCenter: _openNewsCenter,
      storyController: widget.storyController,
      promotionsController: widget.promotionsController,
      marketplaceController: widget.marketplaceController,
      onOpenStory: _openStory,
      onOpenPromotion: _openPromotion,
      onOpenMarketplace: () => setState(() => _currentIndex = 2),
      forumController: widget.forumController,
      onOpenForum: (categoryId) => _openForum(categoryId: categoryId),
      onOpenForumTopic: _openForumTopic,
    ),
    // The pages are built once, but the composer inside the feed names the
    // member, and that name can still arrive on a token refresh. Listening
    // here keeps it current without rebuilding the whole stack.
    AnimatedBuilder(
      animation: widget.authController,
      builder: (_, _) => CommunityScreen(
        controller: widget.communityController,
        storyController: widget.storyController,
        commentsController: widget.commentsController,
        mediaUploadController: widget.mediaUploadController,
        specialRequestController: widget.specialRequestController,
        moderationRepository: widget.contentModerationRepository,
        promotionsController: widget.promotionsController,
        viewer: widget.authController.user,
      ),
    ),
    MarketplaceScreen(
      controller: widget.marketplaceController,
      memberCapabilitiesController: widget.memberCapabilitiesController,
    ),
    ProfileScreen(
      controller: widget.profileController,
      journeyController: widget.journeyController,
      onSignOut: widget.onSignOut,
      memberCapabilitiesController: widget.memberCapabilitiesController,
      storyController: widget.storyController,
      mediaUploadController: widget.mediaUploadController,
      postCommands: widget.postCommands,
    ),
  ];

  /// The home screen's badge card promised a destination and never had one.
  /// It leads where the profile's badge counter leads: the Journey cabinet,
  /// opened on its Rozetler tab. The route lives here because DiscoverScreen
  /// only takes a callback.
  void _openBadges() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => JourneyScreen(
        controller: widget.journeyController,
        initialTab: JourneyTab.badges,
      ),
    ),
  );

  /// The home rail and the feed rail share one controller, so a Story opened
  /// from either side counts as read on both.
  void _openStory(StoryItem story) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => StoryViewerScreen(
        controller: widget.storyController,
        initialStoryId: story.id,
        moderationRepository: widget.contentModerationRepository,
      ),
    ),
  );

  /// Where a sponsored card leads. A promotion without a target is not a dead
  /// card: it opens itself, because most of them are an announcement and
  /// nothing more.
  Future<void> _openPromotion(Promotion promotion) async {
    widget.promotionsController.recordClick(promotion.id);
    final value = promotion.targetValue;
    if (value != null && value.isNotEmpty) {
      switch (promotion.targetKind) {
        case PromotionTargetKind.news:
          _openArticle(value);
          return;
        case PromotionTargetKind.listing:
          setState(() => _currentIndex = 2);
          return;
        case PromotionTargetKind.post:
          setState(() => _currentIndex = 1);
          return;
        case PromotionTargetKind.external:
          final uri = Uri.tryParse(value);
          // Yalnızca http(s): tanıtım kartı, uygulamanın başka bir şemayla ne
          // açacağına karar verdiği yer değil.
          if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
            final opened = await launchUrl(
              uri,
              mode: LaunchMode.externalApplication,
            );
            if (opened) return;
          }
        // Etkinlik ekranı bu fazın dışında; hedef çözülemezse tanıtımın
        // kendisi açılır.
        case PromotionTargetKind.event:
        case null:
          break;
      }
    }
    if (!mounted) return;
    await showAppBottomSheet<void>(
      context: context,
      child: PromotionDetailSheet(promotion: promotion),
    );
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );
    _pages = _buildPages();
    // The bell carries a count, so it has to know the answer before anyone
    // opens the notification list.
    widget.notificationsController.load();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MainLayoutScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _pages = _buildPages();
  }

  @override
  void reassemble() {
    super.reassemble();
    _pages = _buildPages();
  }

  void _openMenu() {
    _scaffoldKey.currentState?.openEndDrawer();
  }

  void _openMessages() => Navigator.of(context).pushNamed(AppRoutes.inbox);

  /// Haber Merkezi ana sayfadaki manşet şeridiyle aynı denetleyiciyi paylaşır;
  /// bir haberi burada beğenmek şeritteki sayacı da günceller.
  /// Manşet şeridinden doğrudan habere; Haber Merkezi'nden geçmeye gerek yok.
  void _openArticle(String articleId) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => NewsArticleScreen(
        articleId: articleId,
        controller: widget.newsController,
        commentsController: widget.newsCommentsController,
        moderationRepository: widget.contentModerationRepository,
        viewerId: widget.authController.user?.id ?? 'local-user',
      ),
    ),
  );

  void _openNewsCenter() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => NewsCenterScreen(
        controller: widget.newsController,
        commentsController: widget.newsCommentsController,
        moderationRepository: widget.contentModerationRepository,
        viewerId: widget.authController.user?.id ?? 'local-user',
      ),
    ),
  );

  void _openForum({String? categoryId}) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ForumScreen(
        controller: widget.forumController,
        moderationRepository: widget.contentModerationRepository,
        viewerId: widget.authController.user?.id ?? 'local-user',
        initialCategoryId: categoryId,
      ),
    ),
  );

  /// Ana sayfadaki şeritten doğrudan konuya; forum listesinden geçmeye gerek
  /// yok. Aynı denetleyici okunduğu için okunma sayacı iki yerde de artıyor.
  void _openForumTopic(ForumTopic topic) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ForumTopicScreen(
        topicId: topic.id,
        controller: widget.forumController,
        moderationRepository: widget.contentModerationRepository,
        viewerId: widget.authController.user?.id ?? 'local-user',
      ),
    ),
  );

  void _openNotifications() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          NotificationsScreen(controller: widget.notificationsController),
    ),
  );

  /// The compose sheet, reachable from the ➕ in the middle of the nav bar.
  ///
  /// Until now the only way in was a box buried in the feed, which meant the
  /// primary action of a social app was three taps deep on three of four tabs.
  void _openComposer() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => PostComposerScreen(
        feedController: widget.communityController,
        mediaUploadController: widget.mediaUploadController,
        viewer: widget.authController.user,
        loadTaggablePeople: () async => [
          for (final contact
              in await widget.storyController.loadAudienceContacts())
            TaggedUser(id: contact.id, displayName: contact.displayName),
        ],
      ),
    ),
  );

  /// Sayfalar bir kez kuruluyor ve `IndexedStack` içinde canlı kalıyor: profil
  /// sekmesi kendini yalnızca ilk açılışta yüklüyordu, dolayısıyla yeni paylaşım
  /// ızgaraya ancak uygulama yeniden açılınca düşüyordu. Sekmeye her dönüşte
  /// tazeleniyor.
  void _selectPage(int index) {
    setState(() => _currentIndex = index);
    if (index == 3) widget.profileController.load();
    if (index == 0) widget.homeController.load();
  }

  /// The location line under the greeting, or null while the summary is still
  /// loading. A member with no locality yet gets no line rather than a blank one.
  String? get _localityLabel {
    final summary = widget.homeController.summary;
    final city = summary?.city?.trim();
    if (city == null || city.isEmpty) return null;
    final region = summary?.regionCode?.trim();
    return region == null || region.isEmpty ? city : '$city, $region';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      endDrawer: _buildModernSideDrawer(context, AppColors.primary),
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 84),
              child: Column(
                children: [
                  // Above the stack, not inside a page: the menu and the bell
                  // belong to the shell, so they survive a tab change.
                  AnimatedBuilder(
                    animation: Listenable.merge([
                      widget.authController,
                      widget.homeController,
                      widget.notificationsController,
                    ]),
                    builder: (_, _) {
                      final user = widget.authController.user;
                      return AppTopBar(
                        title: _titleFor(_currentIndex, user?.displayName),
                        greetingName: _currentIndex == 0
                            ? user?.shortName
                            : null,
                        subtitle: _currentIndex == 0 ? _localityLabel : null,
                        onOpenMenu: _openMenu,
                        onOpenNotifications: _openNotifications,
                        unreadNotifications:
                            widget.notificationsController.unreadCount,
                      );
                    },
                  ),
                  Expanded(
                    child: IndexedStack(
                      index: _currentIndex,
                      children: _pages,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 16,
            child: _FloatingNav(
              pageIndex: _currentIndex,
              onSelectPage: _selectPage,
              onCompose: _openComposer,
            ),
          ),
        ],
      ),
    );
  }

  /// What the bar says when it is not greeting anyone. The profile tab shows
  /// the member's own name, which is the one place a name is the title.
  static String _titleFor(int index, String? displayName) => switch (index) {
    1 => 'Akış',
    2 => 'Çarşı',
    3 => (displayName?.trim().isNotEmpty ?? false)
        ? displayName!.trim()
        : 'Profil',
    _ => 'TurkSquare',
  };

  Widget _buildModernSideDrawer(BuildContext context, Color primaryIndigo) {
    const drawerDarkBg = Color(0xFF0F172A); // Slate 900
    const cardOverlayBg = Color(0xFF1E293B);
    final user = widget.authController.user;

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.82,
      backgroundColor: drawerDarkBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          bottomLeft: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // 1. DRAWER HEADER & MINIMAL KULLANICI PROFİL KARTI
            Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
              child: Column(
                children: [
                  // Üst Logo ve Kapat Butonu
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          FadeTransition(
                            opacity: _pulseAnimation,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF818CF8),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'TURKSQUARE',
                            style: TextStyle(
                              color: Color(0xFFA5B4FC),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                        icon: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Minimalist Profil Kartı
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Stack(
                          children: [
                            // Initials, not a stock photo of someone else. The
                            // real avatar lands here once profiles carry one.
                            Container(
                              width: 38,
                              height: 38,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: primaryIndigo.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.12),
                                ),
                              ),
                              child: Text(
                                user?.initials ?? '?',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF34D399),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: drawerDarkBg,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      // The signed-up name, falling back to the
                                      // address rather than to a stand-in person.
                                      user?.displayName?.trim().isNotEmpty ==
                                              true
                                          ? user!.displayName!.trim()
                                          : user?.email.split('@').first ??
                                                'Üye',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  // "Onaylı" is earned, unlike the PRO chip that
                                  // used to sit here for everyone.
                                  if (widget
                                      .memberCapabilitiesController
                                      .value
                                      .identityVerified) ...[
                                    const SizedBox(width: 6),
                                    const Icon(
                                      Icons.verified_rounded,
                                      size: 14,
                                      color: Color(0xFF38BDF8),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                user?.email ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 2. KAYDIRILABİLİR MENÜ ÖĞELERİ
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                children: [
                  // 1. MESAJLAR
                  _buildDrawerItem(
                    title: 'Mesajlar',
                    subtitle: 'Sohbetler ve bildirimler',
                    icon: Icons.send_rounded,
                    iconBg: primaryIndigo.withValues(alpha: 0.15),
                    iconColor: const Color(0xFF818CF8),
                    // No badge: the count used to be a hardcoded `3`, which was
                    // wrong for everyone. It comes back when the inbox publishes
                    // a real unread total.
                    isActive: false,
                    onTap: () {
                      Navigator.pop(context);
                      _openMessages();
                    },
                  ),

                  const SizedBox(height: 4),

                  // 2. HABER MERKEZİ
                  _buildDrawerItem(
                    title: 'Haber Merkezi',
                    subtitle: 'Amerika gündemi ve topluluk haberleri',
                    icon: Icons.newspaper_rounded,
                    iconBg: AppColors.primary.withValues(alpha: 0.15),
                    iconColor: const Color(0xFF818CF8),
                    onTap: () {
                      Navigator.pop(context);
                      _openNewsCenter();
                    },
                  ),

                  const SizedBox(height: 4),

                  // 3. FORUM
                  _buildDrawerItem(
                    title: 'Forum',
                    subtitle: 'Vize, emlak, iş kurma: aranıp bulunan cevaplar',
                    icon: Icons.forum_rounded,
                    iconBg: AppColors.primary.withValues(alpha: 0.15),
                    iconColor: const Color(0xFF818CF8),
                    onTap: () {
                      Navigator.pop(context);
                      _openForum();
                    },
                  ),

                  const SizedBox(height: 4),

                  // 4. TURKSQUARE YAYIN (SESLİ SOHBET SİSTEMİ)
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF581C87).withValues(alpha: 0.3),
                          const Color(0xFF881337).withValues(alpha: 0.2),
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFA855F7).withValues(alpha: 0.25),
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      // Sesli oda henüz yok; canlı görünen bir satır bırakmıyoruz.
                      enabled: false,
                      leading: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFF43F5E,
                              ).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.graphic_eq_rounded,
                              size: 18,
                              color: Color(0xFFFB7185),
                            ),
                          ),
                          // The pulsing "live now" dot is gone with it: nothing
                          // is broadcasting.
                        ],
                      ),
                      title: Row(
                        children: [
                          const Text(
                            'TurkSquare Yayın',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFF43F5E,
                              ).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(
                                  0xFFFB7185,
                                ).withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Text(
                              'Sesli Oda',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFFDA4AF),
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: const Text(
                        'Canlı sesli sohbet alanları',
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                      trailing: const _ComingSoonChip(),
                    ),
                  ),

                  const SizedBox(height: 4),

                  // 5. PROFİL VE HESAP
                  _buildDrawerItem(
                    title: 'Profil ve Hesap',
                    subtitle: 'Üyelik & kişisel veriler',
                    icon: Icons.person_outline_rounded,
                    iconBg: Colors.white.withValues(alpha: 0.05),
                    iconColor: const Color(0xFF94A3B8),
                    onTap: () {
                      Navigator.pop(context);
                      setState(() => _currentIndex = 3);
                    },
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Divider(
                      color: Colors.white.withValues(alpha: 0.08),
                      height: 1,
                    ),
                  ),

                  // 6. BİLDİRİM TERCİHLERİ
                  _buildDrawerItem(
                    title: 'Bildirim Tercihleri',
                    subtitle: 'Anlık bildirim & e-posta',
                    icon: Icons.notifications_none_rounded,
                    iconBg: Colors.white.withValues(alpha: 0.05),
                    iconColor: const Color(0xFF94A3B8),
                    comingSoon: true,
                    onTap: () {},
                  ),

                  const SizedBox(height: 4),

                  // 7. YARDIM & DESTEK
                  _buildDrawerItem(
                    title: 'Yardım & Destek',
                    subtitle: 'SSS ve canlı destek',
                    icon: Icons.help_outline_rounded,
                    iconBg: Colors.white.withValues(alpha: 0.05),
                    iconColor: const Color(0xFF94A3B8),
                    comingSoon: true,
                    onTap: () {},
                  ),
                ],
              ),
            ),

            // 3. DRAWER FOOTER (ÇIKIŞ YAP & SÜRÜM BİLGİSİ)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: cardOverlayBg.withValues(alpha: 0.4),
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onSignOut();
                    },
                    icon: const Icon(
                      Icons.logout_rounded,
                      color: Color(0xFFFB7185),
                      size: 16,
                    ),
                    label: const Text(
                      'Çıkış Yap',
                      style: TextStyle(
                        color: Color(0xFFFB7185),
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      backgroundColor: const Color(
                        0xFFF43F5E,
                      ).withValues(alpha: 0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const Text(
                    'v2.4.0',
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Drawer Menü Öğesi Oluşturucu
  Widget _buildDrawerItem({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    Widget? badgeWidget,
    bool isActive = false,
    bool comingSoon = false,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isActive
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: isActive
            ? Border.all(color: const Color(0xFF6C5CE7).withValues(alpha: 0.3))
            : null,
      ),
      // Dimmed and inert rather than tappable-but-silent: a row that swallows
      // the tap without doing anything reads as a bug.
      child: Opacity(
        opacity: comingSoon ? 0.55 : 1,
        child: ListTile(
        onTap: comingSoon ? null : onTap,
        enabled: !comingSoon,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: iconColor),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
        ),
        trailing: comingSoon
            ? const _ComingSoonChip()
            : badgeWidget ??
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: Color(0xFF475569),
                  ),
        ),
      ),
    );
  }
}

class _ComingSoonChip extends StatelessWidget {
  const _ComingSoonChip();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Text(
      'Yakında',
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w800,
        color: Color(0xFF94A3B8),
      ),
    ),
  );
}

/// The bottom bar: four tabs with a compose button wedged in the middle.
///
/// The ➕ is not a tab — it opens the composer and leaves the current tab where
/// it was — so slot indices and page indices are deliberately different things.
class _FloatingNav extends StatelessWidget {
  const _FloatingNav({
    required this.pageIndex,
    required this.onSelectPage,
    required this.onCompose,
  });

  /// Which of the four pages is showing, not which of the five slots.
  final int pageIndex;
  final ValueChanged<int> onSelectPage;
  final VoidCallback onCompose;

  /// Slot → page. The centre slot has no page, hence the null.
  static const _pageForSlot = <int?>[0, 1, null, 2, 3];

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.home_outlined, Icons.home_rounded, 'Ana Sayfa'),
      (Icons.groups_outlined, Icons.groups_rounded, 'Akış'),
      (Icons.add_rounded, Icons.add_rounded, 'Paylaş'),
      (Icons.storefront_outlined, Icons.storefront_rounded, 'Çarşı'),
      (Icons.person_outline_rounded, Icons.person_rounded, 'Profil'),
    ];
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [
          BoxShadow(
            color: Color(0x220E0B18),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          for (var slot = 0; slot < items.length; slot++)
            Expanded(
              child: _pageForSlot[slot] == null
                  ? _ComposeButton(onTap: onCompose, label: items[slot].$3)
                  : _NavItem(
                      // Sekmenin adı ana sayfada da geçebiliyor (arama
                      // kutusundaki "Çarşı" rozeti gibi); testlerin sekmeyi
                      // metinden bulması bu yüzden güvenilir değil.
                      key: ValueKey('nav-${items[slot].$3}'),
                      icon: items[slot].$1,
                      activeIcon: items[slot].$2,
                      label: items[slot].$3,
                      selected: pageIndex == _pageForSlot[slot],
                      onTap: () => onSelectPage(_pageForSlot[slot]!),
                    ),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textMuted;
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(selected ? activeIcon : icon, color: color, size: 22),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposeButton extends StatelessWidget {
  const _ComposeButton({required this.onTap, required this.label});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF6355D8), Color(0xFF8B5CF6)],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: .35),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
        ),
      ),
    ),
  );
}
