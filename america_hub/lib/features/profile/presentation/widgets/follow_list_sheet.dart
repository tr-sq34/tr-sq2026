import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_image_source.dart';
import '../../application/profile_controller.dart';
import '../../domain/entities/user_profile.dart';

enum FollowListTab { followers, following }

/// Takipçiler ve takip edilenler, tek sayfada iki sekme.
///
/// Yönetim burada: kendi profilinde takipçini listeden çıkarabiliyor, takip
/// ettiğin birini bırakabiliyor, listede gördüğün birini takip edebiliyorsun.
/// Yüklenemedi, kilitli ve gerçekten boş üç ayrı ekran — üçünü de boş liste
/// olarak göstermek, olmayan bir sessizliği varmış gibi anlatmak olurdu.
class FollowListSheet extends StatefulWidget {
  const FollowListSheet({
    super.key,
    required this.controller,
    required this.profile,
    this.initialTab = FollowListTab.followers,
    this.onOpenMember,
  });

  final ProfileController controller;
  final UserProfile profile;
  final FollowListTab initialTab;

  /// Listedeki bir kişiye dokunmak profilini açıyor. Null geçilirse satır
  /// dokunulamaz kalıyor — bir yere gitmeyen dokunuş, bozuk bir düğmedir.
  final void Function(String userId)? onOpenMember;

  @override
  State<FollowListSheet> createState() => _FollowListSheetState();
}

