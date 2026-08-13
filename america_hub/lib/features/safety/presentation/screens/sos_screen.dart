import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/design/app_radius.dart';
import '../../application/sos_controller.dart';
import '../../domain/sos_alert.dart';

/// Yardım Çağrısı.
///
/// Uygulamadaki her ekran bir şey göstermek için var; bu ekran bir şey yapmak
/// için var, o yüzden diğerlerine benzemiyor: tek bir büyük düğme, en az sayıda
/// karar ve yanlış basıldığında geri alınabilen tek bir sonuç.
///
/// Konum hakkındaki söz ekranda yazılı duruyor. Üye neyi paylaştığını, kimin
/// görebildiğini ve ne zaman silineceğini çağrıyı göndermeden önce okuyor —
/// sonradan bir ayarlar sayfasında değil.
class SosScreen extends StatefulWidget {
  const SosScreen({super.key, required this.controller});

  final SosController controller;

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  final _noteController = TextEditingController();
  final _locationNoteController = TextEditingController();
  SosKind _kind = SosKind.personalSafety;
  bool _shareLocation = true;

  @override
  void initState() {
    super.initState();
    widget.controller.load();
  }

  @override
  void dispose() {
    _noteController.dispose();
    _locationNoteController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yardım çağrısı gönderilsin mi?'),
        content: Text(
          _shareLocation
              ? 'Çağrı güvenlik ekibine iletilecek ve konumun mühürlü olarak gönderilecek. '
                    'Konumu görebilmek için gerekçe yazmaları gerekiyor; çağrı kapandığında konum siliniyor.\n\n'
                    'Hayati tehlike varsa önce 911\'i ara.'
              : 'Çağrı güvenlik ekibine konumsuz iletilecek. Nerede olduğunu yalnızca yazdığın kadarıyla bilecekler.\n\n'
                    'Hayati tehlike varsa önce 911\'i ara.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            child: const Text('Gönder'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final sent = await widget.controller.trigger(
      kind: _kind,
      shareLocation: _shareLocation,
      note: _noteController.text,
      locationNote: _locationNoteController.text,
    );
    if (!mounted) return;
    if (sent) {
      _noteController.clear();
      _locationNoteController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yardım çağrın iletildi.')),
      );
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Çağrıyı geri al'),
        content: const Text(
          'Çağrı kapanacak ve paylaştığın konum silinecek. Yardıma hâlâ ihtiyacın varsa geri alma.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Geri al'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final done = await widget.controller.cancel();
    if (!mounted || !done) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Çağrın geri alındı, konumun silindi.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Yardım Çağrısı'),
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          if (controller.isLoading && controller.alert == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (controller.errorMessage case final String message)
                  _Notice(message: message, tone: _NoticeTone.error),
                if (controller.locationNotice case final String message)
                  _Notice(message: message, tone: _NoticeTone.warning),
                if (controller.alert case final SosAlert alert)
                  _OpenAlertCard(
                    alert: alert,
                    isBusy: controller.isSending,
                    onCancel: _cancel,
                  )
                else
                  ..._composer(controller),
                const SizedBox(height: 20),
                const _EmergencyFooter(),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _composer(SosController controller) => [
    const Text(
      'Ne oluyor?',
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
      ),
    ),
    const SizedBox(height: 4),
    const Text(
      'Çağrın TurkSquare güvenlik ekibine gider. Ekip çağrıyı üstlenir ve gerekirse konumunu açar.',
      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
    ),
    const SizedBox(height: 14),
    for (final kind in SosKind.values) ...[
      _KindTile(
        kind: kind,
        selected: _kind == kind,
        onTap: () => setState(() => _kind = kind),
      ),
      const SizedBox(height: 8),
    ],
    const SizedBox(height: 6),
    TextField(
      controller: _noteController,
      maxLines: 3,
      maxLength: 500,
      decoration: const InputDecoration(
        labelText: 'Kısaca ne olduğunu yaz (isteğe bağlı)',
        border: OutlineInputBorder(),
        alignLabelWithHint: true,
      ),
    ),
    const SizedBox(height: 8),
    _LocationSwitch(
      value: _shareLocation,
      onChanged: (value) => setState(() => _shareLocation = value),
    ),
    const SizedBox(height: 10),
    TextField(
      controller: _locationNoteController,
      maxLength: 200,
      decoration: const InputDecoration(
        labelText: 'Nerede olduğunu tarif et (isteğe bağlı)',
        helperText: 'Örn. "Kat 3, arka giriş" — konum kapalıysa tek bilgi bu olur.',
        border: OutlineInputBorder(),
      ),
    ),
    const SizedBox(height: 12),
    SizedBox(
      height: 62,
      child: FilledButton(
        onPressed: controller.isSending ? null : _send,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFDC2626),
          disabledBackgroundColor: const Color(0xFFDC2626).withValues(alpha: .5),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(AppRadius.button),
          ),
        ),
        child: controller.isSending
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.sos_rounded, color: Colors.white),
                  SizedBox(width: 10),
                  Text(
                    'Yardım İste',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
      ),
    ),
  ];
}

