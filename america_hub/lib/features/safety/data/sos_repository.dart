import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../domain/sos_alert.dart';

abstract interface class SosRepository {
  /// Üyenin açık çağrısı, yoksa null.
  Future<SosAlert?> active();

  /// Çağrıyı gönderir. Aynı çağrıyı tekrar göndermek hata değil: sunucu ikinci
  /// bir kart açmıyor, yeni konumu açık olanın üzerine yazıyor. Panik düğmesine
  /// bir kez basılmaz.
  Future<void> trigger(SosDraft draft);

  /// Geri almak yıkıcı: sunucu noktayı siliyor ve yaşayan bütün erişimleri
  /// iptal ediyor. "Ben iyiyim" demek, konumun bir kartta gri görünmesi değil,
  /// var olmayı bırakması demek.
  Future<void> cancel(String id);
}

class ApiSosRepository implements SosRepository {
  ApiSosRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;

  @override
  Future<SosAlert?> active() async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.safetySosActive,
    );
    final data = response.data?['data'];
    return data == null ? null : SosAlert.fromJson(data as Map<String, dynamic>);
  }

  @override
  Future<void> trigger(SosDraft draft) =>
      _client.post<Map<String, dynamic>>(
        ApiEndpoints.safetySos,
        data: draft.toJson(),
      );

  @override
  Future<void> cancel(String id) =>
      _client.post<void>(ApiEndpoints.safetySosCancel(id));
}
