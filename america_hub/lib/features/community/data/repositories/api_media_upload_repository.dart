import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/network/api_client.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/entities/post_media_upload.dart';
import '../../domain/repositories/media_upload_repository.dart';
import '../../domain/services/media_upload_policy.dart';

/// Doğrudan özel depoya yükleme. Üyenin oturum jetonu yalnızca TurkSquare
/// API'sine gidiyor; kısa ömürlü depo bağlantısı yalnızca o API'nin döndürdüğü
/// başlıkları alıyor.
class ApiMediaUploadRepository implements MediaUploadRepository {
  ApiMediaUploadRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;

  @override
  Stream<MediaUploadProgress> upload(MediaUploadRequest request) async* {
    final error = MediaUploadPolicy.validate(request.media);
    if (error != null) {
      yield MediaUploadProgress(
        localId: request.media.localId,
        status: MediaUploadStatus.rejected,
        fraction: 0,
        errorMessage: error,
      );
      return;
    }
    try {
      yield MediaUploadProgress(
        localId: request.media.localId,
        status: MediaUploadStatus.pending,
        fraction: .05,
      );
      final bytes = await XFile(request.localUri).readAsBytes();
      if (bytes.lengthInBytes != request.media.sizeBytes) {
        throw StateError('Seçilen dosyanın boyutu değişti. Lütfen tekrar seçin.');
      }
      final digest = sha256.convert(bytes).toString();
      final presign = await _client.post<Map<String, dynamic>>(
        '/media/uploads/presign',
        data: {
          'kind': 'image',
          'contentType': request.media.mimeType,
          'fileName': request.media.fileName,
          'sizeBytes': request.media.sizeBytes,
          'sha256': digest,
        },
      );
      final data = presign.data?['data'] as Map<String, dynamic>?;
      if (data == null) throw StateError('Yükleme izni oluşturulamadı.');
      final uploadUrl = data['uploadUrl'] as String?;
      final uploadId = data['uploadId'] as String?;
      final mediaId = data['mediaId'] as String?;
      final headers = (data['requiredHeaders'] as Map?)?.cast<String, dynamic>();
      if (uploadUrl == null || uploadId == null || mediaId == null || headers == null) {
        throw StateError('Yükleme yanıtı geçersiz.');
      }
      yield MediaUploadProgress(
        localId: request.media.localId,
        status: MediaUploadStatus.uploading,
        fraction: .2,
      );
      await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 20),
        ),
      ).put<void>(
        uploadUrl,
        data: bytes,
        options: Options(
          headers: headers,
          contentType: request.media.mimeType,
          responseType: ResponseType.plain,
        ),
      );
      yield MediaUploadProgress(
        localId: request.media.localId,
        status: MediaUploadStatus.uploading,
        fraction: .75,
      );
      await _client.post<void>('/media/uploads/complete', data: {'uploadId': uploadId});

      for (var attempt = 0; attempt < 25; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        final statusResponse = await _client.get<Map<String, dynamic>>(
          '/media/$mediaId',
        );
        final status = statusResponse.data?['data'] as Map<String, dynamic>?;
        if (status == null) throw StateError('Medya tarama durumu okunamadı.');
        final state = status['status'] as String?;
        if (state == 'ready') {
          final url = status['url'] as String?;
          if (url == null) throw StateError('Güvenli medya URL’si oluşturulamadı.');
          yield MediaUploadProgress(
            localId: request.media.localId,
            status: MediaUploadStatus.ready,
            fraction: 1,
            media: PostMedia(
              id: mediaId,
              type: PostMediaType.image,
              url: url,
              thumbnailUrl: status['thumbnailUrl'] as String?,
            ),
          );
          return;
        }
        if (state == 'rejected') {
          yield MediaUploadProgress(
            localId: request.media.localId,
            status: MediaUploadStatus.rejected,
            fraction: 0,
            errorMessage: 'Dosya güvenlik doğrulamasını geçemedi.',
          );
          return;
        }
        yield MediaUploadProgress(
          localId: request.media.localId,
          status: MediaUploadStatus.uploading,
          fraction: .8 + ((attempt + 1) / 25) * .18,
        );
      }
      throw TimeoutException(
        'Görsel güvenlik taramasından 50 saniyede geçemedi. Biraz sonra tekrar dener misin?',
      );
    } catch (error) {
      yield MediaUploadProgress(
        localId: request.media.localId,
        status: MediaUploadStatus.failed,
        fraction: 0,
        errorMessage: mediaUploadFailureMessage(error),
      );
    }
  }
}

