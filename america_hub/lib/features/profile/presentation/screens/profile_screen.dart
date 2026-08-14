import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/state/async_state.dart';
import '../../../../core/widgets/app_image_source.dart';
import '../../../community/application/media_upload_controller.dart';
import '../../../community/application/story_controller.dart';
import '../../../community/domain/entities/community_post.dart';
import '../../../community/domain/entities/post_media_upload.dart';
import '../../../community/domain/repositories/community_repository.dart';
import '../../../journey/application/journey_controller.dart';
import '../../../journey/domain/entities/journey.dart';
import '../../../journey/presentation/screens/journey_screen.dart';
import '../../../verification/application/member_capabilities_controller.dart';
import '../../application/friendship_controller.dart';
import '../../application/profile_controller.dart';
import '../../domain/entities/friendship.dart';
import '../../domain/entities/user_profile.dart';
import '../widgets/profile_badge_chip.dart';

/// The member's identity in America.
///
/// Tab order is Profil → Paylaşımlar → Arkadaşlar: who this person is comes
/// before what they posted. Nothing on this screen is invented — a member with
/// no bio, no badges and no posts sees empty states with a way out of them, not
/// placeholder names.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.controller,
    required this.friendshipController,
    required this.journeyController,
    required this.onSignOut,
    required this.memberCapabilitiesController,
    required this.storyController,
    required this.mediaUploadController,
    required this.postCommands,
  });

  final ProfileController controller;
  final FriendshipController friendshipController;
  final JourneyController journeyController;
  final Future<void> Function() onSignOut;
  final MemberCapabilitiesController memberCapabilitiesController;
  final StoryController storyController;
  final MediaUploadController mediaUploadController;
  final CommunityPostCommands postCommands;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final _picker = ImagePicker();
  bool _showArchive = false;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    widget.controller.load();
    widget.journeyController.load();
    widget.memberCapabilitiesController.load();
    widget.storyController.loadHighlights();
    widget.friendshipController.load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final state = widget.controller.state;
      if (state is AsyncFailure<UserProfile>) {
        return _ErrorState(message: state.message, onRetry: widget.controller.load);
      }
      if (state is! AsyncData<UserProfile>) {
        return const Center(child: CircularProgressIndicator());
      }
      final profile = state.value;
      return Scaffold(
        backgroundColor: AppColors.background,
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(child: _Header(
              profile: profile,
              journeyController: widget.journeyController,
              uploadingAvatar: _uploadingAvatar,
              onTapAvatar: profile.isSelf ? _changeAvatar : null,
              onEditBio: profile.isSelf ? () => _editBio(profile) : null,
              onOpenJourney: () => _openJourney(),
              onOpenBadges: () => _openJourney(tab: JourneyTab.badges),
              onSignOut: profile.isSelf ? _confirmSignOut : null,
            )),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarHeader(tabs: _tabs),
            ),
          ],
          body: TabBarView(
            controller: _tabs,
            children: [
              _AboutTab(
                profile: profile,
                capabilities: widget.memberCapabilitiesController,
                story: widget.storyController,
              ),
              _PostsTab(
                controller: widget.controller,
                profile: profile,
                showArchive: _showArchive,
                onToggleArchive: (value) {
                  setState(() => _showArchive = value);
                  if (value) widget.controller.loadArchived(profile.id);
                },
                onDelete: _deletePost,
              ),
              _FriendsTab(
                profile: profile,
                controller: widget.friendshipController,
                // Kabul edilen istek başlıktaki arkadaş sayısını da
                // değiştiriyor; listede 3, başlıkta 2 yazmasın diye.
                onFriendsChanged: widget.controller.load,
              ),
            ],
          ),
        ),
      );
    },
  );

  void _openJourney({JourneyTab tab = JourneyTab.tasks}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => JourneyScreen(
            controller: widget.journeyController,
            initialTab: tab,
          ),
        ),
      );

  Future<void> _editBio(UserProfile profile) async {
    final controller = TextEditingController(text: profile.bio);
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(sheetContext).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Kendinden bahset', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 4,
              maxLength: 280,
              decoration: const InputDecoration(
                hintText: 'Nereden geldin, burada ne yapıyorsun, neye meraklısın?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => Navigator.pop(sheetContext, controller.text),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    if (saved != null) await widget.controller.updateBio(saved);
  }

  /// Tap the avatar to change it. The image travels the same quarantine-and-scan
  /// path as every other upload; the profile only stores the id once the media
  /// pipeline says the file is ready.
  Future<void> _changeAvatar() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galeriden seç'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Fotoğraf çek'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final image = await _picker.pickImage(source: source, imageQuality: 92);
    if (image == null) return;
    final bytes = await image.readAsBytes();
    final localId = '${DateTime.now().microsecondsSinceEpoch}-${image.name}';
    // Uploading and saving take a moment each. Without a sign that anything is
    // happening the member taps, waits, sees the old circle and concludes the
    // feature is broken.
    if (mounted) setState(() => _uploadingAvatar = true);
    try {
      await widget.mediaUploadController.upload(
        MediaUploadRequest(
          localUri: image.path,
          media: PostMediaUpload(
            localId: localId,
            type: PostMediaType.image,
            fileName: image.name,
            mimeType: image.mimeType ?? 'image/jpeg',
            sizeBytes: bytes.lengthInBytes,
          ),
        ),
      );
      final uploaded = widget.mediaUploadController.progressById[localId]?.media;
      // The composer reads `readyMedia` off the same controller, so an avatar
      // left behind here would ride along on the member's next post.
      widget.mediaUploadController.remove(localId);
      if (uploaded == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fotoğraf yüklenemedi. Tekrar dene.')),
        );
        return;
      }
      await widget.controller.updateAvatar(uploaded.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil fotoğrafın güncellendi.')),
      );
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _deletePost(ProfilePost post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Paylaşım silinsin mi?'),
        content: const Text('Bu geri alınamaz. Saklamak istersen arşivleyebilirsin.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Sil')),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.postCommands.deletePost(post.id);
    final state = widget.controller.state;
    if (state is AsyncData<UserProfile>) await widget.controller.loadPosts(state.value.id);
  }

  Future<void> _confirmSignOut() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Çıkış yapılsın mı?'),
        content: const Text('Bu cihazdaki oturumun güvenli olarak kapatılacak.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Çıkış yap')),
        ],
      ),
    );
    if (shouldSignOut != true || !mounted) return;
    await widget.onSignOut();
  }
}

