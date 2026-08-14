import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import '../../../../core/widgets/app_remote_image.dart';
import '../../application/community_home_controller.dart';
import '../../data/community_home_repository.dart';
import '../../../community/application/story_controller.dart';
import '../../../community/domain/entities/feed_extensions.dart';
import '../../../forum/application/forum_controller.dart';
import '../../../forum/domain/entities/forum.dart';
import '../../../forum/presentation/widgets/forum_trending_section.dart';
import '../../../marketplace/application/marketplace_controller.dart';
import '../../../marketplace/domain/entities/marketplace_listing.dart';
import '../../../news/application/news_controller.dart';
import '../../../news/domain/entities/news_article.dart';
import '../../../news/presentation/widgets/headline_strip.dart';
import '../../../promotions/application/promotions_controller.dart';
import '../../../promotions/domain/entities/promotion.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({
    super.key,
    required this.controller,
    required this.onOpenBadges,
    required this.newsController,
    required this.onOpenArticle,
    required this.onOpenNewsCenter,
    required this.storyController,
    required this.promotionsController,
    required this.marketplaceController,
    required this.onOpenStory,
    required this.onOpenPromotion,
    required this.onOpenMarketplace,
    required this.forumController,
    required this.onOpenForum,
    required this.onOpenForumTopic,
  });

  final CommunityHomeController controller;

  /// The badge card's destination is owned by the shell; this screen only
  /// calls it.
  final VoidCallback onOpenBadges;

  /// The headline strip and the Haber Merkezi read this same controller, so a
  /// headline can never say something the article behind it does not.
  final NewsController newsController;
  final ValueChanged<NewsArticle> onOpenArticle;
  final VoidCallback onOpenNewsCenter;

  /// The rail shows the member's own network, exactly as the feed's rail does.
  /// One controller, two surfaces: a Story marked read here is read there too.
  final StoryController storyController;

  /// The sponsored slot at the head of the rail and the "Sana Özel Öne
  /// Çıkanlar" cards; both are promotions, told apart by their placement.
  final PromotionsController promotionsController;

  /// The listings strip reads the same repository the Çarşı tab does, so the
  /// home screen can never advertise something the marketplace has not got.
  final MarketplaceController marketplaceController;

  /// Menüdeki Forum ekranıyla aynı denetleyici: şeritten açılan konu,
  /// listede de aynı sayaçlarla duruyor.
  final ForumController forumController;
  final ValueChanged<String?> onOpenForum;
  final ValueChanged<ForumTopic> onOpenForumTopic;

  final ValueChanged<StoryItem> onOpenStory;
  final ValueChanged<Promotion> onOpenPromotion;
  final VoidCallback onOpenMarketplace;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.load();
    widget.newsController.loadHeadlines();
    // Both are shared with other tabs and both guard against a second call in
    // flight, so asking here costs nothing when the member opened the feed
    // first.
    widget.storyController.load();
    widget.promotionsController.loadActive();
    widget.marketplaceController.load();
    widget.forumController.loadCategories();
    widget.forumController.loadTrending();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (_, _) {
      final summary = widget.controller.summary;
      return ScrollConfiguration(
        behavior: const _HomeScrollBehavior(),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // The greeting, location and the menu/bell buttons moved to the
            // shell's AppTopBar: they belong to every tab, not just this one.
            if (summary?.isNewMember == true)
              _NewMemberWelcome(city: summary?.city),
            _StoriesSection(
              storyController: widget.storyController,
              promotionsController: widget.promotionsController,
              onOpenStory: widget.onOpenStory,
              onOpenPromotion: widget.onOpenPromotion,
            ),
            _CommunityPulse(
              summary: summary,
              onOpenMarketplace: widget.onOpenMarketplace,
            ),
            const SizedBox(height: 20),
            _HighlightsSection(
              onOpenBadges: widget.onOpenBadges,
              promotionsController: widget.promotionsController,
              onOpenPromotion: widget.onOpenPromotion,
            ),
            // Burada "⚡ Canlı İhale & Satış" diye bir bölüm vardı: yanıp sönen
            // bir canlı işareti, "Yana Kaydırın (1/4)" yazısı ve iki kart.
            // Kartlardaki her şey koda elle yazılmıştı: aynı çay takımı, aynı
            // satıcı, aynı "12 Teklif", aynı fiyat. Böyle bir ihale hiç var
            // olmadı; "Teklif Ver" düğmesi de boştu. Sunucuda ihaleleri
            // listeleyen bir uç nokta yok, uygulamada ihale açan bir ekran yok.
            // İhale gerçekten yapıldığında bölüm de gerçek verisiyle döner.
            const _LocalContextSection(),
            HeadlineStrip(
              controller: widget.newsController,
              onOpenArticle: widget.onOpenArticle,
              onOpenNewsCenter: widget.onOpenNewsCenter,
            ),
            ForumTrendingSection(
              controller: widget.forumController,
              onOpenForum: widget.onOpenForum,
              onOpenTopic: widget.onOpenForumTopic,
            ),
            _RecentListingsSection(
              controller: widget.marketplaceController,
              onOpenMarketplace: widget.onOpenMarketplace,
            ),
            const SizedBox(height: 100),
          ],
        ),
      );
    },
  );
}

