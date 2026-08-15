import 'dart:async';

import 'package:america_hub/core/pagination/cursor_page.dart';
import 'package:america_hub/core/pagination/paged_controller.dart';
import 'package:america_hub/features/community/application/community_feed_controller.dart';
import 'package:america_hub/features/community/data/repositories/mock_community_repository.dart';
import 'package:america_hub/features/community/domain/entities/community_post.dart';
import 'package:america_hub/features/community/domain/entities/feed_extensions.dart';
import 'package:america_hub/features/community/domain/repositories/community_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cevabı elimizde tutan akış.
///
/// Sekmelerin derdi zamanlamaydı: hangi cevabın hangi sekmeye ait olduğu,
/// cevaplar sırasız geldiğinde karışıyordu. O yüzden burada her istek bekliyor;
/// hangisinin ne zaman döneceğine sınama karar veriyor.
class _ControlledFeed implements FeedRepository {
  final List<FeedMode> asked = [];
  final List<(FeedMode, Completer<CursorPage<CommunityPost>>)> _pending = [];

  @override
  Future<CommunityPost> fetchPost(String postId) async =>
      throw UnimplementedError();

  @override
  Future<CursorPage<CommunityPost>> fetchFeed({
    required FeedMode mode,
    String? cursor,
    int limit = 20,
  }) {
    asked.add(mode);
    final completer = Completer<CursorPage<CommunityPost>>();
    _pending.add((mode, completer));
    return completer.future;
  }

  void answer(FeedMode mode) {
    final entry = _pending.firstWhere((item) => item.$1 == mode);
    _pending.remove(entry);
    entry.$2.complete(
      CursorPage(
        items: [
          CommunityPost(
            id: '${mode.name}-1',
            ownerId: 'demo',
            authorName: 'Demo',
            location: 'Austin, TX',
            timeLabel: 'şimdi',
            message: '${mode.name} akışı',
            likes: 0,
            comments: 0,
          ),
        ],
      ),
    );
  }

  void refuse(FeedMode mode) {
    final entry = _pending.firstWhere((item) => item.$1 == mode);
    _pending.remove(entry);
    entry.$2.completeError(Exception('sunucu yok'));
  }
}

/// İstediği anda cevap veren akış: sırayla ilerleyen sınamalar için.
class _InstantFeed implements FeedRepository {
  final List<FeedMode> asked = [];

  @override
  Future<CommunityPost> fetchPost(String postId) async =>
      throw UnimplementedError();

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
          id: '${mode.name}-1',
          ownerId: 'demo',
          authorName: 'Demo',
          location: 'Austin, TX',
          timeLabel: 'şimdi',
          message: '${mode.name} akışı',
          likes: 0,
          comments: 0,
        ),
      ],
    );
  }
}

CommunityFeedController _controller(FeedRepository feed) {
  final repository = MockCommunityRepository();
  return CommunityFeedController(
    repository: repository,
    feed: feed,
    commands: repository,
    interactions: repository,
    polls: repository,
  );
}