/// Name, photo, counters and the journey strip in one compact block.
///
/// It is deliberately short. Everything that used to sit here in its own padded
/// card now lives as a single row further down: the header's job is to say who
/// this is, not to fill a screen.
class _Header extends StatelessWidget {
  const _Header({
    required this.profile,
    required this.journeyController,
    required this.onOpenJourney,
    required this.onOpenBadges,
    this.uploadingAvatar = false,
    this.onTapAvatar,
    this.onEditBio,
    this.onSignOut,
  });

  final UserProfile profile;
  final JourneyController journeyController;
  final bool uploadingAvatar;
  final VoidCallback onOpenJourney;
  final VoidCallback onOpenBadges;
  final VoidCallback? onTapAvatar;
  final VoidCallback? onEditBio;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppColors.profileTint, AppColors.background],
      ),
    ),
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Avatar(profile: profile, onTap: onTapAvatar, uploading: uploadingAvatar),
            const SizedBox(width: 14),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _Stat(value: profile.postCount, label: 'Paylaşım')),
                  Expanded(child: _Stat(value: profile.friendCount, label: 'Arkadaş')),
                  // The badge cabinet lives on the journey screen, so the
                  // counter that names it is the way in.
                  Expanded(
                    child: _Stat(
                      value: profile.badgeCount,
                      label: 'Rozet',
                      onTap: onOpenBadges,
                    ),
                  ),
                ],
              ),
            ),
            if (onSignOut != null)
              IconButton(
                tooltip: 'Güvenli çıkış',
                icon: const Icon(Icons.logout_rounded, color: AppColors.profileAccent),
                onPressed: onSignOut,
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Flexible(
              child: Text(
                profile.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
            ),
            if (profile.identityVerified) ...[
              const SizedBox(width: 6),
              const Icon(Icons.verified_rounded, size: 18, color: Color(0xFF2F6FED)),
            ],
          ],
        ),
        if (profile.journeyLine != null) ...[
          const SizedBox(height: 2),
          Text(
            profile.journeyLine!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
        const SizedBox(height: 6),
        _Bio(profile: profile, onEdit: onEditBio),
        const SizedBox(height: 12),
        _JourneyCard(controller: journeyController, onTap: onOpenJourney),
        if (profile.showcasedBadges.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final badge in profile.showcasedBadges)
                ProfileBadgeChip(title: badge.title, tier: badge.tier),
            ],
          ),
        ],
        const SizedBox(height: 10),
      ],
    ),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.profile, this.onTap, this.uploading = false});

  final UserProfile profile;
  final VoidCallback? onTap;
  final bool uploading;

  static const _size = 64.0;

  @override
  Widget build(BuildContext context) {
    final image = appImageProvider(profile.avatarUrl);
    // Initials until there is a photo, and again if the photo will not load. A
    // stock face would tell the member the app already knows what they look
    // like; a silently blank circle tells them their upload failed.
    final initials = Text(
      _initials(profile.displayName),
      style: const TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w800,
        color: AppColors.profileAccent,
      ),
    );
    return Semantics(
      button: onTap != null,
      label: onTap != null ? 'Profil fotoğrafını değiştir' : 'Profil fotoğrafı',
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          children: [
            Container(
              height: _size,
              width: _size,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.profileTint,
                border: Border.all(color: AppColors.profileBorder, width: 2),
              ),
              alignment: Alignment.center,
              child: uploading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : image == null
                      ? initials
                      : Image(
                          image: image,
                          height: _size,
                          width: _size,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stack) =>
                              Center(child: initials),
                        ),
            ),
            if (onTap != null && !uploading)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.profileAccent,
                  ),
                  child: const Icon(Icons.photo_camera_rounded, size: 13, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.onTap});

  final int value;
  final String label;
  final VoidCallback? onTap;

  // Long labels shrink rather than clip: at a large text scale "Paylaşım" is
  // wider than a third of the header, and a truncated count means nothing.
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Text('$value', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: onTap == null ? AppColors.textSecondary : AppColors.profileAccent,
                fontWeight: onTap == null ? FontWeight.w400 : FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Bio extends StatelessWidget {
  const _Bio({required this.profile, this.onEdit});

  final UserProfile profile;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    if (profile.bio.isNotEmpty) {
      return GestureDetector(
        onTap: onEdit,
        child: Text(profile.bio, style: const TextStyle(height: 1.35)),
      );
    }
    if (onEdit == null) return const SizedBox.shrink();
    return TextButton.icon(
      onPressed: onEdit,
      style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
      icon: const Icon(Icons.edit_note_rounded, size: 18),
      label: const Text('Kendinden bahset'),
    );
  }
}

