import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/state/async_state.dart';
import '../../../auth/application/auth_controller.dart';
import '../../application/profile_controller.dart';
import '../../domain/entities/user_profile.dart';
import 'archive_screen.dart';

/// Profil ve hesap ayarları.
///
/// Çeker menüdeki "Profil ve Hesap Ayarları" buraya geliyor. Üç şey bir arada:
/// profili kimin görebileceği, arşive kaldırılan paylaşımlar ve hesabın
/// kendisiyle ilgili iki geri dönüşü olan karar. Hiçbiri profil ekranının
/// sekmelerine gömülü değil - dondurma ve silme, yanlışlıkla dokunulacak yerde
/// durmamalı.
class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({
    super.key,
    required this.profileController,
    required this.authController,
    required this.onSignOut,
    this.onDeletePost,
  });

  final ProfileController profileController;
  final AuthController authController;

  /// Hesap kapandıktan sonra çağrılıyor: yerel oturum zaten silinmiş oluyor,
  /// bu geriye kalan tek işi yapıyor - üyeyi giriş ekranına götürmek.
  final Future<void> Function() onSignOut;

  /// Arşivden silme. Null ise arşiv ekranında "Sil" satırı hiç görünmüyor.
  final Future<void> Function(ProfilePost)? onDeletePost;

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  bool _closing = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      backgroundColor: AppColors.background,
      elevation: 0,
      title: const Text(
        'Profil ve Hesap Ayarları',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
      ),
    ),
    body: AnimatedBuilder(
      animation: widget.profileController,
      builder: (context, _) => switch (widget.profileController.state) {
        AsyncFailure<UserProfile>(:final message) => _Message(
          title: message,
          detail: 'Ayarları açabilmek için önce profilinin okunması gerekiyor.',
          onRetry: widget.profileController.load,
        ),
        AsyncData<UserProfile>(:final value) => _body(value),
        _ => const Center(child: CircularProgressIndicator()),
      },
    ),
  );

  Widget _body(UserProfile profile) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
    children: [
      const _SectionTitle('Profil gizliliği'),
      const SizedBox(height: 6),
      const Text(
        'Gizli profilde arkadaşın olmayanlar yalnızca adını ve fotoğrafını '
        'görür; paylaşımların, arkadaş listen ve rozetlerin kapalı kalır.',
        style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.textMuted),
      ),
      const SizedBox(height: 14),
      SegmentedButton<ProfileVisibility>(
        segments: const [
          ButtonSegment(
            value: ProfileVisibility.public,
            label: Text('Herkese açık'),
            icon: Icon(Icons.public),
          ),
          ButtonSegment(
            value: ProfileVisibility.friendsOnly,
            label: Text('Gizli'),
            icon: Icon(Icons.lock_outline),
          ),
        ],
        selected: {profile.visibility},
        onSelectionChanged: widget.profileController.isSaving
            ? null
            : (value) => _setVisibility(value.first),
      ),
      const SizedBox(height: 28),
      const _SectionTitle('İçeriklerin'),
      const SizedBox(height: 10),
      _SettingTile(
        icon: Icons.inventory_2_outlined,
        title: 'Arşiv',
        subtitle:
            'Akıştan kaldırdığın paylaşımlar. Beğenileri ve yorumları duruyor, '
            'seni istediğin zaman geri getirebilirsin.',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ArchiveScreen(
              controller: widget.profileController,
              profile: profile,
              onDelete: widget.onDeletePost,
            ),
          ),
        ),
      ),
      const SizedBox(height: 28),
      const _SectionTitle('Hesap'),
      const SizedBox(height: 10),
      _SettingTile(
        icon: Icons.pause_circle_outline_rounded,
        title: 'Hesabı dondur',
        subtitle:
            'Profilin ve paylaşımların görünmez olur, hiçbir şey silinmez. '
            'Tekrar giriş yaptığın an her şey yerine döner.',
        onTap: _closing ? null : _confirmFreeze,
      ),
      const SizedBox(height: 8),
      _SettingTile(
        icon: Icons.delete_outline_rounded,
        title: 'Hesabı sil',
        subtitle:
            'Hesabın $_graceDays gün sonra kalıcı olarak silinir. Bu süre '
            'içinde giriş yaparsan silme talebi iptal olur.',
        danger: true,
        onTap: _closing ? null : _confirmDelete,
      ),
      if (_closing) ...[
        const SizedBox(height: 20),
        const Center(child: CircularProgressIndicator()),
      ],
    ],
  );

  /// Sunucudaki `ACCOUNT_DELETION_GRACE_DAYS` ile aynı sayı.
  static const _graceDays = 30;

  Future<void> _setVisibility(ProfileVisibility visibility) async {
    final messenger = ScaffoldMessenger.of(context);
    await widget.profileController.updateVisibility(visibility);
    if (widget.profileController.state is AsyncFailure<UserProfile>) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          visibility == ProfileVisibility.public
              ? 'Profilin herkese açık.'
              : 'Profilin artık yalnızca arkadaşlarına açık.',
        ),
      ),
    );
  }

  Future<void> _confirmFreeze() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hesabın dondurulsun mu?'),
        content: const Text(
          'Profilin, paylaşımların ve yorumların kimseye görünmeyecek. '
          'Mesajların, arkadaşların ve rozetlerin silinmiyor.\n\n'
          'Bu cihazdaki ve diğer cihazlardaki oturumların kapanacak. Geri '
          'dönmek için tek yapman gereken tekrar giriş yapmak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Dondur'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _closing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.authController.freezeAccount();
    } catch (_) {
      if (!mounted) return;
      setState(() => _closing = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Hesap dondurulamadı. İstek sunucuya ulaşmadı; hesabın açık kaldı.',
          ),
        ),
      );
      return;
    }
    await widget.onSignOut();
  }

  Future<void> _confirmDelete() async {
    final password = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => const _DeleteAccountSheet(graceDays: _graceDays),
    );
    if (password == null || !mounted) return;
    setState(() => _closing = true);
    final messenger = ScaffoldMessenger.of(context);
    DateTime purgeAt;
    try {
      purgeAt = await widget.authController.requestAccountDeletion(password);
    } catch (error) {
      if (!mounted) return;
      setState(() => _closing = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '$error'.contains('INVALID_CREDENTIALS')
                ? 'Şifre doğrulanamadı. Hesabın olduğu gibi duruyor.'
                : 'Silme talebi gönderilemedi. Hesabın olduğu gibi duruyor.',
          ),
        ),
      );
      return;
    }
    if (mounted) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Silme talebin alındı'),
          content: Text(
            'Hesabın ${_dateLabel(purgeAt)} tarihinde kalıcı olarak '
            'silinecek. O güne kadar giriş yaparsan talep iptal olur ve her '
            'şey yerinde kalır.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Anladım'),
            ),
          ],
        ),
      );
    }
    await widget.onSignOut();
  }

  static String _dateLabel(DateTime value) {
    const months = [
      'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
      'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
    ];
    return '${value.day} ${months[value.month - 1]} ${value.year}';
  }
}

