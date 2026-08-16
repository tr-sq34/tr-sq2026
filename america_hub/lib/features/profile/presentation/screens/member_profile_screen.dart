import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/state/async_state.dart';
import '../../../../core/widgets/app_image_source.dart';
import '../../application/friendship_controller.dart';
import '../../application/profile_controller.dart';
import '../../domain/entities/friendship.dart';
import '../../domain/entities/user_profile.dart';
import '../widgets/follow_list_sheet.dart';
import '../widgets/profile_badge_chip.dart';

/// Başka bir üyenin profilini açar.
///
/// Uygulamada uzun süre böyle bir ekran yoktu: akıştaki bir ada dokunmak hiçbir
/// yere gitmiyordu ve bir üyeyi tanımanın tek yolu paylaşımının altındaki
/// menüydü. Buraya avatardan, addan ve takip listelerinden geliniyor.
Future<void> openMemberProfile(
  BuildContext context, {
  required String userId,
  required ProfileController controller,
  FriendshipController? friendshipController,
  void Function(UserProfile profile)? onMessage,
}) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MemberProfileScreen(
          userId: userId,
          controller: controller,
          friendshipController: friendshipController,
          onMessage: onMessage,
        ),
      ),
    );

class MemberProfileScreen extends StatefulWidget {
  const MemberProfileScreen({
    super.key,
    required this.userId,
    required this.controller,
    this.friendshipController,
    this.onMessage,
  });

  final String userId;
  final ProfileController controller;

  /// Arkadaşlık düğmesi yalnızca denetleyici verildiğinde çiziliyor. Hiçbir şey
  /// yapmayan bir "Arkadaş ekle" düğmesi, olmayan bir özelliği varmış gibi
  /// göstermek olurdu.
  final FriendshipController? friendshipController;
  final void Function(UserProfile profile)? onMessage;

  @override
  State<MemberProfileScreen> createState() => _MemberProfileScreenState();
}

class _MemberProfileScreenState extends State<MemberProfileScreen> {
  AsyncState<UserProfile> _state = const AsyncLoading();
  AsyncState<List<ProfilePost>> _posts = const AsyncLoading();
  bool _followBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = const AsyncLoading());
    try {
      final profile = await widget.controller.profileOf(widget.userId);
      if (!mounted) return;
      setState(() => _state = AsyncData(profile));
      await widget.friendshipController?.loadStatus(widget.userId);
      await _loadPosts();
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = const AsyncFailure('Profil yüklenemedi.'));
    }
  }

  Future<void> _loadPosts() async {
    try {
      final posts = await widget.controller.postsOf(widget.userId);
      if (!mounted) return;
      setState(() => _posts = AsyncData(posts));
    } catch (_) {
      if (!mounted) return;
      setState(() => _posts = const AsyncFailure('Paylaşımlar yüklenemedi.'));
    }
  }

  Future<void> _toggleFollow(UserProfile profile) async {
    setState(() => _followBusy = true);
    final result =
        await widget.controller.setFollowing(profile.id, !profile.viewerFollows);
    if (!mounted) return;
    setState(() => _followBusy = false);
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İşlem tamamlanamadı. Tekrar dene.')),
      );
      return;
    }
    if (profile.viewerFollows && result) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${profile.displayName} arkadaşın olduğu için takip listende kalıyor.',
          ),
        ),
      );
    }
    // Sayaçlar sunucudan yeniden okunuyor; burada birer artırmak, arkadaşlık
    // yüzünden işlemeyen bir takipten çıkmayı olmuş gibi göstermek olurdu.
    await _load();
  }

  void _openFollows(UserProfile profile, FollowListTab tab) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => FollowListSheet(
          controller: widget.controller,
          profile: profile,
          initialTab: tab,
          onOpenMember: (userId) {
            Navigator.of(context).pop();
            if (userId == profile.id) return;
            openMemberProfile(
              context,
              userId: userId,
              controller: widget.controller,
              friendshipController: widget.friendshipController,
              onMessage: widget.onMessage,
            );
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          state is AsyncData<UserProfile> ? state.value.displayName : 'Profil',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
      ),
      body: switch (state) {
        AsyncFailure<UserProfile>(:final message) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Tekrar dene')),
            ],
          ),
        ),
        AsyncData<UserProfile>(:final value) => _body(value),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _body(UserProfile profile) => RefreshIndicator(
    onRefresh: _load,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        _MemberHead(
          profile: profile,
          onOpenFollowers: () => _openFollows(profile, FollowListTab.followers),
          onOpenFollowing: () => _openFollows(profile, FollowListTab.following),
        ),
        const SizedBox(height: 14),
        _Actions(
          profile: profile,
          followBusy: _followBusy,
          onToggleFollow: () => _toggleFollow(profile),
          friendshipController: widget.friendshipController,
          onMessage: widget.onMessage == null ? null : () => widget.onMessage!(profile),
        ),
        if (profile.showcasedBadges.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final badge in profile.showcasedBadges)
                ProfileBadgeChip(title: badge.title, tier: badge.tier),
            ],
          ),
        ],
        const SizedBox(height: 16),
        // Kilitli profil bir duvar değil: kim olduğu, kendini nasıl anlattığı ve
        // rozetleri yukarıda duruyor. Kapalı olan geri kalanı ve neden kapalı
        // olduğu burada tek cümleyle yazıyor.
        if (!profile.canViewFullProfile)
          const _LockedNotice()
        else ...[
          _Facts(profile: profile),
          const SizedBox(height: 16),
          _PostGrid(state: _posts, onRetry: _loadPosts),
        ],
      ],
    ),
  );
}

