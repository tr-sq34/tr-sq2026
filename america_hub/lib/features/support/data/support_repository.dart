import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../domain/support_request.dart';

abstract interface class SupportRepository {
  /// Üyenin kendi talepleri, en son hareket eden en üstte.
  Future<List<SupportRequest>> list();

  /// Tek bir talebin bütün yazışması.
  Future<SupportRequest> thread(String id);

  /// Yeni talep açar ve talebin kimliğini döndürür. Aynı taslak iki kez
  /// gönderilirse sunucu ikinci talebi açmıyor; taslaktaki `clientToken`
  /// sayesinde ilkinin kimliği geri geliyor.
  Future<String> create(SupportRequestDraft draft);

  /// Açık bir talebe ek yazar. Kapanmış talebe yazılamaz — sunucu 409 döner ve
  /// ekran üyeye yeni talep açmasını söyler.
  Future<void> reply(String id, String body);
}

class ApiSupportRepository implements SupportRepository {
  ApiSupportRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;

  @override
  Future<List<SupportRequest>> list() async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.supportRequests,
    );
    final data = response.data?['data'] as List<dynamic>? ?? const [];
    return data
        .map((item) => SupportRequest.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<SupportRequest> thread(String id) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.supportRequest(id),
    );
    return SupportRequest.fromJson(
      response.data?['data'] as Map<String, dynamic>? ?? const {},
    );
  }

  @override
  Future<String> create(SupportRequestDraft draft) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.supportRequests,
      data: draft.toJson(),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? const {};
    return data['id'] as String? ?? '';
  }

  @override
  Future<void> reply(String id, String body) => _client.post<Map<String, dynamic>>(
    ApiEndpoints.supportRequestMessages(id),
    data: {'body': body.trim()},
  );
}
