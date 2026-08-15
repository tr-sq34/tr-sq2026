import 'dart:async';

import 'package:america_hub/features/community/data/repositories/api_media_upload_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Yükleme hatasının metne dönüşmesi. Sınanan şey metnin güzelliği değil, tek
/// bir özellik: ekranda çıkan cümle, başarısız olan adımı söylüyor mu.
void main() {
  DioException failed(String path, {int? status, Object? data}) => DioException(
        requestOptions: RequestOptions(path: path),
        response: status == null
            ? null
            : Response<Object?>(
                requestOptions: RequestOptions(path: path),
                statusCode: status,
                data: data,
              ),
        type: status == null ? DioExceptionType.unknown : DioExceptionType.badResponse,
      );

  const azureUrl =
      'https://tsmedia.blob.core.windows.net/community-media/uploads/quarantine/u/m?sig=x';

  test('sunucunun verdiği neden mesaja giriyor', () {
    final message = mediaUploadFailureMessage(
      failed('/media/uploads/complete', status: 400, data: {
        'error': {
          'code': 'UPLOAD_VALIDATION_FAILED',
          'message': 'Yüklenen dosya doğrulanamadı.',
        },
      }),
    );

    expect(message, contains('Yüklemeyi tamamlama isteği'));
    expect(message, contains('400'));
    expect(message, contains('Yüklenen dosya doğrulanamadı.'));
  });

  test('mesaj yoksa sunucunun hata kodu yazılıyor', () {
    final message = mediaUploadFailureMessage(
      failed('/media/uploads/presign', status: 500, data: {
        'error': {'code': 'MEDIA_UPLOAD_NOT_ACCEPTED'},
      }),
    );

    expect(message, contains('Yükleme izni isteği'));
    expect(message, contains('MEDIA_UPLOAD_NOT_ACCEPTED'));
  });

  test('depolama servisinin XML hata kodu okunuyor', () {
    final message = mediaUploadFailureMessage(
      failed(
        azureUrl,
        status: 400,
        data: '<?xml version="1.0" encoding="utf-8"?><Error>'
            '<Code>MissingRequiredHeader</Code>'
            '<Message>An HTTP header that is mandatory for this request is not specified.</Message>'
            '</Error>',
      ),
    );

    // Depoya yazma adımı, bizim API'mizin bir adımıyla karışmamalı: bu ikisinin
    // nedeni de çözümü de ayrı.
    expect(message, contains('depoya yazılması'));
    expect(message, contains('MissingRequiredHeader'));
  });

  test('tarama durumu sorgusu kendi adıyla anılıyor', () {
    final message = mediaUploadFailureMessage(
      failed('/media/6f1a0f1e-0000-4000-8000-000000000000', status: 404),
    );
    expect(message, contains('Tarama durumu sorgusu'));
  });

  test('ağ hatası sunucu hatası gibi gösterilmiyor', () {
    final message = mediaUploadFailureMessage(
      DioException(
        requestOptions: RequestOptions(path: azureUrl),
        type: DioExceptionType.connectionError,
      ),
    );
    expect(message, contains('İnternet bağlantısı'));
    expect(message, isNot(contains('HTTP')));
  });

  test('zaman aşımı kendi cümlesini koruyor', () {
    expect(
      mediaUploadFailureMessage(TimeoutException('Görsel taramadan geçemedi.')),
      contains('Görsel taramadan geçemedi.'),
    );
  });

  test('hiçbir hata türü boş ya da eski genel cümleyi üretmiyor', () {
    final errors = <Object>[
      ...DioExceptionType.values.map(
        (type) => DioException(requestOptions: RequestOptions(path: azureUrl), type: type),
      ),
      StateError('Yükleme yanıtı geçersiz.'),
      TimeoutException('bitti'),
      ArgumentError('beklenmeyen'),
    ];

    for (final error in errors) {
      final message = mediaUploadFailureMessage(error);
      expect(message.trim(), isNotEmpty, reason: '$error');
      expect(message, isNot(contains('Medya güvenli olarak yüklenemedi')), reason: '$error');
    }
  });
}
