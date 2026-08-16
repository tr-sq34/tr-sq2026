import '../entities/legal_document.dart';

abstract class LegalRepository {
  /// Yayımlanmış metni getirir.
  ///
  /// Henüz yayımlanmamışsa [LegalDocumentNotPublished] atar. Boş bir metin
  /// döndürmek, metnin boş olduğunu söylemek olurdu.
  Future<LegalDocument> getDocument(LegalDocumentKind kind);
}
