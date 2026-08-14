import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/pagination/paged_controller.dart';
import '../../../../core/widgets/app_badge.dart';
import '../../../../core/widgets/app_remote_image.dart';
import '../../../../core/widgets/app_screen_header.dart';
import '../../../../core/widgets/app_state_views.dart';
import '../../application/events_controller.dart';
import '../../domain/entities/community_event.dart';

const _months = ['Ocak', 'Subat', 'Mart', 'Nisan', 'Mayis', 'Haziran', 'Temmuz', 'Agustos', 'Eylul', 'Ekim', 'Kasim', 'Aralik'];
String _time(DateTime value) => '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String _eventDate(DateTime value) => '${value.day} ${_months[value.month - 1]} - ${_time(value)}';
String _dateFilterLabel(EventDateFilter value) => switch (value) { EventDateFilter.all => 'Tum tarihler', EventDateFilter.next30Days => 'Sonraki 30 gun', EventDateFilter.august => 'Agustos' };
String _sortLabel(EventSort value) => switch (value) { EventSort.soonest => 'En yakin tarih', EventSort.popular => 'En populer' };
String _categoryLabel(String value) => switch (value) { 'all' => 'Tum kategoriler', 'Culture' => 'Kultur', 'Cinema' => 'Sinema', 'Exhibition' => 'Sergiler', 'Music' => 'Konserler', 'Travel' => 'Geziler', 'Workshop' => 'Atolyeler', 'Food' => 'Lezzet', 'Festival' => 'Festival', 'Family' => 'Aile', 'Community' => 'Topluluk', _ => value };

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key, required this.controller});
  final EventsController controller;
  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.load();
  }

  Future<void> _pickDate() async {
    final value = await showModalBottomSheet<EventDateFilter>(context: context, builder: (_) => _FilterSheet<EventDateFilter>(title: 'Tarih sec', values: const [EventDateFilter.all, EventDateFilter.next30Days, EventDateFilter.august], label: _dateFilterLabel));
    if (value != null && mounted) widget.controller.updateFilters(dateFilter: value);
  }

  Future<void> _pickCategory() async {
    final value = await showModalBottomSheet<String>(context: context, builder: (_) => _FilterSheet<String>(title: 'Kategori sec', values: ['all', ...widget.controller.availableCategories], label: _categoryLabel));
    if (value != null && mounted) widget.controller.updateFilters(category: value);
  }

  Future<void> _pickSort() async {
    final value = await showModalBottomSheet<EventSort>(context: context, builder: (_) => _FilterSheet<EventSort>(title: 'Sirala', values: const [EventSort.soonest, EventSort.popular], label: _sortLabel));
    if (value != null && mounted) widget.controller.updateFilters(sort: value);
  }

  void _openCategory(String category, String label) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventsCategoryScreen(controller: widget.controller, category: category, title: label)));

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, child) {
          if (widget.controller.isInitialLoading) {
            return const Column(children: [AppScreenHeader(title: 'Etkinlikler', subtitle: 'Cevrendeki bulusmalari kesfet.'), Expanded(child: AppLoadingView(label: 'Etkinlikler yukleniyor...'))]);
          }
          if (widget.controller.state == PagedLoadState.failure) {
            return Column(children: [const AppScreenHeader(title: 'Etkinlikler', subtitle: 'Cevrendeki bulusmalari kesfet.'), Expanded(child: AppErrorState(message: 'Etkinlikler yuklenemedi.', onRetry: widget.controller.load))]);
          }
          final allEvents = widget.controller.items;
          final events = widget.controller.visibleItems;
          return ListView(
            key: const PageStorageKey('events-root-scroll'),
            padding: const EdgeInsets.only(bottom: 100),
            children: [
              if (allEvents.isEmpty) const Padding(padding: EdgeInsets.only(top: 50), child: AppEmptyState(icon: Icons.event_busy_outlined, title: 'Etkinlik bulunamadi', message: 'Yeni etkinlikler yakinda burada gorunecek.')) else if (events.isEmpty) Padding(padding: const EdgeInsets.only(top: 50), child: AppEmptyState(icon: Icons.filter_alt_off_outlined, title: 'Bu filtrede etkinlik yok', message: 'Baska bir tarih veya kategori secmeyi dene.', actionLabel: 'Filtreleri temizle', onAction: () => widget.controller.updateFilters(category: 'all', dateFilter: EventDateFilter.all))) else ...[
                _EventHero(events: events, controller: widget.controller),
                const SizedBox(height: 18),
                _DiscoveryPanel(onDateTap: _pickDate, onCategoryFilterTap: _pickCategory, onSortTap: _pickSort, onCategoryTap: _openCategory),
                const Padding(padding: EdgeInsets.fromLTRB(20, 22, 20, 12), child: Text('Yaklasan etkinlikler', style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w800))),
                SizedBox(
                  height: 177,
                  child: SingleChildScrollView(
                    key: const PageStorageKey('events-upcoming-rail'),
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(children: [
                      for (var index = 0; index < events.take(8).length; index++) ...[
                        _UpcomingEventTile(event: events[index], controller: widget.controller),
                        if (index != events.take(8).length - 1) const SizedBox(width: 12),
                      ],
                    ]),
                  ),
                ),
              ],
            ],
          );
        },
      );
}

