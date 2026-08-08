import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/network/api_client.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/entities/post_media_upload.dart';
import '../../domain/repositories/media_upload_repository.dart';
import '../../domain/services/media_upload_policy.dart';

/// Direct-to-private-S3 media upload. The user token is deliberately sent only
/// to TurkSquare's API; the short-lived S3 URL receives only the signed upload
/// headers returned by that API.
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
      throw TimeoutException('Medya taraması zaman aşımına uğradı.');
    } catch (_) {
      yield MediaUploadProgress(
        localId: request.media.localId,
        status: MediaUploadStatus.failed,
        fraction: 0,
        errorMessage: 'Medya güvenli olarak yüklenemedi. Lütfen tekrar deneyin.',
      );
    }
  }
}
