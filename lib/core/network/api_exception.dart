import 'package:dio/dio.dart';

class ApiException implements Exception {
  const ApiException({required this.message, this.statusCode});

  final String message;
  final int? statusCode;

  factory ApiException.fromDio(DioException error) {
    final responseData = error.response?.data;
    final serverMessage = responseData is Map<String, dynamic> ? responseData['message'] : null;
    final message = serverMessage is String ? serverMessage : _defaultMessage(error);
    return ApiException(message: message, statusCode: error.response?.statusCode);
  }

  static String _defaultMessage(DioException error) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout || DioExceptionType.receiveTimeout => 'The request timed out. Please try again.',
      DioExceptionType.connectionError => 'No internet connection. Check your network and try again.',
      DioExceptionType.badResponse when error.response?.statusCode == 401 => 'Your session has expired. Please sign in again.',
      DioExceptionType.badResponse => 'The server could not complete your request.',
      _ => 'Something went wrong. Please try again.',
    };
  }

  @override
  String toString() => message;
}
