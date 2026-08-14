import '../../../core/pagination/paged_controller.dart';
import '../domain/entities/community_event.dart';
import '../domain/repositories/events_repository.dart';

/// Süzgeçteki üçüncü seçenek `august` idi ve tam olarak ağustos ayını
/// süzüyordu: yazıldığı ay. Aralıkta açan birine "Ağustos" diye bir seçenek
/// gösterip her seferinde boş liste veriyordu. Yerine bulunulan ay geçti.
enum EventDateFilter { all, next30Days, thisMonth }
enum EventSort { soonest, popular }

class EventsController extends PagedController<CommunityEvent> {
  EventsController({required EventsRepository repository, DateTime Function()? now})
      : _repository = repository,
        _now = now ?? DateTime.now,
        super(dataSource: repository, pageSize: 20);

  final EventsRepository _repository;

  /// Tarih süzgeçleri "şimdi"ye bakıyor; testin onu sabitleyebilmesi için
  /// dışarıdan verilebiliyor.
  final DateTime Function() _now;
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
      if (_dateFilter == EventDateFilter.thisMonth) {
        final now = _now();
        if (event.startsAt.year != now.year || event.startsAt.month != now.month) return false;
      }
      if (_dateFilter == EventDateFilter.next30Days) {
        final now = _now();
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

  /// Süzgeç listesi elde ne varsa ondan çıkıyor. Sabit bir liste, panelden yeni
  /// bir kategori yayınlandığı gün onu görünmez yapardı; ekranın kapak
  /// görselleri olan dokuz kategori ise zaten bu listenin içinden geliyor.
  List<String> get availableCategories =>
      (items.map((event) => event.category).toSet().toList()..sort());

  List<String> get availableCities =>
      (items.map((event) => event.city).where((city) => city.isNotEmpty).toSet().toList()..sort());

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

  /// Ana sayfadaki şerit ve Etkinlikler ekranı aynı denetleyiciyi paylaşıyor,
  /// ikisi de açılırken bunu çağırıyor. Elde liste varken baştan yüklemek hem
  /// gereksiz hem de açılan ekranın çizimi sırasında öbür ekranı uyandırdığı
  /// için hataya yol açıyordu. Liste boşsa -ilk açılış ya da yükleme hatası-
  /// yeniden deneniyor.
  Future<void> load() =>
      items.isEmpty ? loadInitial() : Future<void>.value();
}
