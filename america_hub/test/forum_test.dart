import 'package:america_hub/core/state/async_state.dart';
import 'package:america_hub/features/auth/domain/entities/app_user.dart';
import 'package:america_hub/features/forum/application/forum_controller.dart';
import 'package:america_hub/features/forum/data/repositories/mock_forum_repository.dart';
import 'package:america_hub/features/forum/domain/entities/forum.dart';
import 'package:flutter_test/flutter_test.dart';

/// Forumun kuralları burada sınanıyor: kimin adına yazıldığı, kapalı konuya
/// yanıt yazılamadığı, sabitlenen konunun sıralamanın üstünde durduğu.
void main() {
  const viewer = AppUser(
    id: 'local-zeynep',
    email: 'zeynep@example.com',
    displayName: 'Zeynep Kaya',
  );

  late MockForumRepository repository;
  late ForumController controller;

  setUp(() {
    repository = MockForumRepository(viewer: () => viewer);
    controller = ForumController(repository: repository);
  });

  test('a new topic carries the signed-in member\'s name', () async {
    final topic = await repository.createTopic(
      const CreateTopicDraft(
        categoryId: 'cat-vize',
        title: 'Yeşil kart başvurusunda avukat şart mı?',
        body: 'Kendi başvurusunu yapan var mı? Nerelerde takıldınız?',
      ),
    );

    expect(topic.authorName, 'Zeynep Kaya');
    expect(topic.authorId, 'local-zeynep');
    expect(topic.categoryTitle, 'Vize & Göçmenlik');
  });

  test('a topic that is too thin never leaves the composer', () async {
    const draft = CreateTopicDraft(
      categoryId: 'cat-vize',
      title: 'Kısa',
      body: 'Yardım',
    );

    expect(draft.validationError, isNotNull);
    expect(() => repository.createTopic(draft), throwsArgumentError);
  });

  test('replying moves the topic to the top of the list', () async {
    // Sabit konu her koşulda birinci; sıralama onun altında başlıyor.
    final before = await repository.fetchTopics();
    expect(before.items.first.isPinned, isTrue);

    await repository.reply(topicId: 'topic-ehliyet', body: 'Bende de öyle oldu.');
    final after = await repository.fetchTopics();

    expect(after.items.first.isPinned, isTrue);
    expect(after.items[1].id, 'topic-ehliyet');
    expect(after.items[1].lastReplyAuthorName, 'Zeynep Kaya');
  });

  test('a locked topic takes no new replies', () async {
    expect(
      () => repository.reply(topicId: 'topic-kurallar', body: 'Anlaşıldı.'),
      throwsStateError,
    );
  });

  test('category counters count what is in the list', () async {
    final before = await repository.fetchCategories();
    final vize = before.firstWhere((category) => category.id == 'cat-vize');
    expect(vize.topicCount, 1);

    await repository.createTopic(
      const CreateTopicDraft(
        categoryId: 'cat-vize',
        title: 'B1/B2 vizesinde ikinci giriş sorunlu mu?',
        body: 'İkinci kez giriş yapanlarda sorun çıkıyor mu, tecrübesi olan?',
      ),
    );

    final after = await repository.fetchCategories();
    expect(
      after.firstWhere((category) => category.id == 'cat-vize').topicCount,
      2,
    );
  });

  test('opening a topic counts the read once per open', () async {
    final first = await repository.fetchTopic('topic-h1b');
    final second = await repository.fetchTopic('topic-h1b');

    expect(second.viewCount, first.viewCount + 1);
  });

  // Aynı konu hem listede hem trend şeridinde durabiliyor; beğeni ikisinde de
  // aynı sayıyı göstermeli, yoksa üye geri döndüğünde eski sayacı görür.
  test('a like on a topic shows up in both lists', () async {
    await controller.load();
    await controller.loadTrending(limit: 5);

    await controller.toggleTopicLike('topic-e2');

    final inList = _pick(controller.topics, 'topic-e2');
    final inTrending = _pick(controller.trending, 'topic-e2');

    expect(inList.isLiked, isTrue);
    expect(inTrending.likeCount, inList.likeCount);
  });

  test('the reply the member writes lands under the open topic', () async {
    await controller.openTopicById('topic-kiralik');
    await controller.reply('topic-kiralik', 'Bizde kefil istediler.');

    expect(controller.openTopic!.replyCount, 13);
    final replies = switch (controller.replies) {
      AsyncData<List<ForumReply>>(:final value) => value,
      _ => const <ForumReply>[],
    };
    expect(replies.last.authorName, 'Zeynep Kaya');
  });
}

ForumTopic _pick(AsyncState<List<ForumTopic>> state, String id) =>
    switch (state) {
      AsyncData<List<ForumTopic>>(:final value) => value.firstWhere(
        (topic) => topic.id == id,
      ),
      _ => throw StateError('Liste yüklenmedi.'),
    };