class _MemberHead extends StatelessWidget {
  const _MemberHead({
    required this.profile,
    required this.onOpenFollowers,
    required this.onOpenFollowing,
  });

  final UserProfile profile;
  final VoidCallback onOpenFollowers;
  final VoidCallback onOpenFollowing;

  @override
  Widget build(BuildContext context) {
    final avatar = appImageProvider(profile.avatarUrl);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor: AppColors.profileTint,
              backgroundImage: avatar,
              child: avatar == null
                  ? Text(
                      profile.displayName.characters.first.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.profileAccent,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _Count(value: profile.postCount, label: 'Paylaşım'),
                  ),
                  Expanded(
                    child: _Count(
                      value: profile.followerCount,
                      label: 'Takipçi',
                      onTap: onOpenFollowers,
                    ),
                  ),
                  Expanded(
                    child: _Count(
                      value: profile.followingCount,
                      label: 'Takip',
                      onTap: onOpenFollowing,
                    ),
                  ),
                ],
              ),
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
        if (profile.username != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '@${profile.username}',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.profileAccent,
              ),
            ),
          ),
        if (profile.followsViewer)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Seni takip ediyor',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        if (profile.bio.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(profile.bio, style: const TextStyle(height: 1.35)),
        ],
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.value, required this.label, this.onTap});

  final int value;
  final String label;
  final VoidCallback? onTap;

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

class _Actions extends StatelessWidget {
  const _Actions({
    required this.profile,
    required this.followBusy,
    required this.onToggleFollow,
    this.friendshipController,
    this.onMessage,
  });

