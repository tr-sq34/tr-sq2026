import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_image_source.dart';
import '../../domain/entities/user_profile.dart';
import 'post_card_palette.dart';

/// Izgaradaki tek kare. Profil ızgarası ile arşiv aynı kareyi kullanıyor:
/// arşivdeki paylaşım, profildekinden başka bir şeye benzemesin.
class ProfilePostTile extends StatelessWidget {
  const ProfilePostTile({
    super.key,
    required this.post,
    required this.enabled,
    required this.onOpen,
    required this.onMenu,
  });

  final ProfilePost post;

  /// Menü yalnızca kendi profilinde. Başkasının paylaşımını sabitlemek ya da
  /// arşivlemek diye bir şey yok; kareye dokunup okumak ise herkese açık.
  final bool enabled;
  final VoidCallback onOpen;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final thumbnail = appImageProvider(post.thumbnailUrl);
    return GestureDetector(
      onTap: onOpen,
      onLongPress: enabled ? onMenu : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              // Fotoğrafsız paylaşım artık gri bir kutu değil: yazı kendi
              // renkli kartını alıyor, ızgara da birbirinin aynı karelerden
              // kurtuluyor.
              color: thumbnail == null ? null : AppColors.profileTint,
              gradient: thumbnail == null ? postCardGradient(post.id) : null,
              borderRadius: BorderRadius.circular(10),
              border: thumbnail == null
                  ? null
                  : Border.all(color: AppColors.profileBorder),
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
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.3,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          if (post.pinned)
            const Positioned(
              top: 4,
              left: 4,
              child: _TileMarker(icon: Icons.push_pin_rounded),
            ),
          if (!post.commentsEnabled)
            Positioned(
              top: 4,
              left: post.pinned ? 26 : 4,
              child: const _TileMarker(icon: Icons.comments_disabled_rounded),
            ),
          if (enabled)
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: onMenu,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: _TileMarker(icon: Icons.more_horiz_rounded),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Karenin köşesindeki küçük işaret. Kare zaten üçte bir ekran genişliğinde;
/// yazı sığmıyor, o yüzden yalnızca simge - ne anlama geldiği paylaşımın
/// kendisi açıldığında yazıyla duruyor.
class _TileMarker extends StatelessWidget {
  const _TileMarker({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: const Color(0x66000000),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(icon, size: 13, color: Colors.white),
  );
}