class _EventHero extends StatefulWidget {
  const _EventHero({required this.events, required this.controller});
  final List<CommunityEvent> events;
  final EventsController controller;
  @override
  State<_EventHero> createState() => _EventHeroState();
}

class _EventHeroState extends State<_EventHero> {
  var _index = 0;
  @override
  Widget build(BuildContext context) {
    final event = widget.events[_index % widget.events.length];
    return SizedBox(
      height: 286,
      child: GestureDetector(
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v.abs() > 120) setState(() => _index = v < 0 ? (_index + 1) % widget.events.length : (_index - 1 + widget.events.length) % widget.events.length);
        },
        child: Stack(fit: StackFit.expand, children: [
          AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: Stack(key: ValueKey(event.id), fit: StackFit.expand, children: [
            AppRemoteImage(imageUrl: event.imageUrl, semanticLabel: event.title),
            const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x4A17052D), Color(0xE41C0B35)]))),
            Positioned(left: 20, right: 20, bottom: 42, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(event.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800, height: 1.08)),
              const SizedBox(height: 6), Text('${event.location} - ${_eventDate(event.startsAt.toLocal())}', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10), OutlinedButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventDetailScreen(event: event, controller: widget.controller))), style: OutlinedButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size(0, 30), padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4), tapTargetSize: MaterialTapTargetSize.shrinkWrap, side: const BorderSide(color: Colors.white70), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7))), child: const Text('Etkinligi gor', style: TextStyle(fontSize: 11))),
            ])),
          ])),
          Positioned(top: 14, left: 20, right: 20, child: Column(children: [
            Container(height: 42, padding: const EdgeInsets.symmetric(horizontal: 14), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .94), borderRadius: BorderRadius.circular(22)), child: const Row(children: [Icon(Icons.search_rounded, size: 20, color: AppColors.textMuted), SizedBox(width: 9), Expanded(child: Text('Etkinlik, grup veya mekan ara', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.textMuted)))])),
            const SizedBox(height: 10), const Row(children: [_HeroChip(label: 'New York, NY', icon: Icons.location_on_outlined), Spacer(), _HeroChip(label: 'Tum tarihler', icon: Icons.calendar_today_outlined)]),
          ])),
          Positioned(bottom: 16, left: 20, child: Row(children: [for (var i = 0; i < widget.events.length; i++) Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 6), decoration: BoxDecoration(shape: BoxShape.circle, color: i == _index % widget.events.length ? Colors.white : Colors.white38))])),
        ]),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label, required this.icon});
  final String label; final IconData icon;
  @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: Colors.black.withValues(alpha: .18), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withValues(alpha: .25))), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: Colors.white, size: 14), const SizedBox(width: 5), Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)), const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 16)]));
}

class _DiscoveryPanel extends StatelessWidget {
  const _DiscoveryPanel({required this.onDateTap, required this.onCategoryFilterTap, required this.onSortTap, required this.onCategoryTap});
  final VoidCallback onDateTap;
  final VoidCallback onCategoryFilterTap;
  final VoidCallback onSortTap;
  final void Function(String category, String label) onCategoryTap;

