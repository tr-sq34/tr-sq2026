import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_image_source.dart';
import '../../domain/entities/conversation.dart';

/// Grup kurma ve grup ayarları sayfalarının ortak parçaları.
///
/// İkisi de aynı künyeyi düzenliyor: fotoğraf, ad, açıklama, şehir. Aynı alanı
/// iki yerde ayrı ayrı yazmak, birinde uzunluk sınırı olup ötekinde olmaması
/// gibi sessiz farklarla bitiyordu.

enum GroupPhotoAction { gallery, camera, remove }

/// Fotoğrafın nereden geleceğini soran küçük sayfa. "Kaldır" ayrı bir yanıt:
/// sayfayı kapatmakla fotoğrafı silmek aynı şey sayılamaz.
Future<GroupPhotoAction?> showGroupPhotoActions(
  BuildContext context, {
  required bool canRemove,
}) => showModalBottomSheet<GroupPhotoAction>(
  context: context,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (sheetContext) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFFE2E4EC),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined,
              color: AppColors.primary),
          title: const Text('Galeriden seç'),
          onTap: () => Navigator.pop(sheetContext, GroupPhotoAction.gallery),
        ),
        ListTile(
          leading:
              const Icon(Icons.photo_camera_outlined, color: AppColors.primary),
          title: const Text('Fotoğraf çek'),
          onTap: () => Navigator.pop(sheetContext, GroupPhotoAction.camera),
        ),
        if (canRemove)
          ListTile(
            leading:
                const Icon(Icons.delete_outline, color: AppColors.accentRose),
            title: const Text('Fotoğrafı kaldır'),
            onTap: () => Navigator.pop(sheetContext, GroupPhotoAction.remove),
          ),
        const SizedBox(height: 8),
      ],
    ),
  ),
);

/// Grup fotoğrafı: seçilmemişken davet eden bir daire, seçildikten sonra
/// yayınlanacak karenin kendisi. Yükleme sürerken üstünde bir örtü var, çünkü
/// "seçtim" ile "yüklendi" aynı an değil.
class GroupAvatarPicker extends StatelessWidget {
  const GroupAvatarPicker({
    super.key,
    required this.preview,
    required this.uploading,
    required this.ready,
    required this.onTap,
    this.existingUrl,
  });

  final Uint8List? preview;
  final bool uploading;
  final bool ready;
  final VoidCallback? onTap;

  /// Sunucuda zaten duran fotoğraf. Ayarlar sayfası açıldığında grubun mevcut
  /// fotoğrafı görünsün diye: boş bir daire, fotoğraf hiç yokmuş gibi okunuyor.
  final String? existingUrl;

  @override
  Widget build(BuildContext context) {
    final existing = preview == null ? appImageProvider(existingUrl) : null;
    return SizedBox(
      width: 104,
      height: 104,
      child: Material(
        color: const Color(0xFFF3F0FF),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (preview != null)
                Image.memory(preview!, fit: BoxFit.cover)
              else if (existing != null)
                Image(image: existing, fit: BoxFit.cover)
              else
                const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_outlined,
                        color: AppColors.primary, size: 26),
                    SizedBox(height: 5),
                    Text(
                      'Grup fotoğrafı',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              if (uploading)
                const ColoredBox(
                  color: Color(0x77000000),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.4,
                    ),
                  ),
                ),
              if (ready)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppColors.accentEmerald,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded,
                        size: 13, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class GroupTextField extends StatelessWidget {
  const GroupTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.maxLength,
    this.maxLines = 1,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final int maxLength;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    maxLength: maxLength,
    maxLines: maxLines,
    onChanged: onChanged,
    textCapitalization: TextCapitalization.sentences,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: maxLines > 1,
      prefixIcon: Padding(
        // Çok satırlı alanda simge ortada durunca ilk satırdan kopuyor.
        padding: EdgeInsets.only(bottom: maxLines > 1 ? 44 : 0),
        child: Icon(icon, color: AppColors.primary),
      ),
      filled: true,
      fillColor: const Color(0xFFF7F7FB),
      counterStyle: const TextStyle(fontSize: 10.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFEAEAF1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
      ),
    ),
  );
}

/// İki seçenek, ikisinin de ne demek olduğu yazılı.
///
/// Eskiden burada "Açık / Gizli" yazan iki düğme vardı ve hangisinin ne
/// getirdiği hiçbir yerde yazmıyordu. Gizli bir grupta geçmişin yalnızca
/// katıldıktan sonrası okunuyor; bu, seçimden sonra öğrenilecek bir şey değil.
class GroupPrivacyChoice extends StatelessWidget {
  const GroupPrivacyChoice({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final GroupPrivacy value;
  final ValueChanged<GroupPrivacy> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _option(
        privacy: GroupPrivacy.public,
        icon: Icons.public_rounded,
        title: 'Açık grup',
        subtitle: 'Herkes katılabilir, katılan geçmiş sohbetleri de okur.',
      ),
      const SizedBox(height: 8),
      _option(
        privacy: GroupPrivacy.private,
        icon: Icons.lock_outline_rounded,
        title: 'Gizli grup',
        subtitle: 'Katılım senin onayınla olur, geçmiş sohbetler görünmez.',
      ),
    ],
  );

  Widget _option({
    required GroupPrivacy privacy,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = value == privacy;
    return Material(
      color: selected ? const Color(0xFFF3F0FF) : const Color(0xFFF7F7FB),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => onChanged(privacy),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.primary : const Color(0xFFEAEAF1),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? AppColors.primary : const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle_rounded,
                    size: 20, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}
