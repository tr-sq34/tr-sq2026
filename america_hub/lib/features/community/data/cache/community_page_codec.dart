import 'dart:convert';

import '../../../../core/cache/cache_codec.dart';
import '../../../../core/pagination/cursor_page.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/entities/feed_extensions.dart';

class CommunityPageCodec implements CacheCodec<CursorPage<CommunityPost>> {
  @override
  CursorPage<CommunityPost> decode(String value) {
    final json = jsonDecode(value) as Map<String, dynamic>;
    final List<CommunityPost> items = (json['items'] as List<dynamic>).cast<Map<String, dynamic>>().map((item) => CommunityPost(
          id: item['id'] as String,
          authorName: item['authorName'] as String,
          location: item['location'] as String,
          timeLabel: item['timeLabel'] as String,
          message: item['message'] as String,
          likes: item['likes'] as int,
          comments: item['comments'] as int,
          ownerId: item['ownerId'] as String? ?? 'local-user',
          visibility: PostVisibility.values.byName(item['visibility'] as String? ?? PostVisibility.friendsOnly.name),
          commentsPolicy: CommentsPolicy.values.byName(item['commentsPolicy'] as String? ?? CommentsPolicy.friendsOnly.name),
          status: PostStatus.values.byName(item['status'] as String? ?? PostStatus.published.name),
          media: (item['media'] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>()
              .map((media) => PostMedia(
                    id: media['id'] as String,
                    type: PostMediaType.values.byName(media['type'] as String),
                    url: media['url'] as String,
                    thumbnailUrl: media['thumbnailUrl'] as String?,
                    durationSeconds: media['durationSeconds'] as int?,
                  ))
              .toList(growable: false),
          taggedUsers: (item['taggedUsers'] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>()
              .map((user) => TaggedUser(id: user['id'] as String, displayName: user['displayName'] as String))
              .toList(growable: false),
          postLocation: item['postLocation'] == null
              ? null
              : PostLocation(
                  placeId: (item['postLocation'] as Map<String, dynamic>)['placeId'] as String,
                  displayName: (item['postLocation'] as Map<String, dynamic>)['displayName'] as String,
                  city: (item['postLocation'] as Map<String, dynamic>)['city'] as String?,
                ),
          isLiked: item['isLiked'] as bool? ?? false,
          isAuthor: item['isAuthor'] as bool? ?? false,
          deletedAt: item['deletedAt'] == null ? null : DateTime.tryParse(item['deletedAt'] as String),
          purpose: CommunityPostPurpose.values.byName(item['purpose'] as String? ?? CommunityPostPurpose.standard.name),
          travelerMatch: item['travelerMatch'] == null
              ? null
              : TravelerMatchDetails(
                  from: (item['travelerMatch'] as Map<String, dynamic>)['from'] as String,
                  to: (item['travelerMatch'] as Map<String, dynamic>)['to'] as String,
                  travelAt: DateTime.tryParse((item['travelerMatch'] as Map<String, dynamic>)['travelAt'] as String? ?? '') ?? DateTime.now(),
                  packageDetails: (item['travelerMatch'] as Map<String, dynamic>)['packageDetails'] as String? ?? '',
                  note: (item['travelerMatch'] as Map<String, dynamic>)['note'] as String?,
                ),
          badge: item['badge'] == null
              ? null
              : CommunityBadge(
                  label: (item['badge'] as Map<String, dynamic>)['label'] as String,
                  icon: (item['badge'] as Map<String, dynamic>)['icon'] as String? ?? '✦',
                ),
          poll: _pollFrom(item['poll']),
          newsReference: _newsFrom(item['newsReference']),
          // Damga da saklanıyor: çevrimdışı açılan akışta "3dk" yazan bir kart,
          // bir gün sonra hâlâ "3dk" demesin diye etiket değil an tutuluyor.
          createdAt: item['createdAt'] == null
              ? null
              : DateTime.tryParse(item['createdAt'] as String),
        )).toList();
    return CursorPage(items: items, nextCursor: json['nextCursor'] as String?);
  }

  @override
  String encode(CursorPage<CommunityPost> value) => jsonEncode({
        'nextCursor': value.nextCursor,
        'items': value.items.map((item) => {
              'id': item.id,
              'authorName': item.authorName,
              'location': item.location,
              'timeLabel': item.timeLabel,
              'message': item.message,
              'likes': item.likes,
              'comments': item.comments,
              'ownerId': item.ownerId,
              'visibility': item.visibility.name,
              'commentsPolicy': item.commentsPolicy.name,
              'status': item.status.name,
              'media': item.media.map((media) => {
                    'id': media.id,
                    'type': media.type.name,
                    'url': media.url,
                    'thumbnailUrl': media.thumbnailUrl,
                    'durationSeconds': media.durationSeconds,
                  }).toList(),
              'taggedUsers': item.taggedUsers.map((user) => {'id': user.id, 'displayName': user.displayName}).toList(),
              'postLocation': item.postLocation == null
                  ? null
                  : {
                      'placeId': item.postLocation!.placeId,
                      'displayName': item.postLocation!.displayName,
                      'city': item.postLocation!.city,
                    },
              'isLiked': item.isLiked,
              'isAuthor': item.isAuthor,
              'deletedAt': item.deletedAt?.toIso8601String(),
              'purpose': item.purpose.name,
              'travelerMatch': item.travelerMatch == null
                  ? null
                  : {
                      'from': item.travelerMatch!.from,
                      'to': item.travelerMatch!.to,
                      'travelAt': item.travelerMatch!.travelAt.toIso8601String(),
                      'packageDetails': item.travelerMatch!.packageDetails,
                      'note': item.travelerMatch!.note,
                    },
              'badge': item.badge == null
                  ? null
                  : {'label': item.badge!.label, 'icon': item.badge!.icon},
              'poll': item.poll == null
                  ? null
                  : {
                      'id': item.poll!.id,
                      'question': item.poll!.question,
                      'selectionMode': item.poll!.selectionMode.name,
                      'endsAt': item.poll!.endsAt?.toIso8601String(),
                      'options': item.poll!.options.map((option) => {'id': option.id, 'label': option.label, 'votes': option.votes}).toList(),
                      'selectedOptionIds': item.poll!.selectedOptionIds.toList(),
                    },
              'createdAt': item.createdAt?.toIso8601String(),
              'newsReference': item.newsReference == null
                  ? null
                  : {
                      'articleId': item.newsReference!.articleId,
                      'title': item.newsReference!.title,
                      'category': item.newsReference!.category,
                    },
            }).toList(),
      });
}

/// Çevrimdışı kopyada haber bağlantısı da duruyor. Aksi halde uçakta açılan
/// akışta haber kartı sıradan bir paylaşıma dönüşürdü: imzası "Haber Bülteni"
/// kalır ama dokunulduğunda hiçbir yere gitmezdi.
NewsPostReference? _newsFrom(Object? raw) {
  if (raw is! Map<String, dynamic>) return null;
  final id = raw['articleId'] as String?;
  if (id == null || id.isEmpty) return null;
  return NewsPostReference(
    articleId: id,
    title: raw['title'] as String? ?? '',
    category: raw['category'] as String?,
  );
}

/// Çevrimdışı kopyada anket de duruyor. Aksi halde uçakta açılan akışta anketli
/// bir paylaşım yalnızca sorusuyla görünüyordu: seçenekler kaybolduğu için
/// altında dokunulacak bir şey kalmıyordu.
CommunityPoll? _pollFrom(Object? raw) {
  if (raw is! Map<String, dynamic>) return null;
  final endsAt = raw['endsAt'] as String?;
  return CommunityPoll(
    id: raw['id'] as String,
    question: raw['question'] as String? ?? '',
    selectionMode: PollSelectionMode.values.byName(raw['selectionMode'] as String? ?? PollSelectionMode.single.name),
    endsAt: endsAt == null ? null : DateTime.tryParse(endsAt),
    options: (raw['options'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map((option) => PollOption(
              id: option['id'] as String,
              label: option['label'] as String? ?? '',
              votes: (option['votes'] as num?)?.toInt() ?? 0,
            ))
        .toList(growable: false),
    selectedOptionIds: (raw['selectedOptionIds'] as List<dynamic>? ?? const []).cast<String>().toSet(),
  );
}