  final UserProfile profile;
  final bool followBusy;
  final VoidCallback onToggleFollow;
  final FriendshipController? friendshipController;
  final VoidCallback? onMessage;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: profile.viewerFollows
            ? OutlinedButton.icon(
                onPressed: followBusy ? null : onToggleFollow,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Takiptesin'),
              )
            : FilledButton.icon(
                onPressed: followBusy ? null : onToggleFollow,
                icon: const Icon(Icons.person_add_alt_rounded, size: 18),
                label: const Text('Takip et'),
              ),
      ),
      if (friendshipController != null) ...[
        const SizedBox(width: 10),
        Expanded(
          child: AnimatedBuilder(
            animation: friendshipController!,
            builder: (context, _) {
              final status = friendshipController!.statusOf(profile.id);
              // Bu üç düğme uzun süre kapalıydı: durumu söylüyor, hiçbir şey
              // yapmıyorlardı. "Sana istek gönderdi" yazan bir düğmeye basıp
              // isteği kabul edememek en kötüsüydü — üyeyi zile geri
              // gönderiyordu. Depoda dört yöntem de zaten vardı.
              return switch (status) {
                FriendshipStatus.friends => OutlinedButton.icon(
                  onPressed: () => _openFriendMenu(context),
                  icon: const Icon(Icons.people_rounded, size: 18),
                  label: const Text('Arkadaşsınız'),
                ),
                FriendshipStatus.pendingOutgoing => OutlinedButton.icon(
                  onPressed: () => _withdrawRequest(context),
                  icon: const Icon(Icons.hourglass_bottom_rounded, size: 18),
                  label: const Text('İstek gönderildi'),
                ),
                FriendshipStatus.pendingIncoming => FilledButton.icon(
                  onPressed: () => _answerRequest(context),
                  icon: const Icon(Icons.mark_email_unread_outlined, size: 18),
                  label: const Text('İsteği yanıtla'),
                ),
                FriendshipStatus.blocked => const SizedBox.shrink(),
                FriendshipStatus.none => OutlinedButton.icon(
                  onPressed: () => _sendRequest(context),
                  icon: const Icon(Icons.person_add_outlined, size: 18),
                  label: const Text('Arkadaş ekle'),
                ),
              };
            },
          ),
        ),
      ],
      if (onMessage != null) ...[
        const SizedBox(width: 10),
        IconButton.filledTonal(
          onPressed: onMessage,
          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
          tooltip: 'Mesaj gönder',
        ),
      ],
    ],
  );

  /// Bekleyen isteğin kimliği.
  ///
  /// Profil ekranı yalnızca durumu okuyor; kimlik istek listesinde duruyor.
  /// Liste okunmamışsa bir kez okunuyor, yine bulunamazsa üyeye sessiz bir
  /// hiçbir şey değil, ne olduğu söyleniyor.
  Future<FriendRequest?> _pendingRequest() async {
    final controller = friendshipController!;
    final known = controller.requestWith(profile.id);
    if (known != null) return known;
    await controller.load();
    return controller.requestWith(profile.id);
  }

  Future<void> _answerRequest(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final request = await _pendingRequest();
    if (!context.mounted) return;
    if (request == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'İstek bilgisi okunamadı. Bağlantını kontrol edip tekrar dene.',
          ),
        ),
      );
      return;
    }
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(
                '${profile.displayName} sana arkadaşlık isteği gönderdi.',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.check_rounded, color: AppColors.primary),
              title: const Text('Kabul et'),
              onTap: () => Navigator.of(sheetContext).pop(true),
            ),
            ListTile(
              leading: const Icon(
                Icons.close_rounded,
                color: AppColors.textMuted,
              ),
              title: const Text('Reddet'),
              // Reddedilen istek karşı tarafa bildirilmiyor; ekranda da öyle
              // yazıyor ki üye "haber gider mi" diye tereddüt etmesin.
              subtitle: const Text(
                'Karşı tarafa bildirilmez.',
                style: TextStyle(fontSize: 11.5),
              ),
              onTap: () => Navigator.of(sheetContext).pop(false),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (accepted == null) return;
    final done = await friendshipController!.respond(request.id, accepted);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          !done
              ? friendshipController!.errorMessage ?? 'İstek yanıtlanamadı.'
              : accepted
              ? '${profile.displayName} ile arkadaş oldunuz.'
              : 'İstek reddedildi.',
        ),
      ),
    );
  }

  Future<void> _withdrawRequest(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final request = await _pendingRequest();
    if (!context.mounted) return;
    if (request == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'İstek bilgisi okunamadı. Bağlantını kontrol edip tekrar dene.',
          ),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('İsteği geri çek'),
        content: Text(
          '${profile.displayName} kişisine gönderdiğin arkadaşlık isteği geri '
          'alınsın mı? Dilediğin zaman yeniden gönderebilirsin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Geri çek'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final done = await friendshipController!.cancelRequest(request.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          done
              ? 'İstek geri çekildi.'
              : friendshipController!.errorMessage ?? 'İstek geri çekilemedi.',
        ),
      ),
    );
  }

  Future<void> _openFriendMenu(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final remove = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(
                '${profile.displayName} ile arkadaşsınız.',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.person_remove_outlined,
                color: Color(0xFFB45309),
              ),
              title: const Text('Arkadaşlıktan çıkar'),
              subtitle: const Text(
                'Takip durumun değişmez, karşı tarafa bildirilmez.',
                style: TextStyle(fontSize: 11.5),
              ),
              onTap: () => Navigator.of(sheetContext).pop(true),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (remove != true || !context.mounted) return;
    final done = await friendshipController!.unfriend(profile.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          done
              ? '${profile.displayName} arkadaş listenden çıkarıldı.'
              : friendshipController!.errorMessage ??
                    'Arkadaşlık kaldırılamadı.',
        ),
      ),
    );
  }

  Future<void> _sendRequest(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final sent = await friendshipController!.send(profile.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          sent
              ? '${profile.displayName} kişisine arkadaşlık isteği gönderildi.'
              : friendshipController!.errorMessage ?? 'İstek gönderilemedi.',
        ),
      ),
    );
  }
}

