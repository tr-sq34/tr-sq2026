import '../../../core/network/api_client.dart';

class CommunityHomeSummary {
  const CommunityHomeSummary({
    required this.city,
    required this.regionCode,
    required this.connections,
    required this.localPosts,
    required this.activeStories,
    required this.isNewMember,
  });
  final String? city;
  final String? regionCode;
  final int connections;
  final int localPosts;
  final int activeStories;
  final bool isNewMember;

  factory CommunityHomeSummary.fromJson(Map<String, dynamic> json) {
    final locality = json['locality'] as Map<String, dynamic>?;
    final counts = json['counts'] as Map<String, dynamic>? ?? const {};
    int count(String key) => (counts[key] as num?)?.toInt() ?? 0;
    return CommunityHomeSummary(
      city: locality?['city'] as String?,
      regionCode: locality?['regionCode'] as String?,
      connections: count('connections'),
      localPosts: count('localPosts'),
      activeStories: count('activeStories'),
      isNewMember: json['isNewMember'] == true,
    );
  }
}

class CommunityHomeRepository {
  CommunityHomeRepository(this._client);
  final ApiClient _client;

  Future<CommunityHomeSummary> fetch() async {
    final response = await _client.get<Map<String, dynamic>>(
      '/community/home/summary',
    );
    final payload = response.data?['data'] as Map<String, dynamic>? ?? const {};
    return CommunityHomeSummary.fromJson(payload);
  }
}