  @override
  Widget build(BuildContext context) {
    const categories = [
      ('Kultur', 'Culture', 'https://images.unsplash.com/photo-1561214115-f2f134cc4912?auto=format&fit=crop&w=500&q=80'),
      ('Sinema', 'Cinema', 'https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?auto=format&fit=crop&w=500&q=80'),
      ('Sergiler', 'Exhibition', 'https://images.unsplash.com/photo-1561214115-8d4e0b8a0995?auto=format&fit=crop&w=500&q=80'),
      ('Konserler', 'Music', 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&w=500&q=80'),
      ('Geziler', 'Travel', 'https://images.unsplash.com/photo-1494526585095-c41746248156?auto=format&fit=crop&w=500&q=80'),
      ('Atolyeler', 'Workshop', 'https://images.unsplash.com/photo-1544787219-7f47ccb76574?auto=format&fit=crop&w=500&q=80'),
      ('Lezzet', 'Food', 'https://images.unsplash.com/photo-1547592180-85f173990554?auto=format&fit=crop&w=500&q=80'),
      ('Festival', 'Festival', 'https://images.unsplash.com/photo-1492684223066-81342ee5ff30?auto=format&fit=crop&w=500&q=80'),
      ('Aile', 'Family', 'https://images.unsplash.com/photo-1503454537195-1dcabb73ffb9?auto=format&fit=crop&w=500&q=80'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _EventFilterButton(label: 'Tarih', icon: Icons.calendar_today_outlined, onPressed: onDateTap),
          SizedBox(width: 8),
          _EventFilterButton(label: 'Kategori', icon: Icons.grid_view_rounded, onPressed: onCategoryFilterTap),
          SizedBox(width: 8),
          _EventFilterButton(label: 'Sirala', icon: Icons.swap_vert_rounded, onPressed: onSortTap),
        ]),
        const SizedBox(height: 20),
        const Text('Etkinlik kategorileri', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (_, constraints) {
          final tileWidth = (constraints.maxWidth - 24) / 3;
          return Wrap(
            spacing: 12,
            runSpacing: 14,
            children: [
              for (final item in categories)
                SizedBox(
                  width: tileWidth,
                  child: InkWell(onTap: () => onCategoryTap(item.$2, item.$1), borderRadius: BorderRadius.circular(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ClipRRect(borderRadius: BorderRadius.circular(14), child: SizedBox(height: 92, width: double.infinity, child: AppRemoteImage(imageUrl: item.$3, semanticLabel: item.$1))),
                    const SizedBox(height: 6), Text(item.$1, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  ])),
                ),
            ],
          );
        }),
      ]),
    );
  }
}

class _EventFilterButton extends StatelessWidget {
  const _EventFilterButton({required this.label, required this.icon, required this.onPressed});
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Expanded(
        child: SizedBox(
          height: 36,
          child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 15),
          label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            backgroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFF9D9AA4)),
            padding: const EdgeInsets.symmetric(horizontal: 5),
            shape: const StadiumBorder(),
          ),
        ),
        ),
      );
}

class _UpcomingEventTile extends StatelessWidget {
  const _UpcomingEventTile({required this.event, required this.controller});
  final CommunityEvent event;
  final EventsController controller;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 130,
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventDetailScreen(event: event, controller: controller))),
          borderRadius: BorderRadius.circular(17),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17), boxShadow: const [BoxShadow(color: Color(0x120E0B18), blurRadius: 14, offset: Offset(0, 5))]),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(height: 96, width: double.infinity, child: AppRemoteImage(imageUrl: event.imageUrl, semanticLabel: event.title)),
              Padding(padding: const EdgeInsets.fromLTRB(10, 9, 10, 7), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(event.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                const SizedBox(height: 4),
                Text('${event.location} - ${event.startsAt.day} ${_months[event.startsAt.month - 1]}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
              ])),
            ]),
          ),
        ),
      );
}

class _FilterSheet<T> extends StatelessWidget {
  const _FilterSheet({required this.title, required this.values, required this.label});
  final String title;
  final List<T> values;
  final String Function(T value) label;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: AppColors.surfaceBorder, borderRadius: BorderRadius.circular(4)))),
            const SizedBox(height: 18),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final value in values) ListTile(contentPadding: EdgeInsets.zero, title: Text(label(value), style: const TextStyle(fontWeight: FontWeight.w600)), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => Navigator.of(context).pop(value)),
          ]),
        ),
      );
}

class EventsCategoryScreen extends StatelessWidget {
  const EventsCategoryScreen({super.key, required this.controller, required this.category, required this.title});
  final EventsController controller;
  final String category;
  final String title;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final items = [for (final event in controller.items) if (event.category == category) event]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(title: Text(title), backgroundColor: AppColors.background, surfaceTintColor: Colors.transparent),
            body: items.isEmpty
                ? const AppEmptyState(icon: Icons.event_busy_outlined, title: 'Bu kategoride etkinlik yok', message: 'Yeni etkinlikler eklendiginde burada gorunecek.')
                : ListView.separated(padding: const EdgeInsets.fromLTRB(20, 10, 20, 30), itemCount: items.length, separatorBuilder: (_, index) => const SizedBox(height: 14), itemBuilder: (_, index) => _EventCard(event: items[index], controller: controller)),
          );
        },
      );
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.controller});
  final CommunityEvent event; final EventsController controller;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventDetailScreen(event: event, controller: controller))),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Color(0x120E0B18), blurRadius: 14, offset: Offset(0, 5))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(height: 150, width: double.infinity, child: AppRemoteImage(imageUrl: event.imageUrl, semanticLabel: event.title)),
            Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(event.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 5),
              Text('${event.location} - ${event.city}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 10),
              Row(children: [AppBadge(label: event.priceLabel, color: AppColors.accentAmber), const Spacer(), Text('${event.attendeeCount} katiliyor', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12))]),
            ])),
          ]),
        ),
      );
}