class _LockedNotice extends StatelessWidget {
  const _LockedNotice();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.profileTint,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.profileBorder),
    ),
    child: const Column(
      children: [
        Icon(Icons.lock_outline, size: 30, color: AppColors.textMuted),
        SizedBox(height: 10),
        Text('Bu profil gizli', style: TextStyle(fontWeight: FontWeight.w800)),
        SizedBox(height: 6),
        Text(
          'Paylaşımlarını, nereden geldiğini ve ilgi alanlarını yalnızca '
          'arkadaşları görebiliyor. Arkadaş olduğunuzda burası açılır.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ],
    ),
  );
}

class _Facts extends StatelessWidget {
  const _Facts({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final rows = <(IconData, String, String)>[
      if (profile.journeyLine != null)
        (Icons.place_outlined, 'Nerelisin', profile.journeyLine!)
      else if (profile.bornInUs)
        (Icons.place_outlined, 'Nerelisin', 'Amerika doğumlu'),
      if (profile.interests.isNotEmpty)
        (Icons.interests_outlined, 'İlgi alanları', profile.interests.join(', ')),
    ];
    // Hiçbir şey yazmamış bir üyenin profilinde boş bir kart durmasın.
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.profileBorder),
      ),
      child: Column(
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 44,
                color: AppColors.profileBorder,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(rows[index].$1, size: 18, color: AppColors.profileAccent),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 92,
                    child: Text(
                      rows[index].$2,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      rows[index].$3,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PostGrid extends StatelessWidget {
  const _PostGrid({required this.state, required this.onRetry});

  final AsyncState<List<ProfilePost>> state;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => switch (state) {
    AsyncFailure<List<ProfilePost>>(:final message) => Column(
      children: [
        Text(message, style: const TextStyle(color: AppColors.textSecondary)),
        TextButton(onPressed: onRetry, child: const Text('Tekrar dene')),
      ],
    ),
    AsyncData<List<ProfilePost>>(:final value) when value.isEmpty => const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Text(
        'Henüz bir paylaşım yok.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary),
      ),
    ),
    AsyncData<List<ProfilePost>>(:final value) => GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: value.length,
      itemBuilder: (context, index) {
        final post = value[index];
        final thumbnail = appImageProvider(post.thumbnailUrl);
        return Container(
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
          child: thumbnail != null
              ? null
              : Text(
                  post.message,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    color: AppColors.textSecondary,
                  ),
                ),
        );
      },
    ),
    _ => const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(child: CircularProgressIndicator()),
    ),
  };
}
