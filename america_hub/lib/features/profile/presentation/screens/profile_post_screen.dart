import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_image_source.dart';
import '../../domain/entities/user_profile.dart';
import '../widgets/post_card_palette.dart';

/// Izgaradaki bir karenin açılmış hâli.
///
/// Izgara uzun süre bir çıkmazdı: kareye dokunmak hiçbir şey yapmıyordu, uzun
/// basmak ise gizli bir menü açıyordu. Paylaşımın tamamını okumanın, kaç beğeni
/// aldığını görmenin ve onunla ilgili bir şey yapmanın yeri burası.
class ProfilePostScreen extends StatelessWidget {
  const ProfilePostScreen({
    super.key,
    required this.post,
    required this.authorName,
    required this.isOwner,
    this.avatarUrl,
    this.username,
    this.onOpenComments,
    this.onTogglePin,
    this.onToggleComments,
    this.onToggleArchive,
    this.onDelete,
  });

  final ProfilePost post;
  final String authorName;
  final String? username;
  final String? avatarUrl;

  /// Sahibi değilse üç nokta menüsü hiç çizilmiyor: bir başkasının paylaşımını
  /// sabitlemek ya da arşivlemek diye bir şey yok.
  final bool isOwner;

  /// Null ise yorum tabakası bu ekrandan açılamıyor ve sayı bir düğme gibi
  /// değil, düz bir bilgi olarak duruyor.
  final VoidCallback? onOpenComments;
  final Future<void> Function()? onTogglePin;
  final Future<void> Function()? onToggleComments;
  final Future<void> Function()? onToggleArchive;
  final Future<void> Function()? onDelete;

  @override
  Widget build(BuildContext context) {
    final image = appImageProvider(post.thumbnailUrl);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'Paylaşım',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        actions: [
          if (isOwner)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (value) => _onAction(context, value),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'pin',
                  enabled: onTogglePin != null,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      post.pinned
                          ? Icons.push_pin_rounded
                          : Icons.push_pin_outlined,
                    ),
                    title: Text(post.pinned ? 'Sabiti kaldır' : 'Başa sabitle'),
                  ),
                ),
                PopupMenuItem(
                  value: 'comments',
                  enabled: onToggleComments != null,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      post.commentsEnabled
                          ? Icons.comments_disabled_outlined
                          : Icons.mode_comment_outlined,
                    ),
                    title: Text(
                      post.commentsEnabled ? 'Yorumlara kapat' : 'Yorumlara aç',
                    ),
                  ),
                ),
                PopupMenuItem(
                  value: 'archive',
                  enabled: onToggleArchive != null,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      post.archived
                          ? Icons.unarchive_outlined
                          : Icons.archive_outlined,
                    ),
                    title: Text(post.archived ? 'Arşivden çıkar' : 'Arşivle'),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  enabled: onDelete != null,
                  child: const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline, color: AppColors.accentRose),
                    title: Text('Sil', style: TextStyle(color: AppColors.accentRose)),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.profileTint,
                backgroundImage: appImageProvider(avatarUrl),
                child: appImageProvider(avatarUrl) == null
                    ? Text(
                        authorName.characters.first.toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.profileAccent,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      authorName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      [
                        if (username != null) '@$username',
                        _dateLabel(post.createdAt),
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (post.pinned)
                const _Marker(icon: Icons.push_pin_rounded, label: 'Sabit'),
            ],
          ),
          const SizedBox(height: 14),
          if (image != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image(image: image, fit: BoxFit.cover),
            )
          else
            Container(
              constraints: const BoxConstraints(minHeight: 180),
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: postCardGradient(post.id),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                post.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (image != null && post.message.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(post.message, style: const TextStyle(height: 1.4)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(
                Icons.favorite_border_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                '${post.likes} beğeni',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(width: 18),
              // Yorumlara kapalı bir paylaşımda sayı hâlâ yazıyor: daha önce
              // yazılmış yorumlar silinmiyor, yalnızca yenisi eklenemiyor.
              Icon(
                post.commentsEnabled
                    ? Icons.mode_comment_outlined
                    : Icons.comments_disabled_outlined,
                size: 18,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: onOpenComments == null
                    ? Text(
                        post.commentsEnabled
                            ? '${post.comments} yorum'
                            : '${post.comments} yorum · kapalı',
                        style: const TextStyle(color: AppColors.textSecondary),
                      )
                    : TextButton(
                        onPressed: onOpenComments,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          alignment: Alignment.centerLeft,
                          visualDensity: VisualDensity.compact,
                        ),
                        child: Text(
                          post.commentsEnabled
                              ? '${post.comments} yorum'
                              : '${post.comments} yorum · kapalı',
                        ),
                      ),
              ),
            ],
          ),
          if (post.archived) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.profileTint,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.profileBorder),
              ),
              child: const Row(
                children: [
                  Icon(Icons.archive_outlined, size: 18, color: AppColors.textMuted),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Bu paylaşım arşivde. Akışta ve ızgarada görünmüyor; '
                      'beğenileri ve yorumları duruyor.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
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

  Future<void> _onAction(BuildContext context, String value) async {
    switch (value) {
      case 'pin':
        await onTogglePin?.call();
      case 'comments':
        await onToggleComments?.call();
      case 'archive':
        await onToggleArchive?.call();
      case 'delete':
        await onDelete?.call();
    }
    // Silme, arşivleme ve sabitleme listeyi değiştiriyor; bu ekran elindeki
    // eski kaydı çizmeye devam etmesin diye kapanıyor.
    if (context.mounted) Navigator.of(context).maybePop();
  }

  static String _dateLabel(DateTime value) {
    const months = [
      'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
      'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
    ];
    return '${value.day} ${months[value.month - 1]} ${value.year}';
  }
}

class _Marker extends StatelessWidget {
  const _Marker({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.profileTint,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.profileAccent),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppColors.profileAccent,
          ),
        ),
      ],
    ),
  );
}