/// The Gurbet Yolculuğu strip: level, progress to the next one, and the single
/// next task. Tapping it opens the full map.
class _JourneyCard extends StatelessWidget {
  const _JourneyCard({required this.controller, required this.onTap});

  final JourneyController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final state = controller.journey;
      final snapshot = state is AsyncData<JourneySnapshot> ? state.value : null;
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.profileBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.explore_rounded, size: 18, color: AppColors.profileAccent),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Gurbet Yolculuğu', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  if (snapshot != null)
                    Text('${snapshot.points} XP',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                ],
              ),
              const SizedBox(height: 10),
              if (snapshot == null)
                const LinearProgressIndicator(minHeight: 6)
              else ...[
                Text('Sv.${snapshot.level} · ${snapshot.levelTitle}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: snapshot.progress,
                    minHeight: 7,
                    backgroundColor: AppColors.profileTint,
                    valueColor: const AlwaysStoppedAnimation(AppColors.profileAccent),
                  ),
                ),
                if (snapshot.nextTask != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Sıradaki: ${snapshot.nextTask!.title} '
                    '(${snapshot.nextTask!.current}/${snapshot.nextTask!.target})',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _TabBarHeader extends SliverPersistentHeaderDelegate {
  _TabBarHeader({required this.tabs});

  final TabController tabs;

  static const double _extent = 62;

  @override
  double get minExtent => _extent;
  @override
  double get maxExtent => _extent;

  // The sliver hands the child a loose height constraint, so the row has to be
  // pinned to the declared extent — a TabBar that measures shorter than
  // `maxExtent` trips the sliver geometry assertion.
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(
    height: _extent,
    color: AppColors.background,
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Container(
      decoration: BoxDecoration(
        color: AppColors.profileTint,
        borderRadius: BorderRadius.circular(24),
      ),
      child: TabBar(
        controller: tabs,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: AppColors.profileAccent,
          borderRadius: BorderRadius.circular(22),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        tabs: const [
          Tab(text: 'Profil'),
          Tab(text: 'Paylaşımlar'),
          Tab(text: 'Arkadaşlar'),
        ],
      ),
    ),
  );

  @override
  bool shouldRebuild(_TabBarHeader oldDelegate) => oldDelegate.tabs != tabs;
}

class _AboutTab extends StatelessWidget {
  const _AboutTab({
    required this.profile,
    required this.capabilities,
    required this.story,
  });

  final UserProfile profile;
  final MemberCapabilitiesController capabilities;
  final StoryController story;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
    children: [
      // One line per fact, separated by a hairline. Each of these used to be a
      // padded card of its own, which turned "Nereden geldin" — three words of
      // answer — into a sixth of the screen.
      _InfoGroup(
        rows: [
          _InfoRow(
            icon: Icons.place_outlined,
            label: 'Nerelisin',
            value: profile.originCity != null
                ? profile.journeyLine!
                : profile.bornInUs
                    ? 'Amerika doğumlu'
                    // The prompt only appears for the member themselves, and it
                    // sends them to onboarding rather than editing here: the
                    // answer belongs to identity, and two writers would fight
                    // over it.
                    : profile.isSelf
                        ? 'Eklenmedi · kurulum ekranından ekleyebilirsin'
                        : 'Belirtilmemiş',
            muted: profile.originCity == null && !profile.bornInUs,
          ),
          if (profile.arrivedYear != null)
            _InfoRow(
              icon: Icons.flight_land_outlined,
              label: 'Geliş',
              value: _arrival(profile),
            ),
          if (profile.interests.isNotEmpty)
            _InfoRow(
              icon: Icons.interests_outlined,
              label: 'İlgi alanları',
              // A chip pile wrapped onto three rows for six words. The same
              // words on one line say exactly as much.
              value: profile.interests.join(', '),
            ),
        ],
      ),
      const SizedBox(height: 12),
      _VerifiedAccountRow(controller: capabilities),
      _StoryHighlights(controller: story),
    ],
  );

  static String _arrival(UserProfile profile) {
    const months = [
      'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
      'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
    ];
    final year = profile.arrivedYear!;
    final month = profile.arrivedMonth;
    final label = month != null && month >= 1 && month <= 12
        ? '${months[month - 1]} $year'
        : '$year';
    final years = DateTime.now().year - year;
    return years <= 0 ? '$label\'dan beri burada' : '$label · $years yıldır burada';
  }
}

