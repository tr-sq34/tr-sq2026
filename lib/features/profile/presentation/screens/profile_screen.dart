import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/state/async_state.dart';
import '../../../community/application/profile_posts_controller.dart';
import '../../../community/domain/entities/community_post.dart';
import '../../application/profile_controller.dart';
import '../../domain/entities/user_profile.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.controller,
    required this.postsController,
    required this.onSignOut,
  });
  final ProfileController controller;
  final ProfilePostsController postsController;
  final Future<void> Function() onSignOut;
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
        content: const Text('Bu cihazdaki oturumun güvenli olarak kapatılacak.'),
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
