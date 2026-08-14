import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Sunucuya gitmeden isteği yakalayan taşıyıcı: hangi yola ne gönderildiğini
/// kaydeder, karşılığında hazır gövdeyi döner.
class RecordingAdapter implements HttpClientAdapter {
  RecordingAdapter(Object? body, {this.statusCode = 200}) : _bodies = [body];

  /// Arka arkaya gelen isteklere sırayla cevap veren biçimi: bir çağrının önce
  /// yazıp sonra okuduğu yerlerde iki ayrı gövde gerekiyor.
  RecordingAdapter.sequence(List<Object?> bodies, {this.statusCode = 200}) : _bodies = bodies;

  final List<Object?> _bodies;
  final int statusCode;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final payload = _bodies[requests.length.clamp(0, _bodies.length - 1)];
    requests.add(options);
    return ResponseBody.fromString(
      payload == null ? '' : jsonEncode(payload),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
