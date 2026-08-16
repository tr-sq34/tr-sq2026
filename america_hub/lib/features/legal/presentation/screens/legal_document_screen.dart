import 'package:flutter/material.dart';

import '../../domain/entities/legal_document.dart';
import '../../domain/repositories/legal_repository.dart';

/// Kullanım Koşulları ve Gizlilik Politikası.
///
/// Giriş ekranının altında "Devam ederek Kullanım Koşulları ve Gizlilik
/// Politikası'nı kabul etmiş olursunuz" yazıyor ve iki bağlantının da altı
/// çiziliydi. İkisi de hiçbir yere gitmiyordu: uygulamada, panelde,
/// veritabanında böyle bir metin hiç olmadı. Üyeden okuyamadığı bir şeyi kabul
/// etmesi isteniyordu.
///
/// Metin panelden geliyor, koda gömülü değil: bir gizlilik politikası hukuki
/// bir taahhüt ve her değiştiğinde uygulamanın yeni sürümünü mağazadan
/// geçirmek, metnin günü geçmiş kalmasının en yaygın sebebi.
class LegalDocumentScreen extends StatefulWidget {
  const LegalDocumentScreen({
    super.key,
    required this.kind,
    required this.repository,
  });

  final LegalDocumentKind kind;
  final LegalRepository repository;

  @override
  State<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends State<LegalDocumentScreen> {
  LegalDocument? _document;
  bool _loading = true;

  /// Yayımlanmamış olmak ile okunamamak ayrı iki cevap, o yüzden ayrı iki alan.
  bool _notPublished = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _notPublished = false;
      _error = null;
    });
    try {
      final document = await widget.repository.getDocument(widget.kind);
      if (!mounted) return;
      setState(() {
        _document = document;
        _loading = false;
      });
    } on LegalDocumentNotPublished {
      if (!mounted) return;
      setState(() {
        _notPublished = true;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: Text(
          _document?.title ?? widget.kind.label,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_notPublished) {
      return _Explanation(
        icon: Icons.description_outlined,
        title: '${widget.kind.label} henüz yayımlanmadı.',
        // Boş bir sayfa, metnin boş olduğunu söylerdi. Burada eksik olanın ne
        // olduğu ve kimde olduğu yazıyor; üyenin yeniden deneyecek bir şeyi yok.
        message:
            'Bu metin hazırlanıyor. Yayımlandığında burada görünecek; o zamana '
            'kadar sorularını Yardım ve Destek ekranından iletebilirsin.',
        onRetry: _load,
        retryLabel: 'Yeniden bak',
      );
    }
    if (_error != null) {
      return _Explanation(
        icon: Icons.cloud_off_rounded,
        title: '${widget.kind.label} şu an açılamadı.',
        message:
            'Metin sunucudan okunamadı, yani burada gördüğün boşluk metnin '
            'kendisi değil. Sebebi: $_error',
        onRetry: _load,
        retryLabel: 'Tekrar dene',
      );
    }

    final document = _document!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        ..._blocks(document.body),
        const SizedBox(height: 28),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),
        const SizedBox(height: 12),
        // Hangi metni okuduğunun kesin karşılığı. "Güncellendi" demek yerine
        // sürüm ve tarih yazıyor.
        Text(
          'Sürüm ${document.version} · ${_formatDate(document.publishedAt)} tarihinde yayımlandı',
          style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
        ),
        if (document.changeNote != null) ...[
          const SizedBox(height: 6),
          Text(
            'Bu sürümde değişen: ${document.changeNote}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        ],
      ],
    );
  }

  /// Panelde yazılan metnin biçimi: boş satır paragraf ayırıyor, satır başındaki
  /// "## " bir ara başlık yapıyor. Paneldeki önizleme de aynı iki kuralı
  /// uyguluyor, ki editör yazdığının nasıl görüneceğini yayımlamadan önce
  /// görsün.
  List<Widget> _blocks(String body) {
    final paragraphs = body
        .split(RegExp(r'\n\s*\n'))
        .map((paragraph) => paragraph.trim())
        .where((paragraph) => paragraph.isNotEmpty);

    final widgets = <Widget>[];
    for (final paragraph in paragraphs) {
      if (paragraph.startsWith('## ')) {
        widgets.add(
          Padding(
            padding: EdgeInsets.only(top: widgets.isEmpty ? 0 : 20, bottom: 8),
            child: Text(
              paragraph.substring(3).trim(),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        );
      } else {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              paragraph,
              style: const TextStyle(
                fontSize: 14,
                height: 1.6,
                color: Color(0xFF334155),
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  String _formatDate(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
}

class _Explanation extends StatelessWidget {
  const _Explanation({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRetry,
    required this.retryLabel,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: const Color(0xFF94A3B8)),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}
