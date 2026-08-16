import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/design/app_radius.dart';
import '../../application/support_controller.dart';
import '../../domain/support_request.dart';
import 'support_thread_screen.dart';

/// Yardım & Destek.
///
/// Menüde uzun süre "yakında" etiketiyle duran satırın arkası. İki şey var:
/// önce sık sorulanlar — çünkü çoğu sorunun cevabı beklemeye değmez — sonra
/// yazışma. Yazılan her talep yönetim panelindeki destek kuyruğuna düşüyor;
/// kimsenin okumadığı bir kutuya yazdırmıyoruz.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key, required this.controller});

  final SupportController controller;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.controller.load();
    });
  }

  Future<void> _compose() async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ComposeSheet(controller: widget.controller),
    );
    if (!mounted || sent != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Talebin destek ekibine iletildi. Cevap geldiğinde bildirim düşer.'),
      ),
    );
  }

  Future<void> _open(SupportRequest request) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SupportThreadScreen(
          controller: widget.controller,
          requestId: request.id,
          subject: request.subject,
        ),
      ),
    );
    if (!mounted) return;
    widget.controller.closeThread();
    await widget.controller.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Yardım & Destek'),
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _compose,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Destek yaz'),
      ),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          return RefreshIndicator(
            onRefresh: controller.load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
              children: [
                const _FaqSection(),
                const SizedBox(height: 24),
                const Text(
                  'Destek taleplerin',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Yazdıkların ve aldığın cevaplar burada durur. Bir üyeyi şikâyet etmek istiyorsan '
                  'paylaşımın altındaki bildir düğmesini kullan — o başka bir yere gider.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                if (controller.isLoading && controller.requests.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(child: CircularProgressIndicator()),
                  )
                // Liste alınamadıysa "talebin yok" yazmıyoruz: açtığı talebi
                // ekranda göremeyen üye onun kaybolduğunu düşünür.
                else if (controller.listError case final String message)
                  _Notice(
                    title: 'Talep listen alınamadı',
                    body: '$message\n\nBu, talebin olmadığı anlamına gelmez — liste sorulamadı. '
                        'Aşağı çekerek tekrar dene.',
                  )
                else if (controller.requests.isEmpty)
                  const _EmptyRequests()
                else
                  for (final request in controller.requests) ...[
                    _RequestTile(request: request, onTap: () => _open(request)),
                    const SizedBox(height: 8),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Sık sorulanlar. Cevabı gerçekten bildiğimiz sorular; "yakında" ya da
/// "ekibimiz size dönecektir" diyen bir madde buraya konmadı.
class _FaqSection extends StatelessWidget {
  const _FaqSection();

  static const _items = [
    (
      'Hesabımı nasıl silerim?',
      'Profil > Ayarlar > Hesabı sil. Silme talebinden sonra 30 gün süre işler; bu süre içinde '
          'giriş yaparsan silme iptal olur. Süre dolduğunda kimliğin gerçekten silinir, '
          'gizlenmez.',
    ),
    (
      'Paylaşımım neden kaldırıldı?',
      'Kaldırma kararı bildirimle gelir ve gerekçesi yazılıdır. Karara katılmıyorsan buradan '
          '"İçerik ve moderasyon" konusuyla yaz; kısıtlıyken de yazabilirsin. Kısıtlama '
          'paylaşımı durdurur, itirazı değil.',
    ),
    (
      'Giriş yapamıyorum, ne yapmalıyım?',
      'Önce şifre sıfırlamayı dene. E-postana ulaşamıyorsan buradan "Hesap ve giriş" konusuyla '
          'yaz; hesabına başkasının eriştiğini düşünüyorsan Profil > Güvenlik ekranından açık '
          'oturumların hepsini kapatabilirsin.',
    ),
    (
      'Çarşıdaki bir alışverişte sorun yaşadım.',
      'TurkSquare alıcı ile satıcı arasında taraf değildir ve ödemeyi tutmaz. Yine de ilanla, '
          'ihaleyle ya da bir üyenin davranışıyla ilgili sorunu "Çarşı ve ödeme" konusuyla yaz — '
          'kural ihlali varsa ilan ve hesap üzerinde işlem yapabiliriz.',
    ),
    (
      'Acil bir tehlike var.',
      'Hayati tehlike, yangın ya da suç durumunda önce 911\'i ara. TurkSquare bir acil durum '
          'hattı değildir. Topluluk güvenlik ekibine ulaşmak için menüdeki Yardım Çağrısı '
          'ekranını kullan; destek talebi acil durumlar için değil.',
    ),
    (
      'Cevap ne kadar sürer?',
      'Sabit bir süre sözü vermiyoruz — veremeyeceğimiz bir sözü ekrana yazmak, beklemeyi daha '
          'da kötü yapar. Talepler en uzun süredir bekleyen en üstte olacak şekilde sıraya '
          'girer; cevap yazıldığı anda bildirim düşer.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.all(AppRadius.card),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Text(
                'Sık sorulanlar',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            for (final (question, answer) in _items)
              ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                title: Text(
                  question,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                children: [
                  Text(
                    answer,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRequests extends StatelessWidget {
  const _EmptyRequests();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: const BorderRadius.all(AppRadius.card),
      ),
      child: const Column(
        children: [
          Icon(Icons.support_agent_outlined, size: 30, color: AppColors.textMuted),
          SizedBox(height: 8),
          Text(
            'Henüz destek talebin yok.',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Yukarıdaki sorularda cevabını bulamadıysan "Destek yaz" düğmesine bas.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.request, required this.onTap});

  final SupportRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (color, background) = switch (request.status) {
      SupportStatus.open => (const Color(0xFFB45309), const Color(0xFFFEF3C7)),
      SupportStatus.answered => (const Color(0xFF047857), const Color(0xFFECFDF5)),
      SupportStatus.closed => (AppColors.textSecondary, AppColors.canvas),
    };
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(AppRadius.card),
      child: Container(
        padding: const EdgeInsets.all(14),
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    request.status.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  supportTimeAgo(request.updatedAt),
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              request.subject,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              // Hiç yanıtlanmamış bir talebe "yanıt bekleniyor" demek yeterli
              // değil; hiç dokunulmadığını söylemek daha dürüst.
              request.lastStaffAt == null
                  ? '${request.topic.label} · henüz yanıtlanmadı'
                  : '${request.topic.label} · son yanıt ${supportTimeAgo(request.lastStaffAt!)}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposeSheet extends StatefulWidget {
  const _ComposeSheet({required this.controller});

  final SupportController controller;

  @override
  State<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<_ComposeSheet> {
  final _subject = TextEditingController();
  final _body = TextEditingController();
  SupportTopic _topic = SupportTopic.account;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final sent = await widget.controller.submit(
      topic: _topic,
      subject: _subject.text,
      body: _body.text,
    );
    if (!mounted || !sent) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          final valid =
              _subject.text.trim().length >= 3 && _body.text.trim().length >= 10;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceBorder,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Destek talebi',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Talebin destek ekibine gider. Uygulama sürümün ve cihaz platformun otomatik '
                  'eklenir — sormamıza gerek kalmasın diye.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<SupportTopic>(
                  initialValue: _topic,
                  decoration: const InputDecoration(
                    labelText: 'Konu',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final topic in SupportTopic.values)
                      DropdownMenuItem(value: topic, child: Text(topic.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _topic = value);
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  _topic.hint,
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _subject,
                  maxLength: 120,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Başlık',
                    hintText: 'Tek cümleyle sorun ne?',
                    border: OutlineInputBorder(),
                  ),
                ),
                TextField(
                  controller: _body,
                  maxLines: 6,
                  maxLength: 4000,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Ayrıntı',
                    hintText: 'Ne yaptın, ne bekliyordun, ne oldu?',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                if (controller.formError case final String message) ...[
                  const SizedBox(height: 4),
                  _Notice(
                    title: controller.tooManyOpen
                        ? 'Açık talep sınırındasın'
                        : 'Talep gönderilemedi',
                    body: message,
                  ),
                ],
                const SizedBox(height: 4),
                FilledButton(
                  onPressed: controller.isSending || !valid ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(50),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(AppRadius.button),
                    ),
                  ),
                  child: controller.isSending
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Gönder'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFB45309);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
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
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: const TextStyle(fontSize: 12.5, height: 1.4, color: color),
          ),
        ],
      ),
    );
  }
}

String supportTimeAgo(DateTime value) {
  final minutes = DateTime.now().difference(value).inMinutes;
  if (minutes < 1) return 'az önce';
  if (minutes < 60) return '$minutes dk önce';
  final hours = minutes ~/ 60;
  if (hours < 24) return '$hours saat önce';
  final days = hours ~/ 24;
  return days < 30 ? '$days gün önce' : '${days ~/ 30} ay önce';
}