class _KindTile extends StatelessWidget {
  const _KindTile({
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final SosKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(AppRadius.card),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFEF2F2) : AppColors.surface,
          borderRadius: const BorderRadius.all(AppRadius.card),
          border: Border.all(
            color: selected ? const Color(0xFFDC2626) : AppColors.surfaceBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: selected ? const Color(0xFFDC2626) : AppColors.textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kind.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    kind.hint,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationSwitch extends StatelessWidget {
  const _LocationSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.all(AppRadius.card),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Konumumu paylaş',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
          // Sözün tamamı burada yazılı: üye neyi paylaştığını göndermeden önce
          // okuyor, sonradan bir ayarlar sayfasında değil.
          Text(
            value
                ? 'Konumun yalnızca bu çağrıyla gönderilir. Yetkililerin listesinde görünmez; '
                      'görmek isteyen kişinin gerekçe yazması gerekir, erişim 30 dakika sonra kapanır ve '
                      'çağrı kapandığında konum silinir. Kaç kişinin baktığını bu ekranda görürsün.'
                : 'Konum gönderilmeyecek. Ekip nerede olduğunu yalnızca aşağıya yazdığın kadarıyla bilecek.',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _OpenAlertCard extends StatelessWidget {
  const _OpenAlertCard({
    required this.alert,
    required this.isBusy,
    required this.onCancel,
  });

  final SosAlert alert;
  final bool isBusy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final acknowledged = alert.status == SosStatus.acknowledged;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: acknowledged ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
        borderRadius: const BorderRadius.all(AppRadius.card),
        border: Border.all(
          color: acknowledged ? const Color(0xFF10B981) : const Color(0xFFDC2626),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                acknowledged
                    ? Icons.verified_user_rounded
                    : Icons.notifications_active_rounded,
                color: acknowledged
                    ? const Color(0xFF047857)
                    : const Color(0xFFDC2626),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  acknowledged
                      ? 'Çağrın üstlenildi'
                      : 'Çağrın iletildi, bekleniyor',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            acknowledged
                ? 'Güvenlik ekibinden biri çağrınla ilgileniyor.'
                : 'Güvenlik ekibi çağrını görüyor. Ekran kendini yeniliyor, kapatmana gerek yok.',
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          _Row(label: 'Durum', value: alert.kindLabel),
          _Row(label: 'Gönderildi', value: _timeAgo(alert.createdAt)),
          if (alert.note case final String note) _Row(label: 'Notun', value: note),
          if (alert.locationNote case final String note)
            _Row(label: 'Tarif ettiğin yer', value: note),
          _Row(
            label: 'Konum',
            value: alert.locationShared
                ? 'Paylaşıldı, mühürlü'
                : 'Paylaşılmadı',
          ),
          if (alert.locationShared) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.all(AppRadius.card),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: Text(
                alert.activeLocationWatchers == 0
                    ? 'Şu anda konumunu kimse göremiyor. Bir yetkili görmek isterse gerekçe yazmak zorunda ve erişimi süreyle sınırlı.'
                    : 'Şu anda ${alert.activeLocationWatchers} yetkili konumunu görebiliyor. Erişimleri süre dolunca kendiliğinden kapanır.',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: alert.activeLocationWatchers == 0
                      ? FontWeight.w400
                      : FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: isBusy ? null : onCancel,
            icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
            label: const Text('İyiyim, çağrıyı geri al'),
          ),
        ],
      ),
    );
  }

  static String _timeAgo(DateTime value) {
    final minutes = DateTime.now().difference(value).inMinutes;
    if (minutes < 1) return 'az önce';
    if (minutes < 60) return '$minutes dakika önce';
    final hours = minutes ~/ 60;
    return hours < 24 ? '$hours saat ${minutes % 60} dakika önce' : '${hours ~/ 24} gün önce';
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _NoticeTone { error, warning }

class _Notice extends StatelessWidget {
  const _Notice({required this.message, required this.tone});

  final String message;
  final _NoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final color = tone == _NoticeTone.error
        ? const Color(0xFFDC2626)
        : const Color(0xFFB45309);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: const BorderRadius.all(AppRadius.card),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Text(message, style: TextStyle(fontSize: 12.5, color: color)),
    );
  }
}

/// TurkSquare bir acil durum servisi değil. Bunu ekranın altına yazmak,
/// üyenin 911 yerine burayı beklemesini önlemenin tek dürüst yolu.
class _EmergencyFooter extends StatelessWidget {
  const _EmergencyFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: const BorderRadius.all(AppRadius.card),
      ),
      child: const Text(
        'TurkSquare bir acil durum hattı değildir. Hayati tehlike, yangın ya da suç durumunda '
        'önce 911\'i ara. Buradaki çağrı, topluluk güvenlik ekibinin sana ulaşması içindir.',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
    );
  }
}