/// One surface holding the facts, hairline-separated. A single border around
/// the group instead of one around every line.
class _InfoGroup extends StatelessWidget {
  const _InfoGroup({required this.rows});

  final List<_InfoRow> rows;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.profileBorder),
    ),
    child: Column(
      children: [
        for (var index = 0; index < rows.length; index++) ...[
          if (index > 0)
            const Divider(height: 1, thickness: 1, indent: 44, color: AppColors.profileBorder),
          rows[index],
        ],
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.muted = false,
  });

  final IconData icon;
  final String label;
  final String value;

  /// Set when the value is an absence rather than an answer, so a missing fact
  /// does not read with the same weight as a given one.
  final bool muted;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.profileAccent),
        const SizedBox(width: 12),
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              height: 1.3,
              fontWeight: muted ? FontWeight.w400 : FontWeight.w600,
              color: muted ? AppColors.textMuted : null,
            ),
          ),
        ),
      ],
    ),
  );
}

class _PostsTab extends StatelessWidget {
  const _PostsTab({
    required this.controller,
    required this.profile,
    required this.showArchive,
    required this.onToggleArchive,
    required this.onDelete,
  });

  final ProfileController controller;
  final UserProfile profile;
  final bool showArchive;
  final ValueChanged<bool> onToggleArchive;
  final Future<void> Function(ProfilePost) onDelete;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final state = showArchive ? controller.archived : controller.posts;
      return Column(
        children: [
          if (profile.isSelf)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: _ArchiveSwitch(
                showArchive: showArchive,
                onChanged: onToggleArchive,
              ),
            ),
          Expanded(
            child: switch (state) {
              AsyncFailure<List<ProfilePost>>(:final message) => Center(child: Text(message)),
              AsyncData<List<ProfilePost>>(:final value) when value.isEmpty => Center(
                child: Text(
                  showArchive
                      ? 'Arşivde bir şey yok.'
                      : profile.isSelf
                          ? 'İlk paylaşımını yap.'
                          : 'Henüz bir paylaşım yok.',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
              AsyncData<List<ProfilePost>>(:final value) => GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                itemCount: value.length,
                itemBuilder: (context, index) => _PostTile(
                  post: value[index],
                  enabled: profile.isSelf,
                  onLongPress: () => _showActions(context, value[index]),
                ),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      );
    },
  );

  Future<void> _showActions(BuildContext context, ProfilePost post) async {
    if (!profile.isSelf) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(post.archived ? Icons.unarchive_outlined : Icons.archive_outlined),
              title: Text(post.archived ? 'Arşivden çıkar' : 'Arşivle'),
              subtitle: Text(post.archived
                  ? 'Paylaşım yeniden akışta ve profilinde görünür.'
                  : 'Akıştan ve ızgaradan kalkar; yorumlar ve beğeniler korunur.'),
              onTap: () {
                Navigator.pop(sheetContext);
                post.archived
                    ? controller.unarchivePost(post.id)
                    : controller.archivePost(post.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.accentRose),
              title: const Text('Sil'),
              onTap: () {
                Navigator.pop(sheetContext);
                onDelete(post);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Izgaranın üstündeki iki kelime.
///
/// Yerinde duran `SegmentedButton` her iki kutuyu da çerçeveleyip seçiliye tik
/// koyuyordu: ekranın en sessiz denetimi, sayfadaki en gürültülü öge olmuştu.
/// Burada yalnızca seçili olan doluyor, çerçeve yok, tik yok.
class _ArchiveSwitch extends StatelessWidget {
  const _ArchiveSwitch({required this.showArchive, required this.onChanged});

  final bool showArchive;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.profileTint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment('Paylaşımlar', selected: !showArchive, value: false),
          _segment('Arşiv', selected: showArchive, value: true),
        ],
      ),
    ),
  );

  Widget _segment(String label, {required bool selected, required bool value}) =>
      Material(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: selected ? null : () => onChanged(value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? AppColors.profileAccent
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      );
}

class _PostTile extends StatelessWidget {
  const _PostTile({required this.post, required this.enabled, required this.onLongPress});

  final ProfilePost post;
  final bool enabled;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final thumbnail = appImageProvider(post.thumbnailUrl);
    return GestureDetector(
      onLongPress: enabled ? onLongPress : null,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.profileTint,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.profileBorder),
          image: thumbnail == null
              ? null
              : DecorationImage(image: thumbnail, fit: BoxFit.cover),
        ),
        padding: const EdgeInsets.all(8),
        alignment: Alignment.center,
        // A text-only post still needs a tile. Rendering the opening words as a
        // typographic card keeps the grid from turning into a row of grey boxes.
        child: thumbnail != null
            ? null
            : Text(
                post.message,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, height: 1.3, color: AppColors.textSecondary),
              ),
      ),
    );
  }
}

