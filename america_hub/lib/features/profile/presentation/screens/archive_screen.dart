import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/state/async_state.dart';
import '../../application/profile_controller.dart';
import '../../domain/entities/user_profile.dart';
import '../widgets/profile_post_tile.dart';
import 'profile_post_screen.dart';

/// Arşivlenmiş paylaşımlar.
///
/// Eskiden profil ızgarasının üstünde "Paylaşımlar / Arşiv" diye bir geçiş
/// vardı: kendi profiline bakan herkes, hiç arşivi olmasa bile o düğmeyi
/// görüyordu. Arşiv nadiren açılan bir çekmece, sürekli önde duran bir sekme
/// değil - yeri hesap ayarlarının altı.
class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({
    super.key,
    required this.controller,
    required this.profile,
    this.onDelete,
  });

  final ProfileController controller;
  final UserProfile profile;

  /// Null ise bu ekrandan silme yapılamıyor ve menüde de görünmüyor. Çalışmayan
  /// bir "Sil" satırı göstermektense hiç göstermemek doğru.
  final Future<void> Function(ProfilePost)? onDelete;

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.loadArchived(widget.profile.id);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      backgroundColor: AppColors.background,
      elevation: 0,
      title: const Text(
        'Arşiv',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
      ),
    ),
    body: AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => switch (widget.controller.archived) {
        AsyncFailure<List<ProfilePost>>(:final message) => _ArchiveMessage(
          icon: Icons.cloud_off_rounded,
          title: message,
          detail: 'Bağlantı geri geldiğinde yeniden dene.',
          onRetry: () => widget.controller.loadArchived(widget.profile.id),
        ),
        AsyncData<List<ProfilePost>>(:final value) when value.isEmpty =>
          const _ArchiveMessage(
            icon: Icons.inventory_2_outlined,
            title: 'Arşivde bir şey yok.',
            detail:
                'Bir paylaşımı arşivlersen akıştan ve profilinden kalkar, '
                'beğenileri ve yorumları burada seni bekler.',
          ),
        AsyncData<List<ProfilePost>>(:final value) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 15,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${value.length} paylaşım arşivde. Bunları senden başka '
                      'kimse göremiyor.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                itemCount: value.length,
                itemBuilder: (context, index) => ProfilePostTile(
                  post: value[index],
                  enabled: true,
                  onOpen: () => _openPost(value[index]),
                  onMenu: () => _showActions(value[index]),
                ),
              ),
            ),
          ],
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    ),
  );

  void _openPost(ProfilePost post) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ProfilePostScreen(
        post: post,
        authorName: widget.profile.displayName,
        username: widget.profile.username,
        avatarUrl: widget.profile.avatarUrl,
        isOwner: true,
        // Arşivdeki bir paylaşım sabitlenemez ve yorumlara açılamaz: ikisi de
        // görünürlükle ilgili, görünmeyen bir paylaşımda karşılığı yok.
        onToggleArchive: () => _unarchive(post),
        onDelete: widget.onDelete == null ? null : () => _delete(post),
      ),
    ),
  );

  Future<void> _showActions(ProfilePost post) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.unarchive_outlined),
            title: const Text('Arşivden çıkar'),
            subtitle: const Text(
              'Paylaşım yeniden akışta ve profilinde görünür.',
            ),
            onTap: () {
              Navigator.pop(sheetContext);
              _unarchive(post);
            },
          ),
          if (widget.onDelete != null)
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: AppColors.accentRose,
              ),
              title: const Text('Sil'),
              subtitle: const Text('Geri alınamaz.'),
              onTap: () {
                Navigator.pop(sheetContext);
                _delete(post);
              },
            ),
        ],
      ),
    ),
  );

  Future<void> _unarchive(ProfilePost post) async {
    final messenger = ScaffoldMessenger.of(context);
    await widget.controller.unarchivePost(post.id);
    messenger.showSnackBar(
      const SnackBar(content: Text('Paylaşım arşivden çıkarıldı.')),
    );
  }

  Future<void> _delete(ProfilePost post) async {
    await widget.onDelete?.call(post);
    if (mounted) await widget.controller.loadArchived(widget.profile.id);
  }
}

class _ArchiveMessage extends StatelessWidget {
  const _ArchiveMessage({
    required this.icon,
    required this.title,
    required this.detail,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 38, color: AppColors.textMuted),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Yeniden dene')),
          ],
        ],
      ),
    ),
  );
}