/// Yükleme neden olmadıysa onu söyleyen metin.
///
/// Burada tek bir cümle vardı: "Medya güvenli olarak yüklenemedi. Lütfen tekrar
/// deneyin." Depo isteği zorunlu bir başlık eksik diye reddedilse de, tarama
/// süresi dolsa da, telefonun bağlantısı gitse de ekranda aynı cümle çıkıyordu.
/// Üye tekrar deniyordu ve aynı şey oluyordu, çünkü tekrar denemek o hataların
/// hiçbirini çözmüyordu; bize kalan kayıt da hangisinin yaşandığını
/// söyleyemiyordu. Panelin ve akışın her yerinde geçerli olan kural burada da
/// geçerli: cevaplamayan tarafı ve nedenini yazmak, "olmadı" demekten iyidir.
String mediaUploadFailureMessage(Object error) {
  if (error is TimeoutException) {
    return error.message ?? 'Görsel taraması zaman aşımına uğradı.';
  }
  if (error is StateError) return error.message;
  if (error is! DioException) return 'Görsel yüklenemedi: $error';

  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
      return 'Görsel yüklenirken bağlantı zaman aşımına uğradı. '
          'Bağlantın yavaşsa daha küçük bir görselle deneyebilirsin.';
    case DioExceptionType.connectionError:
      return 'İnternet bağlantısı kurulamadı, görsel gönderilemedi.';
    case DioExceptionType.cancel:
      return 'Görsel yükleme iptal edildi.';
    case DioExceptionType.badCertificate:
      return 'Depolama sunucusunun sertifikası doğrulanamadı, görsel gönderilmedi.';
    case DioExceptionType.badResponse:
    case DioExceptionType.unknown:
      final status = error.response?.statusCode;
      final detail = _serverDetail(error.response?.data) ??
          (status == null ? error.message?.trim() : null);
      return [
        '${_stepLabel(error.requestOptions.path)} başarısız oldu',
        if (status != null) ' (HTTP $status)',
        '.',
        if (detail != null && detail.isNotEmpty) ' $detail',
      ].join();
  }
}

/// API'nin `{error:{code,message}}` gövdesi ya da Azure'un XML hata gövdesi.
/// İkisi de bir cümle üretemezse hiçbir şey uydurulmuyor.
String? _serverDetail(Object? data) {
  if (data is Map) {
    final error = data['error'];
    if (error is Map) {
      final message = error['message'];
      if (message is String && message.trim().isNotEmpty) return message.trim();
      final code = error['code'];
      if (code is String && code.trim().isNotEmpty) return code.trim();
    }
    return null;
  }
  if (data is String) {
    final code = RegExp(r'<Code>(.*?)</Code>').firstMatch(data)?.group(1);
    if (code != null && code.trim().isNotEmpty) {
      return 'Depolama servisi: ${code.trim()}.';
    }
  }
  return null;
}

/// Hatanın hangi adımda çıktığı. Dördü de "yükleme olmadı" ile biter ama
/// dördünün nedeni ve çözümü ayrıdır; depoya yazma adımı, yolu bizim API
/// yolumuz olmadığı için buradan ayrılıyor.
String _stepLabel(String path) {
  if (path.contains('/uploads/presign')) return 'Yükleme izni isteği';
  if (path.contains('/uploads/complete')) return 'Yüklemeyi tamamlama isteği';
  if (path.contains('/media/')) return 'Tarama durumu sorgusu';
  return 'Görselin depoya yazılması';
}