class EventDetailScreen extends StatelessWidget {
  const EventDetailScreen({super.key, required this.event, required this.controller});
  final CommunityEvent event;
  final EventsController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final matches = [for (final item in controller.items) if (item.id == event.id) item];
          final current = matches.isEmpty ? event : matches.first;
          return Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 10, 14, 8),
                  child: Row(children: [
                    IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19)),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(current.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(_eventDate(current.startsAt.toLocal()), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      Text('${current.location}, ${current.city}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF2477A7), fontWeight: FontWeight.w700)),
                    ])),
                    // Basliktaki bilgi dugmesi buradaydi; basilinca hicbir sey acmiyordu.
                  ]),
                ),
                const Divider(height: 1, color: AppColors.surfaceBorder),
                Expanded(
                  child: ListView(padding: EdgeInsets.zero, children: [
                    SizedBox(height: 230, width: double.infinity, child: AppRemoteImage(imageUrl: current.imageUrl, semanticLabel: current.title)),
                    _DetailSummary(event: current),
                    const Divider(height: 1, color: AppColors.surfaceBorder),
                    _PriceAndAttendance(event: current),
                    const Divider(height: 1, color: AppColors.surfaceBorder),
                    const Padding(padding: EdgeInsets.fromLTRB(18, 16, 18, 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _EventBenefit(icon: Icons.confirmation_number_outlined, label: 'Mobil etkinlik bileti'),
                      SizedBox(height: 11),
                      _EventBenefit(icon: Icons.people_outline_rounded, label: 'Toplulukla birlikte katil'),
                      SizedBox(height: 11),
                      _EventBenefit(icon: Icons.bookmark_border_rounded, label: 'Planin degisirse kaydedebilirsin'),
                    ])),
                    const Divider(height: 1, color: AppColors.surfaceBorder),
                    Padding(padding: const EdgeInsets.fromLTRB(18, 18, 18, 120), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Row(children: [Icon(Icons.verified_user_outlined, color: AppColors.primary), SizedBox(width: 8), Text('Guvenli katilim', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))]),
                      const SizedBox(height: 10),
                      Text(current.description, style: const TextStyle(color: AppColors.textSecondary, height: 1.45)),
                      const SizedBox(height: 12),
                      const Text('Katilim bilgilerin etkinlik sahibiyle guvenli bicimde paylasilir. Etkinlik detaylari degisirse sana bildirim gondeririz.', style: TextStyle(color: AppColors.textSecondary, height: 1.45)),
                    ])),
                  ]),
                ),
                _DetailBottomBar(event: current, controller: controller),
              ]),
            ),
          );
        },
      );
}

class _DetailSummary extends StatelessWidget {
  const _DetailSummary({required this.event});
  final CommunityEvent event;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(event.category, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Etkinlik bilgileri', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            Text('${event.attendeeCount} kisi katilmayi planliyor', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: const Color(0xFFE7F5E9), borderRadius: BorderRadius.circular(6)), child: const Text('Topluluk', style: TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w800, fontSize: 12))),
        ]),
      );
}

class _PriceAndAttendance extends StatelessWidget {
  const _PriceAndAttendance({required this.event});
  final CommunityEvent event;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Katilim ucreti', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(event.priceLabel, style: const TextStyle(color: Color(0xFF1D7A45), fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            const Text('Tum ucretler dahil', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const Text('Katilim', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 4),
            Text('${event.attendeeCount} kisi', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ]),
        ]),
      );
}

class _EventBenefit extends StatelessWidget {
  const _EventBenefit({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(children: [Icon(icon, size: 19, color: AppColors.textPrimary), const SizedBox(width: 10), Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14))]);
}

class _DetailBottomBar extends StatelessWidget {
  const _DetailBottomBar({required this.event, required this.controller});
  final CommunityEvent event;
  final EventsController controller;
  @override
  Widget build(BuildContext context) => SafeArea(top: false, child: Container(padding: const EdgeInsets.fromLTRB(18, 12, 18, 14), decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.surfaceBorder))), child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [const Text('Katilim', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)), Text(event.priceLabel, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))])),
        const SizedBox(width: 12),
        FilledButton(onPressed: () => controller.setRsvp(event, event.isGoing ? EventRsvpStatus.none : EventRsvpStatus.going), style: FilledButton.styleFrom(minimumSize: const Size(148, 46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text(event.isGoing ? 'Katilmiyorum' : 'Katilacagim')),
      ])));
}