/// Gösterim sayacı çizim sırasında değil, kare bittikten sonra işlenir: build
/// içinden denetleyiciye yazmak, aynı karede yeniden çizim istemek olurdu.
/// Denetleyici zaten oturum başına tek gösterim sayar.
void _countImpressions(
  PromotionsController controller,
  Iterable<Promotion> shown,
) {
  if (shown.isEmpty) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    for (final promotion in shown) {
      controller.recordImpression(promotion.id);
    }
  });
}

class _NewMemberWelcome extends StatelessWidget {
  const _NewMemberWelcome({this.city});
  final String? city;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(20, 12, 20, 4),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFF4F1FF),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'TurkSquare’a hoş geldin',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 6),
        Text(
          city == null
              ? 'İlk bağlantılarını kurarak topluluğu keşfetmeye başlayabilirsin.'
              : '$city çevresindeki topluluğu keşfet, ilk paylaşımını yap ve bağlantı kur.',
          style: const TextStyle(color: Color(0xFF64748B), height: 1.35),
        ),
      ],
    ),
  );
}

class _HomeScrollBehavior extends MaterialScrollBehavior {
  const _HomeScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
  };
}

// 2. Stories Section
///
/// Şeridin başında yayındaki sponsorlu yuvalar, ardından üyenin kendi ağındaki
/// Story'ler durur. İkisi de gerçek: hiçbiri yoksa şerit hiç çizilmez, çünkü
/// boş bir Story rayını dolduracak tek şey örnek kullanıcı olurdu.
class _StoriesSection extends StatelessWidget {
  const _StoriesSection({
    required this.storyController,
    required this.promotionsController,
    required this.onOpenStory,
    required this.onOpenPromotion,
  });