/// Gelen kutusu ve arkadaş listesi.
///
/// Bu sekme uzun süre "bir sonraki güncellemede" diyordu; artık gerçek. Gelen
/// istekler üstte duruyor, çünkü cevap bekleyen tek şey onlar.
class _FriendsTab extends StatelessWidget {
  const _FriendsTab({
    required this.profile,
    required this.controller,
    required this.onFriendsChanged,
  });

  final UserProfile profile;
  final FriendshipController controller;
  final Future<void> Function() onFriendsChanged;

  @override
  Widget build(BuildContext context) {
    if (!profile.canViewFullProfile) {
      return const _EmptyState(
        icon: Icons.lock_outline,
        title: 'Bu profil gizli',
        message: 'Arkadaş listesini yalnızca arkadaşları görebilir.',
      );
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.isLoading && !controller.hasLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        if (controller.errorMessage != null && !controller.hasLoaded) {
          return _ErrorState(
            message: controller.errorMessage!,
            onRetry: controller.load,
          );
        }
        final incoming = controller.incomingRequests;
        final outgoing = controller.outgoingRequests;
        final friends = controller.friends;
        if (incoming.isEmpty && outgoing.isEmpty && friends.isEmpty) {
          return _EmptyState(
            icon: Icons.group_outlined,
            title: 'Henüz arkadaş yok',
            message: profile.isSelf
                ? 'Akıştaki bir paylaşımın menüsünden "Arkadaş ekle" diyerek başlayabilirsin.'
                : 'Bu üyenin henüz arkadaşı yok.',
          );
        }
        return RefreshIndicator(
          onRefresh: controller.load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              if (incoming.isNotEmpty) ...[
                const _FriendsSectionTitle('Gelen istekler'),
                for (final request in incoming)
                  _FriendRequestTile(
                    request: request,
                    onAccept: () => _respond(context, request, true),
                    onDecline: () => _respond(context, request, false),
                  ),
                const SizedBox(height: 20),
              ],
              if (outgoing.isNotEmpty) ...[
                const _FriendsSectionTitle('Gönderilen istekler'),
                for (final request in outgoing)
                  _FriendRequestTile(
                    request: request,
                    onCancel: () => controller.cancelRequest(request.id),
                  ),
                const SizedBox(height: 20),
              ],
              _FriendsSectionTitle('Arkadaşlar (${friends.length})'),
              if (friends.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Henüz kimseyle arkadaş değilsin.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              for (final friend in friends)
                _FriendTile(
                  friend: friend,
                  onRemove: profile.isSelf
                      ? () => _confirmUnfriend(context, friend)
                      : null,
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _respond(
    BuildContext context,
    FriendRequest request,
    bool accepted,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await controller.respond(request.id, accepted);
    if (!ok) return;
    if (accepted) await onFriendsChanged();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          accepted
              ? '${request.displayName} artık arkadaşın.'
              : 'İstek reddedildi.',
        ),
      ),
    );
  }

  Future<void> _confirmUnfriend(
    BuildContext context,
    FriendSummary friend,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Arkadaşlıktan çıkar'),
        content: Text(
          '${friend.displayName} arkadaş listenden çıkarılsın mı? Arkadaşa özel '
          'paylaşımlarını artık göremez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Çıkar'),
          ),
        ],
      ),
    );
    if (confirmed == true && await controller.unfriend(friend.userId)) {
      await onFriendsChanged();
    }
  }
}

