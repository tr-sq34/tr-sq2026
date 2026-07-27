import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../community/application/community_feed_controller.dart';
import '../../../community/application/community_comments_controller.dart';
import '../../../community/application/profile_posts_controller.dart';
import '../../../community/application/media_upload_controller.dart';
import '../../../community/application/community_special_request_controller.dart';
import '../../../events/application/events_controller.dart';
import '../../../marketplace/application/marketplace_controller.dart';
import '../../../profile/application/profile_controller.dart';
import '../../../community/presentation/screens/community_screen.dart';
import '../../../events/presentation/screens/events_screen.dart';
import '../../../marketplace/presentation/screens/marketplace_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import 'discover_screen.dart';

class MainLayoutScreen extends StatefulWidget {
  const MainLayoutScreen({super.key, required this.communityController, required this.commentsController, required this.profilePostsController, required this.mediaUploadController, required this.specialRequestController, required this.eventsController, required this.marketplaceController, required this.profileController, required this.onSignOut});
  final CommunityFeedController communityController;
  final CommunityCommentsController commentsController;
  final ProfilePostsController profilePostsController;
  final MediaUploadController mediaUploadController;
  final CommunitySpecialRequestController specialRequestController;
  final EventsController eventsController;
  final MarketplaceController marketplaceController;
  final ProfileController profileController;
  final Future<void> Function() onSignOut;

  @override
  State<MainLayoutScreen> createState() => _MainLayoutScreenState();
}

class _MainLayoutScreenState extends State<MainLayoutScreen> {
  var _currentIndex = 0;

  late List<Widget> _pages;

  List<Widget> _buildPages() => [
        const DiscoverScreen(),
        CommunityScreen(
          controller: widget.communityController,
          commentsController: widget.commentsController,
          mediaUploadController: widget.mediaUploadController,
          specialRequestController: widget.specialRequestController,
        ),
        EventsScreen(controller: widget.eventsController),
        MarketplaceScreen(controller: widget.marketplaceController),
        ProfileScreen(
          controller: widget.profileController,
          postsController: widget.profilePostsController,
          onSignOut: widget.onSignOut,
        ),
      ];

  @override
  void initState() {
    super.initState();
    _pages = _buildPages();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(children: [
        SafeArea(child: Padding(padding: const EdgeInsets.only(bottom: 84), child: IndexedStack(index: _currentIndex, children: _pages))),
        Positioned(left: 18, right: 18, bottom: 16, child: _FloatingNav(index: _currentIndex, onSelected: (index) {
          debugPrint('DEBUG [Navigation]: Tab değiştirildi -> Index: $index');
          setState(() => _currentIndex = index);
        })),
      ]),
    );
  }
}

class _FloatingNav extends StatelessWidget {
  const _FloatingNav({required this.index, required this.onSelected});
  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const items = [(Icons.home_outlined, Icons.home_rounded, 'Ana Sayfa'), (Icons.groups_outlined, Icons.groups_rounded, 'Akış'), (Icons.calendar_month_outlined, Icons.calendar_month_rounded, 'Etkinlik'), (Icons.storefront_outlined, Icons.storefront_rounded, 'Çarşı'), (Icons.person_outline_rounded, Icons.person_rounded, 'Profil')];
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .96), borderRadius: BorderRadius.circular(32), boxShadow: const [BoxShadow(color: Color(0x220E0B18), blurRadius: 24, offset: Offset(0, 10))]),
      child: Row(children: [for (var i = 0; i < items.length; i++) Expanded(child: InkWell(borderRadius: BorderRadius.circular(24), onTap: () => onSelected(i), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(index == i ? items[i].$2 : items[i].$1, color: index == i ? AppColors.primary : AppColors.textMuted, size: 22), const SizedBox(height: 3), Text(items[i].$3, style: TextStyle(color: index == i ? AppColors.primary : AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w700))])))]),
    );
  }
}
