/// Uygulamanın gösterdiği iki hukuki metin.
///
/// Sunucudaki `legal_documents.kind` ile birebir aynı; adları değişirse iki
/// tarafın da değişmesi gerekiyor.
enum LegalDocumentKind {
  terms('terms', 'Kullanım Koşulları'),
  privacy('privacy', 'Gizlilik Politikası');

  const LegalDocumentKind(this.wire, this.label);

  /// Sunucunun beklediği ad.
  final String wire;

  /// Ekranın başlığı metin gelmeden önce de yazılabilsin diye burada duruyor:
  /// "yükleniyor" ekranının bile hangi metni beklediğini söylemesi gerekiyor.
  final String label;
}

/// Panelden yazılıp panelden yayımlanan bir metnin yayımlanmış sürümü.
class LegalDocument {
  const LegalDocument({
    required this.kind,
    required this.version,
    required this.title,
    required this.body,
    required this.publishedAt,
    this.changeNote,
  });

  final LegalDocumentKind kind;

  /// Kaçıncı sürüm. Ekranın altında yazıyor: "hangi metni okuyorum" sorusunun
  /// tarihten daha kesin cevabı.
  final int version;
  final String title;
  final String body;
  final DateTime publishedAt;

  /// Bir önceki sürüme göre neyin değiştiği. Yazılmamışsa gösterilmiyor;
  /// "metin güncellendi" gibi bir cümle uydurmak, hiçbir şey dememekten daha
  /// kötü olurdu.
  final String? changeNote;

  factory LegalDocument.fromJson(Map<String, dynamic> json) {
    final wire = json['kind'] as String?;
    return LegalDocument(
      kind: LegalDocumentKind.values.firstWhere(
        (kind) => kind.wire == wire,
        orElse: () => LegalDocumentKind.terms,
      ),
      version: (json['version'] as num?)?.toInt() ?? 1,
      title: (json['title'] as String?)?.trim() ?? '',
      body: (json['body'] as String?) ?? '',
      publishedAt:
          DateTime.tryParse(json['publishedAt'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      changeNote: (json['changeNote'] as String?)?.trim().isNotEmpty == true
          ? (json['changeNote'] as String).trim()
          : null,
    );
  }
}

/// Metin henüz yayımlanmadı.
///
/// "Okunamadı" ile aynı şey değil ve ekranda da aynı görünmüyor: biri geçici
/// bir arıza, diğeri bir yetkilinin henüz yapmadığı bir iş. İkisini tek bir
/// "bir şeyler ters gitti" cümlesine indirmek, üyeye yeniden denemesi gereken
/// bir şey varmış gibi gösterirdi.
class LegalDocumentNotPublished implements Exception {
  const LegalDocumentNotPublished(this.kind);

  final LegalDocumentKind kind;

  @override
  String toString() => '${kind.label} henüz yayımlanmadı.';
}
