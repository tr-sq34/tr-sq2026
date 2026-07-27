import '../../../core/pagination/paged_controller.dart';
import '../domain/entities/community_event.dart';
import '../domain/repositories/events_repository.dart';

enum EventDateFilter { all, next30Days, august }
enum EventSort { soonest, popular }

class EventsController extends PagedController<CommunityEvent> {
  EventsController({required EventsRepository repository})
      : _repository = repository,
        super(dataSource: repository, pageSize: 20);

  final EventsRepository _repository;
  String _category = 'all';
  String _city = 'all';
  EventDateFilter _dateFilter = EventDateFilter.all;
  EventSort _sort = EventSort.soonest;

  String get category => _category;
  String get city => _city;
  EventDateFilter get dateFilter => _dateFilter;
  EventSort get sort => _sort;

  List<CommunityEvent> get visibleItems {
    final filtered = items.where((event) {
      if (_category != 'all' && event.category != _category) return false;
      if (_city != 'all' && event.city != _city) return false;
      if (_dateFilter == EventDateFilter.august && event.startsAt.month != 8) return false;
      if (_dateFilter == EventDateFilter.next30Days) {
        final now = DateTime.now();
        final until = now.add(const Duration(days: 30));
        if (event.startsAt.isBefore(now) || event.startsAt.isAfter(until)) return false;
      }
      return true;
    }).toList(growable: false);
    filtered.sort((a, b) => _sort == EventSort.soonest
        ? a.startsAt.compareTo(b.startsAt)
        : b.attendeeCount.compareTo(a.attendeeCount));
    return filtered;
  }

  void updateFilters({String? category, String? city, EventDateFilter? dateFilter, EventSort? sort}) {
    _category = category ?? _category;
    _city = city ?? _city;
    _dateFilter = dateFilter ?? _dateFilter;
    _sort = sort ?? _sort;
    notifyListeners();
  }

  void clearCategory() => updateFilters(category: 'all');

  Future<void> setRsvp(CommunityEvent event, EventRsvpStatus status) async {
    final before = items;
    final optimistic = event.copyWith(rsvpStatus: status);
    replaceItems([for (final item in before) if (item.id == event.id) optimistic else item]);
    try {
      final persisted = await _repository.updateRsvp(eventId: event.id, status: status);
      replaceItems([for (final item in items) if (item.id == event.id) persisted else item]);
    } catch (_) {
      replaceItems(before);
      rethrow;
    }
  }

  Future<void> load() => loadInitial();
}
