import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/entities/legal_document.dart';
import '../../domain/repositories/legal_repository.dart';

/// Kimlik istemeyen tek okuma.
///
/// Bu metinlerin bağlantısı giriş ekranının altında duruyor ve orada henüz
/// kimse giriş yapmış değil. `AuthInterceptor` jeton yoksa başlık eklemiyor,
/// sunucudaki yol da jeton beklemiyor.
class ApiLegalRepository implements LegalRepository {
  ApiLegalRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;

  @override
  Future<LegalDocument> getDocument(LegalDocumentKind kind) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        ApiEndpoints.legalDocument(kind.wire),
      );
      return LegalDocument.fromJson(response.data!['data'] as Map<String, dynamic>);
    } on ApiException catch (error) {
      // Yayımlanmamış olmak bir arıza değil. Ekranın bu ikisini ayırabilmesi
      // için hata tipi burada değişiyor; mesajı eşleştirmek, sunucudaki cümle
      // yeniden yazıldığı gün sessizce bozulurdu.
      if (error.code == 'LEGAL_NOT_PUBLISHED') {
        throw LegalDocumentNotPublished(kind);
      }
      rethrow;
    }
  }
}
