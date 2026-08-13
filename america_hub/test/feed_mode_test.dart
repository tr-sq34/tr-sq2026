import 'package:america_hub/core/pagination/cursor_page.dart';
import 'package:america_hub/features/community/application/community_feed_controller.dart';
import 'package:america_hub/features/community/data/repositories/mock_community_repository.dart';
import 'package:america_hub/features/community/domain/entities/community_post.dart';
import 'package:america_hub/features/community/domain/entities/feed_extensions.dart';
import 'package:america_hub/features/community/domain/repositories/community_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sekmenin gerçekten sunucuya sorup sormadığını görmek için: hangi kipin
/// istendiğini kaydediyor.
class _RecordingFeed implements FeedRepository {
  final List<FeedMode> asked = [];

  @override
  Future<CursorPage<CommunityPost>> fetchFeed({
    required FeedMode mode,
    String? cursor,
    int limit = 20,
  }) async {
    asked.add(mode);
    return CursorPage(
      items: [
        CommunityPost(
          id: '$mode-1',
          ownerId: 'demo',
          authorName: 'Demo',
          location: 'Austin, TX',
          timeLabel: 'şimdi',
          message: '$mode akışı',
          likes: 0,
          comments: 0,
        ),
      ],
    );
  }
}

void main() {
  test('sekme değişince akış sunucudan o kiple isteniyor', () async {
    final repository = MockCommunityRepository();
    final feed = _RecordingFeed();
    final controller = CommunityFeedController(
      repository: repository,
      feed: feed,
      commands: repository,
      interactions: repository,
      polls: repository,
    );

    await controller.loadInitial();
    // "Senin İçin" önbellekli depodan geliyor; sunucuya hiç gidilmiyor.
    expect(feed.asked, isEmpty);
    expect(controller.items, isNotEmpty);

    await controller.setMode(FeedMode.nearby);

    expect(feed.asked, [FeedMode.nearby]);
    expect(controller.mode, FeedMode.nearby);
    // Eski sekmenin paylaşımları ekranda kalmıyor: liste sıfırlanıp yeniden
    // dolduruluyor, yoksa "yakınındakiler" başlığı altında başka bir şehir durur.
    expect(controller.items.single.message, contains('nearby'));

    await controller.setMode(FeedMode.following);
    expect(feed.asked, [FeedMode.nearby, FeedMode.following]);

    controller.dispose();
  });

  test('yakınındakiler üyenin seçtiği eyaleti soruyor', () async {
    final texan = MockCommunityRepository(viewerRegion: () async => 'TX');
    final page = await texan.fetchFeed(mode: FeedMode.nearby);

    expect(page.items, isNotEmpty);
    expect(
      page.items.every((post) => post.location.endsWith(', TX')),
      isTrue,
      reason: 'Sekme eyalet demek; başka eyaletin paylaşımı buraya düşemez.',
    );
  });

  test('eyaleti olmayan üyeye yakınındakiler boş geliyor', () async {
    // Konum izlemediğimiz için tahmin edecek bir şey yok: şehrini yazmamış
    // birine gösterilecek "yakın" paylaşım da yok.
    final nomad = MockCommunityRepository(viewerRegion: () async => null);

    expect((await nomad.fetchFeed(mode: FeedMode.nearby)).items, isEmpty);
    expect((await nomad.fetchFeed(mode: FeedMode.forYou)).items, isNotEmpty);
  });
}