  final StoryController storyController;
  final PromotionsController promotionsController;
  final ValueChanged<StoryItem> onOpenStory;
  final ValueChanged<Promotion> onOpenPromotion;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([storyController, promotionsController]),
    builder: (context, _) {
      final sponsored = promotionsController.storySlots;
      final stories = storyController.railItems;
      if (sponsored.isEmpty && stories.isEmpty) return const SizedBox.shrink();
      _countImpressions(promotionsController, sponsored);
      return Container(
        color: Colors.white,
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                'STORY’LER',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF94A3B8),
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final promotion in sponsored)
                    _StoryItem(
                      name: promotion.title,
                      imageUrl: promotion.imageUrl ?? '',
                      isSponsored: true,
                      onTap: () => onOpenPromotion(promotion),
                    ),
                  for (final story in stories)
                    _StoryItem(
                      name: story.authorName,
                      imageUrl: story.media.thumbnailUrl ?? story.media.url,
                      // Okunmuş Story'nin halkası soluk: hangisine bakılmadığı
                      // rayın tek işe yarar bilgisi.
                      isUnread: !story.isViewed,
                      onTap: () => onOpenStory(story),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _StoryItem extends StatelessWidget {
  const _StoryItem({
    required this.name,
    required this.imageUrl,
    required this.onTap,
    this.isSponsored = false,
    this.isUnread = true,
  });
  final String name;
  final String imageUrl;
  final VoidCallback onTap;
  final bool isSponsored;
  final bool isUnread;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: isUnread
                    ? LinearGradient(
                        colors: isSponsored
                            ? const [Color(0xFF6355D8), Color(0xFF3B3383)]
                            : const [
                                Color(0xFFFBBF24),
                                Color(0xFFF43F5E),
                                Color(0xFF6355D8),
                              ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isUnread ? null : const Color(0xFFE2E8F0),
              ),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: ClipOval(
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: AppRemoteImage(
                      imageUrl: imageUrl,
                      semanticLabel: isSponsored
                          ? '$name tanıtımı'
                          : '$name hikayesi',
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              isSponsored ? 'Sponsorlu' : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isSponsored
                    ? const Color(0xFF6355D8)
                    : const Color(0xFF334155),
              ),
            ),
            if (isSponsored)
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF94A3B8),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

// 3. Community Pulse (Dark Section)
///
/// Buradaki her sayı `/community/home/summary`den gelir. Özet yüklenmeden ya da
/// alınamadan sayaç satırı hiç çizilmez: uydurulmuş bir "8 aktif ilan", boş
/// bırakılmış bir satırdan çok daha kötüdür.
class _CommunityPulse extends StatelessWidget {
  const _CommunityPulse({required this.summary, required this.onOpenMarketplace});

  final CommunityHomeSummary? summary;
  final VoidCallback onOpenMarketplace;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0F172A), Color(0xFF1E1A47), Color(0xFF0F172A)],
      ),
      border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
    ),
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.5),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'GÜNÜN TOPLULUK NABZI',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF10B981),
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on_rounded,
                    size: 10,
                    color: Color(0xFFF43F5E),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    // Konumunu vermemiş üyeye başkasının şehrini göstermek
                    // yerine ülke geneli deniyor.
                    summary?.city ?? 'Amerika geneli',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Arama kutusu bir görsel değil, Çarşı'nın arama alanına açılan kapı.
        Material(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onOpenMarketplace,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.search_rounded,
                    color: Color(0xFF6355D8),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Ev, iş veya eşya ara...',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6355D8).withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Çarşı',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (summary case final value?) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _PulseStat(
                  icon: Icons.group_rounded,
                  iconColor: const Color(0xFF6355D8),
                  value: '${value.connections}',
                  label: 'Bağlantın',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PulseStat(
                  icon: Icons.forum_rounded,
                  iconColor: const Color(0xFFFBBF24),
                  value: '${value.localPosts}',
                  label: 'Çevrende paylaşım',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PulseStat(
                  icon: Icons.auto_awesome_rounded,
                  iconColor: const Color(0xFF10B981),
                  value: '${value.activeStories}',
                  label: 'Aktif Story',
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

class _PulseStat extends StatelessWidget {
  const _PulseStat({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
    ),
    child: Column(
      children: [
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}

// 4. Highlights Section
///
/// Rozet kartı her zaman durur — o üyenin kendi ilerlemesi. Geri kalanı
/// panelden yerleştirilmiş `featured_card` tanıtımlarıdır; bu alan editoryal,
/// üye buraya kendi talebiyle giremez.
class _HighlightsSection extends StatelessWidget {
  const _HighlightsSection({
    required this.onOpenBadges,
    required this.promotionsController,
    required this.onOpenPromotion,
  });

  final VoidCallback onOpenBadges;
  final PromotionsController promotionsController;
  final ValueChanged<Promotion> onOpenPromotion;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: promotionsController,
    builder: (context, _) {
      final cards = promotionsController.featuredCards;
      _countImpressions(promotionsController, cards);
      return Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sana Özel Öne Çıkanlar',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    'Bulunduğun yere göre seçilen kartlar',
                    style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 130,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _HighlightCard(
                  title: 'Topluluk Rozetini Al!',
                  subtitle: 'Rozetini tamamla, öne çık.',
                  badge: 'Güvenli Profil',
                  gradient: const [Color(0xFF1E1A47), Color(0xFF3B3383)],
                  onTap: onOpenBadges,
                ),
                for (final promotion in cards)
                  _HighlightCard(
                    title: promotion.title,
                    subtitle: promotion.subtitle ?? promotion.audienceLabel,
                    badge: 'Sponsorlu',
                    imageUrl: promotion.imageUrl,
                    gradient: const [Color(0xFF334155), Color(0xFF0F172A)],
                    onTap: () => onOpenPromotion(promotion),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({
    required this.title,
    required this.subtitle,
    required this.badge,
    this.imageUrl,
    this.gradient,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final String badge;
  final String? imageUrl;
  final List<Color>? gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Container(
      width: 260,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: gradient != null
            ? LinearGradient(
                colors: gradient!,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        image: imageUrl != null
            ? DecorationImage(
                image: NetworkImage(imageUrl!),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withValues(alpha: 0.4),
                  BlendMode.darken,
                ),
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // The badge gives way rather than overflow: the card is a fixed
                // width, and a long badge at a large system text scale would
                // otherwise run off its own edge.
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      badge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

// 6. Local Context & News
class _LocalContextSection extends StatelessWidget {
  const _LocalContextSection();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Çevrende neler oluyor?',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'New York ve çevresindeki Türk topluluğundan gelişmeler',
          style: TextStyle(
            fontSize: 11,
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.calendar_month_rounded,
                  size: 14,
                  color: Color(0xFF6355D8),
                ),
                SizedBox(width: 8),
                Text(
                  'YAKLAŞAN ETKİNLİKLER',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF334155),
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
            Text(
              'Tümünü gör',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF6355D8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 145,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            children: const [
              _EventCard(
                title: 'Türk Pikniği 2026',
                location: 'Central Park · NYC',
                date: 'Bu Cumartesi',
                imageUrl:
                    'https://images.unsplash.com/photo-1517457373958-b7bdd4587205?auto=format&fit=crop&w=400&q=80',
              ),
              _EventCard(
                title: 'Anadolu Caz Gecesi',
                location: 'Brooklyn · NYC',
                date: 'Pazar',
                imageUrl:
                    'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&w=400&q=80',
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.title,
    required this.location,
    required this.date,
    required this.imageUrl,
  });
  final String title;
  final String location;
  final String date;
  final String imageUrl;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 12),
    child: Container(
      width: 190,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              SizedBox(
                height: 90,
                width: double.infinity,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Container(color: const Color(0xFFF1F5F9)),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Text(
                    date,
                    style: const TextStyle(
                      color: Color(0xFF6355D8),
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Color(0xFF0F172A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      size: 10,
                      color: Color(0xFFF43F5E),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        location,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

// 8. Recent Listings
///
/// Çarşı sekmesiyle aynı denetleyiciyi okur: ana sayfa, çarşıda olmayan bir
/// ilanı hiçbir zaman gösteremez. İlan yoksa şerit hiç çizilmez.
class _RecentListingsSection extends StatelessWidget {
  const _RecentListingsSection({
    required this.controller,
    required this.onOpenMarketplace,
  });

  final MarketplaceController controller;
  final VoidCallback onOpenMarketplace;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final listings = controller.items.take(6).toList(growable: false);
      if (listings.isEmpty) return const SizedBox.shrink();
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
                      Icons.local_offer_rounded,
                      size: 14,
                      color: Color(0xFF10B981),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'SON EKLENEN İLANLAR',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF334155),
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: onOpenMarketplace,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Çarşıya Git >',
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
              height: 190,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                itemCount: listings.length,
                itemBuilder: (_, index) => _RecentListingCard(
                  listing: listings[index],
                  onTap: onOpenMarketplace,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _RecentListingCard extends StatelessWidget {
  const _RecentListingCard({required this.listing, required this.onTap});
  final MarketplaceListing listing;
  final VoidCallback onTap;

  /// "$1,450" — binlik ayracı elle konuyor; intl paketi bu ekran için tek
  /// başına bağımlılık olurdu.
  String get _price {
    final whole = listing.price.round().toString();
    final buffer = StringBuffer();
    for (var index = 0; index < whole.length; index++) {
      if (index > 0 && (whole.length - index) % 3 == 0) buffer.write(',');
      buffer.write(whole[index]);
    }
    return '\$$buffer';
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 12),
    child: Container(
      width: 175,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  SizedBox(
                    height: 110,
                    width: double.infinity,
                    child: AppRemoteImage(
                      imageUrl: listing.imageUrl,
                      semanticLabel: listing.title,
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        listing.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: Color(0xFF1E293B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _price,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: Color(0xFF1E1A47),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Yıldızlı puan burada yoktu ve ilanın da böyle bir
                        // alanı yok; yerinde ilanın kendi durumu duruyor.
                        Expanded(
                          child: Text(
                            listing.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          listing.condition,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
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
    ),
  );
}
