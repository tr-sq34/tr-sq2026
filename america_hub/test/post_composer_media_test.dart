import 'dart:convert';

import 'package:america_hub/features/community/application/community_feed_controller.dart';
import 'package:america_hub/features/community/application/media_upload_controller.dart';
import 'package:america_hub/features/community/data/repositories/mock_community_repository.dart';
import 'package:america_hub/features/community/domain/entities/community_post.dart';
import 'package:america_hub/features/community/domain/entities/create_post_draft.dart';
import 'package:america_hub/features/community/domain/entities/post_media_upload.dart';
import 'package:america_hub/features/community/domain/repositories/media_upload_repository.dart';
import 'package:america_hub/features/community/presentation/screens/post_composer_screen.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

/// Seçiciye dokunulduğunda tek bir PNG dönen sahte galeri. Gerçek galeri bir
/// platform kanalı; widget testinde açılamaz, ama bu ekranın hatası da zaten
/// seçicide değil, seçimden sonra olanlarda.
class _FakeGallery extends ImagePickerPlatform {
  /// 1x1 saydam PNG. Ekran gercek baytlari cozuyor; uydurma baytlar burada
  /// testin kendi hatasi olurdu.
  static final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
    'hQGAhKmMIQAAAABJRU5ErkJggg==',
  );

  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async => [
    XFile.fromData(
      _png,
      name: 'ekran-goruntusu.png',
      mimeType: 'image/png',
      path: '/tmp/ekran-goruntusu.png',
    ),
  ];
}

/// Yüklemenin nasıl bittiğini test yazıyor.
class _ScriptedUploads implements MediaUploadRepository {
  _ScriptedUploads(this.outcome);

  /// Son adımda ne olacağı. `null` ise yükleme hiç bitmiyor (yükleniyor
  /// durumunda kalıyor).
  final MediaUploadProgress Function(String localId)? outcome;

  final List<String> declaredMimeTypes = [];

  @override
  Stream<MediaUploadProgress> upload(MediaUploadRequest request) async* {
    declaredMimeTypes.add(request.media.mimeType);
    yield MediaUploadProgress(
      localId: request.media.localId,
      status: MediaUploadStatus.uploading,
      fraction: .3,
    );
    if (outcome == null) return;
    yield outcome!(request.media.localId);
  }
}

class _CapturingCommunity extends MockCommunityRepository {
  final List<CreatePostDraft> drafts = [];

  @override
  Future<CommunityPost> createPost(CreatePostDraft draft) {
    drafts.add(draft);
    return super.createPost(draft);
  }
}

Future<
  ({_CapturingCommunity community, _ScriptedUploads uploads, MediaUploadController controller})
>
_pumpComposer(
  WidgetTester tester, {
  required MediaUploadProgress Function(String localId)? outcome,
}) async {
  final community = _CapturingCommunity();
  final uploads = _ScriptedUploads(outcome);
  final controller = MediaUploadController(repository: uploads);
  await tester.pumpWidget(
    MaterialApp(
      home: PostComposerScreen(
        feedController: CommunityFeedController(
          repository: community,
          feed: community,
          commands: community,
          interactions: community,
          polls: community,
        ),
        mediaUploadController: controller,
      ),
    ),
  );
  await tester.pump();
  return (community: community, uploads: uploads, controller: controller);
}

Future<void> _pickAPhoto(WidgetTester tester) async {
  await tester.tap(find.text('Fotoğraf'));
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _tapPublish(WidgetTester tester) async {
  await tester.tap(find.text('Paylaş'));
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  setUp(() => ImagePickerPlatform.instance = _FakeGallery());

  // Bu, üyenin bildirdiği hatanın kendisi: görsel seçiliyor, yükleme
  // sunucudan 400 alıyor, ekranda hiçbir şey değişmiyor ve "Paylaş" yalnızca
  // yazıyı gönderiyor. Görsel düşerse paylaşım da durmalı.
  testWidgets('yuklenemeyen gorselle paylasim yazi olarak gitmiyor', (
    tester,
  ) async {
    final harness = await _pumpComposer(
      tester,
      outcome: (localId) => MediaUploadProgress(
        localId: localId,
        status: MediaUploadStatus.failed,
        fraction: 0,
        errorMessage: 'Yükleme izni isteği başarısız oldu (HTTP 400).',
      ),
    );

    await _pickAPhoto(tester);
    await tester.enterText(find.byType(TextField).first, 'Akşam yemeği');
    await tester.pump();
    await _tapPublish(tester);

    expect(harness.community.drafts, isEmpty);
    expect(
      find.text('Yükleme izni isteği başarısız oldu (HTTP 400).'),
      findsOneWidget,
    );
  });

  testWidgets('yukleme surerken paylasim bekliyor, sessizce gitmiyor', (
    tester,
  ) async {
    final harness = await _pumpComposer(tester, outcome: null);

    await _pickAPhoto(tester);
    await tester.enterText(find.byType(TextField).first, 'Akşam yemeği');
    await tester.pump();
    await _tapPublish(tester);

    expect(harness.community.drafts, isEmpty);
    expect(
      find.text('Görsel hâlâ yükleniyor. Bitmesini bekleyip paylaşabilirsin.'),
      findsOneWidget,
    );
  });

  testWidgets('yukleme bitince paylasim sunucudaki medya kimligini tasiyor', (
    tester,
  ) async {
    final harness = await _pumpComposer(
      tester,
      outcome: (localId) => MediaUploadProgress(
        localId: localId,
        status: MediaUploadStatus.ready,
        fraction: 1,
        media: const PostMedia(
          id: 'e3b0c442-0000-4000-8000-000000000001',
          type: PostMediaType.image,
          url: 'https://cdn.turksquare.com/safe/1.jpg',
        ),
      ),
    );

    await _pickAPhoto(tester);
    await _tapPublish(tester);

    expect(harness.community.drafts, hasLength(1));
    final media = harness.community.drafts.single.media;
    expect(media, hasLength(1));
    // Yerel dosya yolu değil, sunucunun verdiği kimlik: paylaşımı yaratan uç
    // yalnızca bunu kabul ediyor.
    expect(media.single.id, 'e3b0c442-0000-4000-8000-000000000001');
  });

  // Beyan edilen tür sabit 'image/jpeg' idi. Galeriden gelen PNG'yi JPEG diye
  // göndermek, taramayı yapan tarafa beyan ettiğinden başka bir dosya vermek
  // demek.
  testWidgets('secilen dosyanin gercek turu beyan ediliyor', (tester) async {
    final harness = await _pumpComposer(tester, outcome: null);

    await _pickAPhoto(tester);

    expect(harness.uploads.declaredMimeTypes, ['image/png']);
  });
}
