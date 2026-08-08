import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/state/async_state.dart';
import '../../../community/application/profile_posts_controller.dart';
import '../../../community/application/story_controller.dart';
import '../../../community/domain/entities/community_post.dart';
import '../../application/profile_controller.dart';
import '../../domain/entities/user_profile.dart';
import '../../../verification/application/member_capabilities_controller.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.controller,
    required this.postsController,
    required this.onSignOut,
    required this.memberCapabilitiesController,
    required this.storyController,
  });
  final ProfileController controller;
  final ProfilePostsController postsController;
  final Future<void> Function() onSignOut;
  final MemberCapabilitiesController memberCapabilitiesController;
  final StoryController storyController;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController tabs = TabController(length: 3, vsync: this);
  @override
  void initState() {
    super.initState();
    widget.controller.load();
    widget.memberCapabilitiesController.load();
    widget.storyController.loadHighlights();
  }

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final s = widget.controller.state;
      if (s is! AsyncData<UserProfile>)
        return const Center(child: CircularProgressIndicator());
      final p = s.value;
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              ListTile(
                title: Text(
                  p.displayName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  '${p.originCity ?? 'Türkiye'} → ${p.city ?? ''}, ${p.state ?? ''}',
                ),
                trailing: IconButton(
                  tooltip: 'Güvenli çıkış',
                  icon: const Icon(
                    Icons.logout_rounded,
                    color: AppColors.primary,
                  ),
                  onPressed: _confirmSignOut,
                ),
              ),
              _VerifiedAccountCard(
                controller: widget.memberCapabilitiesController,
              ),
              _StoryHighlights(controller: widget.storyController),
              Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0EDF6),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TabBar(
                  controller: tabs,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: AppColors.textMuted,
                  tabs: const [
                    Tab(text: 'Paylaşımlar'),
                    Tab(text: 'Hakkında'),
                    Tab(text: 'Arkadaşlar'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: tabs,
                  children: [
                    _Posts(controller: widget.postsController, id: p.id),
                    _About(profile: p),
                    const _Friends(),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Future<void> _confirmSignOut() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Çıkış yapılsın mı?'),
        content: const Text(
          'Bu cihazdaki oturumun güvenli olarak kapatılacak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Çıkış yap'),
          ),
        ],
      ),
    );
    if (shouldSignOut != true || !mounted) return;
    await widget.onSignOut();
  }
}

class _StoryHighlights extends StatelessWidget {
  const _StoryHighlights({required this.controller});

  final StoryController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final highlights = controller.highlights;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Öne çıkanlar',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 9),
            SizedBox(
              height: 78,
              child: highlights.isEmpty
                  ? const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Henüz öne çıkarılmış bir Story yok.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: highlights.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, index) {
                        final highlight = highlights[index];
                        final first = highlight.items.first;
                        return SizedBox(
                          width: 68,
                          child: Column(
                            children: [
                              Container(
                                height: 51,
                                width: 51,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.primary,
                                    width: 2,
                                  ),
                                  image: DecorationImage(
                                    image: NetworkImage(
                                      first.media.thumbnailUrl ??
                                          first.media.url,
                                    ),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                highlight.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}

class _VerifiedAccountCard extends StatelessWidget {
  const _VerifiedAccountCard({required this.controller});

  final MemberCapabilitiesController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final verified = controller.value.identityVerified;
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: verified ? const Color(0xFFEAFBF3) : const Color(0xFFF5F3FF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: verified ? const Color(0xFF86E2B3) : const Color(0xFFD8CCFF),
          ),
        ),
        child: Row(
          children: [
            Icon(
              verified ? Icons.verified_rounded : Icons.verified_user_outlined,
              color: verified ? const Color(0xFF059669) : AppColors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                verified
                    ? 'Onaylı Hesap rozeti aktif'
                    : 'Onaylı Hesap rozeti gerekli',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            if (controller.isLoading)
              const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              TextButton(
                onPressed: verified
                    ? controller.load
                    : () => _startVerification(context),
                child: Text(verified ? 'Yenile' : 'Rozeti al'),
              ),
          ],
        ),
      );
    },
  );

  Future<void> _startVerification(BuildContext context) async {
    try {
      final url = await controller.startVerification();
      if (!context.mounted) return;
      final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Doğrulama sayfası açılamadı.')),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Doğrulama şu anda başlatılamadı. Lütfen tekrar deneyin.',
          ),
        ),
      );
    }
  }
}

class _Posts extends StatefulWidget {
  const _Posts({required this.controller, required this.id});
  final ProfilePostsController controller;
  final String id;
  @override
  State<_Posts> createState() => _PostsState();
}

class _PostsState extends State<_Posts> {
  @override
  void initState() {
    super.initState();
    widget.controller.load(widget.id);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final s = widget.controller.state;
      if (s is! AsyncData<List<CommunityPost>>)
        return const Center(child: CircularProgressIndicator());
      if (s.value.isEmpty)
        return const Center(child: Text('Henüz bir paylaşım yapılmadı'));
      return ListView(
        children: [
          for (final post in s.value)
            ListTile(title: Text(post.message), subtitle: Text(post.timeLabel)),
        ],
      );
    },
  );
}

class _About extends StatelessWidget {
  const _About({required this.profile});
  final UserProfile profile;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFEFF6FF), Color(0xFFEDE9FE)],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            const Icon(Icons.route_outlined, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${profile.originCity ?? 'Türkiye'} → ${profile.city ?? ''}, ${profile.state ?? ''}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      const Text(
        'Gurbet rozetleri',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var index = 0; index < profile.badges.length; index++) ...[
              _ProfileBadge(label: profile.badges[index]),
              if (index != profile.badges.length - 1) const SizedBox(width: 8),
            ],
          ],
        ),
      ),
      const SizedBox(height: 18),
      const Text(
        'Favori Türk mekanları',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      for (final p in profile.favoritePlaces)
        Container(
          margin: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(color: Color(0x0D100B18), blurRadius: 10),
            ],
          ),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFFFF1D8),
              child: Icon(Icons.restaurant, color: AppColors.accentAmber),
            ),
            title: Text(p),
            subtitle: const Text('Topluluk önerisi'),
          ),
        ),
    ],
  );
}

class _ProfileBadge extends StatelessWidget {
  const _ProfileBadge({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFF0E9FF),
      borderRadius: BorderRadius.circular(21),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.workspace_premium_outlined,
          size: 16,
          color: AppColors.primary,
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    ),
  );
}

class _Friends extends StatelessWidget {
  const _Friends();
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const Padding(
        padding: EdgeInsets.all(16),
        child: TextField(decoration: InputDecoration(hintText: 'Arkadaş ara')),
      ),
      for (final n in const ['Elif Demir', 'Mert Kaya', 'Zeynep Arslan'])
        ListTile(
          title: Text(n),
          trailing: TextButton(
            onPressed: () {},
            child: const Text('Mesaj gönder'),
          ),
        ),
    ],
  );
}
