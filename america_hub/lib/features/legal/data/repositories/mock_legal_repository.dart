import '../../domain/entities/legal_document.dart';
import '../../domain/repositories/legal_repository.dart';

/// Sahte servislerle çalışırken gösterilen metin.
///
/// Gerçek metin panelden yazılıyor ve buraya bir kopyası konmuyor: iki yerde
/// duran bir gizlilik politikasının biri er geç eskir, ve eskiyen kopyanın
/// hangisi olduğu belli olmaz. Buradaki metin kısa ve ne olduğunu söylüyor.
class MockLegalRepository implements LegalRepository {
  const MockLegalRepository();

  @override
  Future<LegalDocument> getDocument(LegalDocumentKind kind) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return LegalDocument(
      kind: kind,
      version: 1,
      title: kind.label,
      body:
          'Bu, sahte servislerle çalışırken gösterilen örnek metindir.\n\n'
          'Gerçek ${kind.label} yönetim panelindeki Yasal Metinler ekranından '
          'yazılır ve oradan yayımlanır. Uygulama yalnızca yayımlanmış olanı '
          'okur.',
      publishedAt: DateTime(2026, 1, 1),
      changeNote: null,
    );
  }
}
