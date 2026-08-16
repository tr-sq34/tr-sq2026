import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/design/app_radius.dart';
import '../../application/notifications_controller.dart';
import '../../domain/entities/notification_preference.dart';

/// Bildirim Tercihleri.
///
/// Menüde bu satır bugüne kadar hiçbir yere gitmiyordu ve altında "Anlık
/// bildirim & e-posta" yazıyordu — ikisi de gönderilmiyor. Ekranın yaptığı iş
/// gerçek olanla sınırlı: uygulama içindeki zilde hangi türün görüneceği.
/// Olmayan bir push ayarını buraya koymak, kapattığını sanan üyeye hiçbir şey
/// değiştirmemiş bir anahtar vermek olurdu.
class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key, required this.controller});

  final NotificationsController controller;

  @override
  State<NotificationPreferencesScreen> createState() => _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState extends State<NotificationPreferencesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.controller.loadPreferences();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Bildirim Tercihleri'),
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          final preferences = controller.preferences;

          if (controller.isPreferencesLoading && preferences == null) {
            return const Center(child: CircularProgressIndicator());
          }
          // Okunamadıysa hepsi açık gösterilmiyor: üyenin kapattığı bir türü
          // açık göstermek, ayarının silindiğini düşündürür.
          if (preferences == null) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: _Notice(
                message: '${controller.preferencesError ?? 'Bildirim tercihlerin okunamadı.'}\n\n'
                    'Bu, tercihlerinin silindiği anlamına gelmez — okunamadı. '
                    'Kaydedilmiş ayarların sunucuda duruyor.',
                onRetry: () => controller.loadPreferences(),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: controller.loadPreferences,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                const _Intro(),
                const SizedBox(height: 14),
                // Kaydetme hatası listenin başında: anahtarın geri dönmesini
                // gören üyenin sebebi araması gerekmemeli.
                if (controller.preferencesError case final String message) ...[
                  _Notice(message: message),
                  const SizedBox(height: 14),
                ],
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: const BorderRadius.all(AppRadius.card),
                    border: Border.all(color: AppColors.surfaceBorder),
                  ),
                  child: Column(
                    children: [
                      for (final kind in NotificationPreferenceKind.values) ...[
                        if (kind != NotificationPreferenceKind.values.first)
                          const Divider(height: 1, color: AppColors.surfaceBorder),
                        _PreferenceTile(
                          kind: kind,
                          enabled: preferences.isEnabled(kind),
                          busy: controller.savingKind == kind,
                          onChanged: (value) => controller.setPreference(kind, value),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _Summary(muted: preferences.mutedCount),
                const SizedBox(height: 14),
                const _AlwaysOn(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.profileTint,
        borderRadius: const BorderRadius.all(AppRadius.card),
        border: Border.all(color: AppColors.profileBorder),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bu ayarlar uygulama içindeki zil için',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.profileAccent,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'TurkSquare şu an telefonuna anlık bildirim ya da e-posta göndermiyor. '
            'Burada kapattığın tür, uygulamayı açtığında zilde görünmez.',
            style: TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _PreferenceTile extends StatelessWidget {
  const _PreferenceTile({
    required this.kind,
    required this.enabled,
    required this.busy,
    required this.onChanged,
  });

  final NotificationPreferenceKind kind;
  final bool enabled;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kind.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  kind.description,
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
          // Kaydedilirken anahtar dönmeye devam ediyor ama dokunulamıyor:
          // gidiş yolundaki ikinci dokunuş, sunucuya ters sırada varabilir.
          SizedBox(
            width: 52,
            child: busy
                ? const Center(
                    child: SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Switch(
                    value: enabled,
                    activeThumbColor: AppColors.primary,
                    onChanged: onChanged,
                  ),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.muted});

  final int muted;

  @override
  Widget build(BuildContext context) {
    return Text(
      muted == 0
          ? 'Bütün bildirim türleri açık.'
          : '$muted tür kapalı. Kapalı geçen sürede olanlar silinmiyor — tekrar açtığında birikmiş olanı görürsün.',
      style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.textMuted),
    );
  }
}

class _AlwaysOn extends StatelessWidget {
  const _AlwaysOn();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: const BorderRadius.all(AppRadius.card),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Kapatılamayan iki bildirim',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Destek talebine gelen yanıt ve hesabını ilgilendiren duyurular her zaman zilde görünür. '
            'Biri kendi sorduğun sorunun cevabı, diğeri hesabınla ilgili bilmen gereken bir şey; '
            'ikisini de kaçırman "tercih" sayılamaz.',
            style: TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFB45309);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: const BorderRadius.all(AppRadius.card),
        border: Border.all(color: color.withValues(alpha: .32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(fontSize: 12.5, height: 1.4, color: color),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(onPressed: onRetry, child: const Text('Tekrar dene')),
          ],
        ],
      ),
    );
  }
}