class _FriendsSectionTitle extends StatelessWidget {
  const _FriendsSectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
    ),
  );
}

class _FriendRequestTile extends StatelessWidget {
  const _FriendRequestTile({
    required this.request,
    this.onAccept,
    this.onDecline,
    this.onCancel,
  });

  final FriendRequest request;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final avatar = appImageProvider(request.avatarUrl);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.profileTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.profileBorder),
      ),
      // İsim üstte, düğmeler altta: uzun bir ad ile iki düğme aynı satıra
      // dar ekranda sığmıyor.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.profileBorder,
                backgroundImage: avatar,
                child: avatar == null
                    ? const Icon(Icons.person_outline, size: 20)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  request.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (onCancel != null)
                TextButton(onPressed: onCancel, child: const Text('Geri çek'))
              else ...[
                TextButton(onPressed: onDecline, child: const Text('Reddet')),
                const SizedBox(width: 8),
                FilledButton(onPressed: onAccept, child: const Text('Kabul et')),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _FriendTile extends StatelessWidget {
  const _FriendTile({required this.friend, this.onRemove});

  final FriendSummary friend;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final avatar = appImageProvider(friend.avatarUrl);
    final place = friend.placeLabel;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: AppColors.profileTint,
        backgroundImage: avatar,
        child: avatar == null
            ? const Icon(Icons.person_outline, size: 20)
            : null,
      ),
      title: Text(
        friend.displayName,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: place.isEmpty
          ? null
          : Text(
              place,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
      trailing: onRemove == null
          ? null
          : IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.person_remove_outlined, size: 20),
              tooltip: 'Arkadaşlıktan çıkar',
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, style: const TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        FilledButton(onPressed: onRetry, child: const Text('Tekrar dene')),
      ],
    ),
  );
}