class _FollowListSheetState extends State<FollowListSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.initialTab == FollowListTab.followers ? 0 : 1,
  );

  final Map<FollowListTab, _ListState> _lists = {
    FollowListTab.followers: const _ListState.loading(),
    FollowListTab.following: const _ListState.loading(),
  };

  @override
  void initState() {
    super.initState();
    _load(FollowListTab.followers);
    _load(FollowListTab.following);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load(FollowListTab tab) async {
    setState(() => _lists[tab] = const _ListState.loading());
    try {
      final result = tab == FollowListTab.followers
          ? await widget.controller.followers(widget.profile.id)
          : await widget.controller.following(widget.profile.id);
      if (!mounted) return;
      setState(() => _lists[tab] = result.locked
          ? const _ListState.locked()
          : _ListState.ready(result.items));
    } catch (_) {
      if (!mounted) return;
      setState(() => _lists[tab] = const _ListState.failed());
    }
  }

  Future<void> _toggleFollow(FollowSummary member) async {
    final wanted = !member.viewerFollows;
    final result = await widget.controller.setFollowing(member.userId, wanted);
    if (!mounted) return;
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wanted ? 'Takip edilemedi. Tekrar dene.' : 'Takipten çıkılamadı. Tekrar dene.',
          ),
        ),
      );
      return;
    }
    if (!wanted && result) {
      // Sunucu "hâlâ takip ediliyor" dedi: arkadaşlık ayakta ve tek yönlü bir
      // takipten çıkma onu bozmuyor. Üye düğmenin neden değişmediğini bilmeli.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${member.displayName} arkadaşın olduğu için takip listende kalıyor. '
            'Çıkarmak için arkadaşlıktan çıkarman gerekiyor.',
          ),
        ),
      );
    }
    await _load(FollowListTab.followers);
    await _load(FollowListTab.following);
  }

  Future<void> _removeFollower(FollowSummary member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Takipçi çıkarılsın mı?'),
        content: Text(
          '${member.displayName} artık seni takip etmiyor olacak. Haberi olmaz ve '
          'seni yeniden takip edebilir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Çıkar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await widget.controller.removeFollower(member.userId);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Takipçi çıkarılamadı. Tekrar dene.')),
      );
      return;
    }
    await _load(FollowListTab.followers);
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: 0.85,
    minChildSize: 0.5,
    maxChildSize: 0.95,
    expand: false,
    builder: (context, scrollController) => Column(
      children: [
        const SizedBox(height: 10),
        Container(
          height: 4,
          width: 40,
          decoration: BoxDecoration(
            color: AppColors.profileBorder,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.profile.displayName,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        TabBar(
          controller: _tabs,
          labelColor: AppColors.profileAccent,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.profileAccent,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: [
            Tab(text: '${widget.profile.followerCount} Takipçi'),
            Tab(text: '${widget.profile.followingCount} Takip'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildList(FollowListTab.followers, scrollController),
              _buildList(FollowListTab.following, scrollController),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildList(FollowListTab tab, ScrollController scrollController) {
    final state = _lists[tab]!;
    if (state.loading) return const Center(child: CircularProgressIndicator());
    if (state.failedMessage != null) {
      return _Notice(
        icon: Icons.cloud_off_rounded,
        title: state.failedMessage!,
        action: TextButton(onPressed: () => _load(tab), child: const Text('Tekrar dene')),
      );
    }
    if (state.locked) {
      return const _Notice(
        icon: Icons.lock_outline,
        title: 'Bu liste gizli',
        message: 'Takip listesini yalnızca arkadaşları görebilir.',
      );
    }
    final items = state.items!;
    if (items.isEmpty) {
      return _Notice(
        icon: tab == FollowListTab.followers
            ? Icons.people_outline
            : Icons.person_search_outlined,
        title: tab == FollowListTab.followers
            ? 'Henüz takipçin yok'
            : 'Henüz kimseyi takip etmiyorsun',
        message: tab == FollowListTab.followers
            ? 'Paylaşım yaptıkça ve topluluklara katıldıkça seni bulurlar.'
            : 'Akıştaki bir paylaşımda ada dokunup profilinden takip edebilirsin.',
      );
    }
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: items.length,
      itemBuilder: (context, index) => _FollowTile(
        member: items[index],
        isSelf: items[index].userId == widget.profile.id,
        onOpen: widget.onOpenMember == null
            ? null
            : () => widget.onOpenMember!(items[index].userId),
        onToggleFollow: () => _toggleFollow(items[index]),
        onRemoveFollower: widget.profile.isSelf && tab == FollowListTab.followers
            ? () => _removeFollower(items[index])
            : null,
      ),
    );
  }
}

/// Bir sekmenin dört halinden biri. Boş listeyi yükleniyor, kilitli ve
/// yüklenemedi hallerinden ayırt edebilmek için tek bir tipte toplandı.
class _ListState {
  const _ListState.loading()
      : loading = true, locked = false, items = null, failedMessage = null;
  const _ListState.locked()
      : loading = false, locked = true, items = null, failedMessage = null;
  const _ListState.failed()
      : loading = false, locked = false, items = null,
        failedMessage = 'Liste yüklenemedi.';
  const _ListState.ready(this.items)
      : loading = false, locked = false, failedMessage = null;

  final bool loading;
  final bool locked;
  final List<FollowSummary>? items;
  final String? failedMessage;
}

class _FollowTile extends StatelessWidget {
  const _FollowTile({
    required this.member,
    required this.isSelf,
    required this.onToggleFollow,
    this.onOpen,
    this.onRemoveFollower,
  });

  final FollowSummary member;
  final bool isSelf;
  final VoidCallback onToggleFollow;
  final VoidCallback? onOpen;
  final VoidCallback? onRemoveFollower;

  @override
  Widget build(BuildContext context) {
    final avatar = appImageProvider(member.avatarUrl);
    final subtitle = [
      if (member.username != null) '@${member.username}',
      if (member.placeLabel.isNotEmpty) member.placeLabel,
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onOpen,
      leading: CircleAvatar(
        radius: 21,
        backgroundColor: AppColors.profileTint,
        backgroundImage: avatar,
        child: avatar == null ? const Icon(Icons.person_outline, size: 20) : null,
      ),
      title: Text(
        member.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
      // Kendi satırında takip düğmesi yok: kimse kendini takip etmiyor.
      trailing: isSelf
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (member.viewerFollows)
                  OutlinedButton(
                    onPressed: onToggleFollow,
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      side: const BorderSide(color: AppColors.profileBorder),
                      foregroundColor: AppColors.textSecondary,
                    ),
                    child: const Text('Takiptesin'),
                  )
                else
                  FilledButton(
                    onPressed: onToggleFollow,
                    style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: const Text('Takip et'),
                  ),
                if (onRemoveFollower != null)
                  IconButton(
                    tooltip: 'Takipçiyi çıkar',
                    icon: const Icon(Icons.person_remove_outlined, size: 20),
                    onPressed: onRemoveFollower,
                  ),
              ],
            ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    ),
  );
}