/// Silmeden önceki son adım. Şifre burada bir kez daha soruluyor: dondurmak
/// geri alınabilir bir karar, silmek değil - açık kalmış bir telefonu eline
/// geçiren biri bunu yapamasın.
class _DeleteAccountSheet extends StatefulWidget {
  const _DeleteAccountSheet({required this.graceDays});

  final int graceDays;

  @override
  State<_DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends State<_DeleteAccountSheet> {
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Hesabını sil',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Text(
          'Talebin alındığı andan itibaren hesabın kimseye görünmez ve '
          '${widget.graceDays} gün sonra kalıcı olarak silinir. Bu süre içinde '
          'giriş yaparsan silme iptal olur.\n\n'
          'Devam etmek için şifreni gir.',
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.45,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _password,
          obscureText: _obscure,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Şifren',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _password.text.isEmpty
              ? null
              : () => Navigator.pop(context, _password.text),
          style: FilledButton.styleFrom(backgroundColor: AppColors.accentRose),
          child: const Text('Hesabımı sil'),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
  );
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.accentRose : AppColors.profileAccent;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: danger ? AppColors.accentRose : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.detail, this.onRetry});

  final String title;
  final String detail;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 38, color: AppColors.textMuted),
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
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Yeniden dene'),
            ),
          ],
        ],
      ),
    ),
  );
}