class _StoryHighlights extends StatelessWidget {
  const _StoryHighlights({required this.controller});

  final StoryController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final highlights = controller.highlights;
      // Nothing to show means nothing to draw: an empty card announcing its own
      // emptiness is the kind of filler this screen had too much of.
      if (highlights.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 2, bottom: 8),
              child: Text(
                'Öne çıkanlar',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ),
            SizedBox(
              height: 74,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: highlights.length,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final highlight = highlights[index];
                  final first = highlight.items.first;
                  final image = appImageProvider(
                    first.media.thumbnailUrl ?? first.media.url,
                  );
                  return SizedBox(
                    width: 68,
                    child: Column(
                      children: [
                        Container(
                          height: 51,
                          width: 51,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.profileTint,
                            border: Border.all(color: AppColors.profileAccent, width: 2),
                            image: image == null
                                ? null
                                : DecorationImage(image: image, fit: BoxFit.cover),
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

class _VerifiedAccountRow extends StatelessWidget {
  const _VerifiedAccountRow({required this.controller});

  final MemberCapabilitiesController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final verified = controller.value.identityVerified;
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
        decoration: BoxDecoration(
          color: verified ? const Color(0xFFEAFBF3) : AppColors.profileTint,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: verified ? const Color(0xFF86E2B3) : AppColors.profileBorder,
          ),
        ),
        child: Row(
          children: [
            Icon(
              verified ? Icons.verified_rounded : Icons.verified_user_outlined,
              size: 18,
              color: verified ? const Color(0xFF059669) : AppColors.profileAccent,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                verified ? 'Onaylı Hesap rozeti aktif' : 'Onaylı Hesap rozeti gerekli',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            if (controller.isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              TextButton(
                onPressed: verified ? controller.load : () => _startVerification(context),
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
        const SnackBar(content: Text('Doğrulama şu anda başlatılamadı. Lütfen tekrar deneyin.')),
      );
    }
  }
}