void main() {
  test('geri dönülen sekme okunmuş listesiyle açılıyor', () async {
    final feed = _InstantFeed();
    final controller = _controller(feed);

    await controller.load();
    await controller.setMode(FeedMode.nearby);
    expect(feed.asked, [FeedMode.nearby]);

    await controller.setMode(FeedMode.forYou);
    await controller.setMode(FeedMode.nearby);

    // Sunucuya ikinci kez gidilmiyor: iki dakikadan yeni bir liste elde varken
    // üyeyi boş ekranda bekletmek, okunmuş bir sayfayı saklamak olurdu.
    expect(feed.asked, [FeedMode.nearby]);
    expect(controller.items.single.message, contains('nearby'));
    expect(controller.state, PagedLoadState.loaded);

    controller.dispose();
  });

  test('kapalı sekmenin listesi kaydırma sırasında da elde duruyor', () async {
    final controller = _controller(_InstantFeed());

    await controller.load();
    final forYou = controller.items;
    await controller.setMode(FeedMode.following);

    // Yatay kaydırırken iki sayfa aynı anda ekranda: karşıya geçen sayfanın
    // bir an boş görünmesi, sekmenin boş olduğunu söylemek gibi okunuyordu.
    expect(controller.itemsFor(FeedMode.forYou), forYou);
    expect(controller.itemsFor(FeedMode.following).single.message,
        contains('following'));
    // Hiç açılmamış sekme hakkında söylenecek bir şey yok.
    expect(controller.itemsFor(FeedMode.nearby), isEmpty);

    controller.dispose();
  });

  test('hızlı sekme değiştiren üyede son sekme doluyor', () async {
    final feed = _ControlledFeed();
    final controller = _controller(feed);

    // Üye şeridi tek hamlede geçiyor: ilk sekmenin isteği daha yola çıkmadan
    // ikincisi seçiliyor. Eskiden süren yükleme yüzünden ikinci istek sessizce
    // düşüyor ve o sekme hiç dolmuyordu.
    unawaited(controller.setMode(FeedMode.nearby));
    unawaited(controller.setMode(FeedMode.following));
    await pumpEventQueue();

    expect(feed.asked, [FeedMode.following]);
    feed.answer(FeedMode.following);
    await pumpEventQueue();

    expect(controller.mode, FeedMode.following);
    expect(controller.items.single.message, contains('following'));

    controller.dispose();
  });

  test('geride bırakılan cevap yeni sekmeye yazılmıyor', () async {
    final feed = _ControlledFeed();
    final controller = _controller(feed);

    unawaited(controller.setMode(FeedMode.nearby));
    await pumpEventQueue();
    expect(feed.asked, [FeedMode.nearby]);

    // İstek yoldayken sekme değişti; gelen cevap artık kimsenin beklemediği
    // bir liste. "Takip ettiklerin" sekmesinde bir an "Yakınındakiler"
    // paylaşımları beliriyordu.
    unawaited(controller.setMode(FeedMode.following));
    feed.answer(FeedMode.nearby);
    await pumpEventQueue();

    expect(controller.items, isEmpty);
    expect(feed.asked, [FeedMode.nearby, FeedMode.following]);

    feed.answer(FeedMode.following);
    await pumpEventQueue();
    expect(controller.items.single.message, contains('following'));

    controller.dispose();
  });

  test('cevapsız kalan sekme ötekilerin listesini silmiyor', () async {
    final feed = _ControlledFeed();
    final controller = _controller(feed);

    await controller.load();
    expect(controller.items, isNotEmpty);
    final forYou = controller.items;

    unawaited(controller.setMode(FeedMode.nearby));
    await pumpEventQueue();
    feed.refuse(FeedMode.nearby);
    await pumpEventQueue();

    // Hata artık kendi sekmesinin içinde: şerit de öteki sekmelerin listesi de
    // yerinde duruyor, üye çalışan sekmeye geçebiliyor.
    expect(controller.hasFailedMode(FeedMode.nearby), isTrue);
    expect(controller.hasFailedMode(FeedMode.forYou), isFalse);
    expect(controller.isLoadingMode(FeedMode.nearby), isFalse);
    expect(controller.itemsFor(FeedMode.forYou), forYou);

    controller.dispose();
  });

  test('yükleniyor ile gerçekten boş aynı şey sayılmıyor', () async {
    final feed = _ControlledFeed();
    final controller = _controller(feed);

    unawaited(controller.setMode(FeedMode.following));
    await pumpEventQueue();

    expect(controller.isLoadingMode(FeedMode.following), isTrue);
    expect(controller.hasFailedMode(FeedMode.following), isFalse);

    feed.answer(FeedMode.following);
    await pumpEventQueue();

    expect(controller.isLoadingMode(FeedMode.following), isFalse);

    controller.dispose();
  });
}
