import 'package:dio/dio.dart';

class ApiException implements Exception {
  const ApiException({required this.message, this.statusCode});

  final String message;
  final int? statusCode;

  factory ApiException.fromDio(DioException error) {
    final responseData = error.response?.data;
    final errorBody = responseData is Map<String, dynamic> ? responseData['error'] : null;
    final serverMessage = responseData is Map<String, dynamic>
        ? (responseData['message'] ??
            (errorBody is Map<String, dynamic> ? errorBody['message'] : null))
        : null;
    final message = serverMessage is String ? serverMessage : _defaultMessage(error);
    return ApiException(message: message, statusCode: error.response?.statusCode);
  }

  static String _defaultMessage(DioException error) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout || DioExceptionType.receiveTimeout => 'The request timed out. Please try again.',
      DioExceptionType.connectionError => _connectionMessage(error),
      DioExceptionType.badResponse when error.response?.statusCode == 401 => 'Your session has expired. Please sign in again.',
      DioExceptionType.badResponse => 'The server could not complete your request.',
      _ => 'Something went wrong. Please try again.',
    };
  }

  static String _connectionMessage(DioException error) {
    final detail = error.error.toString().toLowerCase();
    if (detail.contains('certificate') || detail.contains('handshake')) {
      return 'Güvenli sertifika bağlantısı doğrulanamadı. Cihaz tarihini kontrol edin.';
    }
    if (detail.contains('failed host lookup') || detail.contains('socket')) {
      return 'Sunucu adresine ulaşılamadı. Ağ veya DNS bağlantısını kontrol edin.';
    }
    return 'Sunucuya güvenli bağlantı kurulamadı. Lütfen tekrar deneyin.';
  }

  @override
  String toString() => message;
}
