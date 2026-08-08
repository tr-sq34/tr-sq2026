import 'dart:convert';

import '../../../../core/cache/cache_codec.dart';
import '../../../../core/pagination/cursor_page.dart';
import '../../domain/entities/community_post.dart';

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
            }).toList(),
      });
}
