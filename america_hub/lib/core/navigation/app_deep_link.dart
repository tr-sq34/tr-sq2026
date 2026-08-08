/// Dış URL veya push payload'ından gelen hedefi UI'dan bağımsız olarak taşır.
sealed class AppDeepLink {
  const AppDeepLink();

  factory AppDeepLink.parse(Uri uri) {
    final segments = [if (uri.host.isNotEmpty) uri.host, ...uri.pathSegments];
    if (segments.length < 2) return const UnknownDeepLink();
    return switch (segments.first) {
      'post' => PostDeepLink(segments[1]),
      'event' => EventDeepLink(segments[1]),
      'listing' => ListingDeepLink(segments[1]),
      'request' => SpecialRequestDeepLink(segments[1]),
      _ => const UnknownDeepLink(),
    };
  }
}

class PostDeepLink extends AppDeepLink { const PostDeepLink(this.postId); final String postId; }
class EventDeepLink extends AppDeepLink { const EventDeepLink(this.eventId); final String eventId; }
class ListingDeepLink extends AppDeepLink { const ListingDeepLink(this.listingId); final String listingId; }
class SpecialRequestDeepLink extends AppDeepLink { const SpecialRequestDeepLink(this.requestId); final String requestId; }
class UnknownDeepLink extends AppDeepLink { const UnknownDeepLink(); }
