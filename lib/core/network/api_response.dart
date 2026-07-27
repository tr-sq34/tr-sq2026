class ApiResponse<T> {
  const ApiResponse({required this.data, this.nextCursor});
  final T data;
  final String? nextCursor;

  factory ApiResponse.fromJson(Map<String, dynamic> json, T Function(Object? raw) decode) {
    return ApiResponse(data: decode(json['data']), nextCursor: json['meta'] is Map<String, dynamic> ? json['meta']['nextCursor'] as String? : null);
  }
}
