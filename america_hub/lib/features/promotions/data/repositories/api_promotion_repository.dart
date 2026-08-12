import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../domain/entities/promotion.dart';
import '../../domain/repositories/promotion_repository.dart';

class ApiPromotionRepository implements PromotionRepository {
  ApiPromotionRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;

  @override
  Future<List<Promotion>> fetchActive() async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.communityPromotionsActive,
    );
    return _promotions(response.data!['data']);
  }

  @override
  Future<List<Promotion>> fetchMine() async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.communityMyPromotions,
    );
    return _promotions(response.data!['data']);
  }

  @override
  Future<void> submit(PromotionRequestDraft draft) => _client
      .post<Map<String, dynamic>>(
        ApiEndpoints.communityPromotions,
        data: draft.toJson(),
      );

  @override
  Future<void> recordEvent(String promotionId, PromotionEventKind kind) =>
      _client.post<void>(
        ApiEndpoints.communityPromotionEvents(promotionId),
        data: {'kind': kind.name},
      );

  List<Promotion> _promotions(Object? raw) => (raw as List<dynamic>)
      .map((item) => Promotion.fromJson(item as Map<String, dynamic>))
      .toList(growable: false);
}
