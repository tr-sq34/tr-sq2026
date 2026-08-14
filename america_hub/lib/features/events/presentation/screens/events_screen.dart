import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/pagination/paged_controller.dart';
import '../../../../core/widgets/app_badge.dart';
import '../../../../core/widgets/app_remote_image.dart';
import '../../../../core/widgets/app_state_views.dart';
import '../../application/events_controller.dart';
import '../../domain/entities/community_event.dart';

const _months = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
String _time(DateTime value) => '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String _eventDate(DateTime value) => '${value.day} ${_months[value.month - 1]} - ${_time(value)}';
String _dateFilterLabel(EventDateFilter value) => switch (value) { EventDateFilter.all => 'Tüm tarihler', EventDateFilter.next30Days => 'Sonraki 30 gün', EventDateFilter.thisMonth => 'Bu ay' };
String _cityLabel(String value) => value == 'all' ? 'Tüm şehirler' : value;
String _sortLabel(EventSort value) => switch (value) { EventSort.soonest => 'En yakın tarih', EventSort.popular => 'En popüler' };
String _categoryLabel(String value) => switch (value) { 'all' => 'Tüm kategoriler', 'Culture' => 'Kültür', 'Cinema' => 'Sinema', 'Exhibition' => 'Sergiler', 'Music' => 'Konserler', 'Travel' => 'Geziler', 'Workshop' => 'Atölyeler', 'Food' => 'Lezzet', 'Festival' => 'Festival', 'Family' => 'Aile', 'Community' => 'Topluluk', _ => value };

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
    final value = await showModalBottomSheet<EventDateFilter>(context: context, builder: (_) => _FilterSheet<EventDateFilter>(title: 'Tarih seç', values: const [EventDateFilter.all, EventDateFilter.next30Days, EventDateFilter.thisMonth], label: _dateFilterLabel));
    if (value != null && mounted) widget.controller.updateFilters(dateFilter: value);
  }

  /// Sehir suzgeci denetleyicide bastan beri vardi ama onu ayarlayan hicbir
  /// yer yoktu. Liste elde ne varsa ondan cikiyor; sabit bir sehir listesi,
  /// panelden baska bir sehre etkinlik yayimlandigi gun onu gizlerdi.
  Future<void> _pickCity() async {
    final value = await showModalBottomSheet<String>(context: context, builder: (_) => _FilterSheet<String>(title: 'Şehir seç', values: ['all', ...widget.controller.availableCities], label: _cityLabel));
    if (value != null && mounted) widget.controller.updateFilters(city: value);
  }

  Future<void> _pickCategory() async {
    final value = await showModalBottomSheet<String>(context: context, builder: (_) => _FilterSheet<String>(title: 'Kategori seç', values: ['all', ...widget.controller.availableCategories], label: _categoryLabel));
    if (value != null && mounted) widget.controller.updateFilters(category: value);
  }

  Future<void> _pickSort() async {
    final value = await showModalBottomSheet<EventSort>(context: context, builder: (_) => _FilterSheet<EventSort>(title: 'Sırala', values: const [EventSort.soonest, EventSort.popular], label: _sortLabel));
    if (value != null && mounted) widget.controller.updateFilters(sort: value);
  }

  void _openCategory(String category, String label) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventsCategoryScreen(controller: widget.controller, category: category, title: label)));

  // Ekranin kendi Scaffold'u var: menuden acilan bir sayfa, geri dugmesi
  // olmadan acilamaz. Onceden yalnizca bir sekmenin govdesi olacak sekilde
  // yazilmisti, ama onu sekmeye koyan bir yer hic olmadi.
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          title: const Text('Etkinlikler', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        ),
        body: _buildBody(),
      );

  Widget _buildBody() => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, child) {
          if (widget.controller.isInitialLoading) {
            return const AppLoadingView(label: 'Etkinlikler yükleniyor...');
          }
          if (widget.controller.state == PagedLoadState.failure) {
            return AppErrorState(message: 'Etkinlikler yüklenemedi.', onRetry: widget.controller.load);
          }
          final allEvents = widget.controller.items;
          final events = widget.controller.visibleItems;
          return ListView(
            key: const PageStorageKey('events-root-scroll'),
            padding: const EdgeInsets.only(bottom: 100),
            children: [
              if (allEvents.isEmpty) const Padding(padding: EdgeInsets.only(top: 50), child: AppEmptyState(icon: Icons.event_busy_outlined, title: 'Etkinlik bulunamadı', message: 'Yeni etkinlikler yakında burada görünecek.')) else if (events.isEmpty) Padding(padding: const EdgeInsets.only(top: 50), child: AppEmptyState(icon: Icons.filter_alt_off_outlined, title: 'Bu filtrede etkinlik yok', message: 'Başka bir tarih veya kategori seçmeyi dene.', actionLabel: 'Filtreleri temizle', onAction: () => widget.controller.updateFilters(category: 'all', city: 'all', dateFilter: EventDateFilter.all))) else ...[
                _EventHero(events: events, controller: widget.controller, onCityTap: _pickCity, onDateTap: _pickDate),
                const SizedBox(height: 18),
                _DiscoveryPanel(categories: widget.controller.availableCategories, onDateTap: _pickDate, onCategoryFilterTap: _pickCategory, onSortTap: _pickSort, onCategoryTap: _openCategory),
                const Padding(padding: EdgeInsets.fromLTRB(20, 22, 20, 12), child: Text('Yaklaşan etkinlikler', style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w800))),
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
  const _EventHero({required this.events, required this.controller, required this.onCityTap, required this.onDateTap});
  final List<CommunityEvent> events;
  final EventsController controller;
  final VoidCallback onCityTap;
  final VoidCallback onDateTap;
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
              const SizedBox(height: 10), OutlinedButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventDetailScreen(event: event, controller: widget.controller))), style: OutlinedButton.styleFrom(foregroundColor: Colors.white, minimumSize: const Size(0, 30), padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4), tapTargetSize: MaterialTapTargetSize.shrinkWrap, side: const BorderSide(color: Colors.white70), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7))), child: const Text('Etkinliği gör', style: TextStyle(fontSize: 11))),
            ])),
          ])),
          // Burada bir arama kutusu duruyordu: "Etkinlik, grup veya mekan ara"
          // yazan, arama alani gibi gorunen ama yazi bile girilemeyen bir
          // kutuydu. Sunucuda etkinlik aramasi diye bir sey yok; gercekten
          // yazildiginda kutu da geri gelir.
          //
          // Altindaki iki cip de -"New York, NY" ile "Tum tarihler"- oku olan
          // birer suzgec gibi duruyor ama hicbir seye baglanmiyordu; sehir
          // koda yazilmisti, tarih ise altindaki gercek suzgecin secimini
          // yansitmiyordu. Ikisi de artik gercek suzgeci aciyor ve o an ne
          // secili ise onu yaziyor.
          Positioned(top: 14, left: 20, right: 20, child: Row(children: [
            Flexible(child: _HeroChip(label: _cityLabel(widget.controller.city), icon: Icons.location_on_outlined, onTap: widget.onCityTap)),
            const Spacer(),
            Flexible(child: _HeroChip(label: _dateFilterLabel(widget.controller.dateFilter), icon: Icons.calendar_today_outlined, onTap: widget.onDateTap)),
          ])),
          Positioned(bottom: 16, left: 20, child: Row(children: [for (var i = 0; i < widget.events.length; i++) Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 6), decoration: BoxDecoration(shape: BoxShape.circle, color: i == _index % widget.events.length ? Colors.white : Colors.white38))])),
        ]),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label, required this.icon, required this.onTap});
  final String label; final IconData icon; final VoidCallback onTap;
  @override Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: Colors.black.withValues(alpha: .18), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withValues(alpha: .25))), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: Colors.white, size: 14), const SizedBox(width: 5), Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))), const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 16)])),
      );
}

/// Kategori kutusunun rengi ve simgesi. Onceden dokuz kutunun her biri
/// Unsplash'ten bir fotograf cekiyordu: canli bir uygulamanin, kendi
/// sunucusunda hic bulunmayan dokuz gorsele bagli olmasi demekti bu.
/// Baglantilar bir gun kirildiginda ekranin ustunde dokuz bos kare kalirdi.
({IconData icon, Color color}) _categoryArt(String category) => switch (category) {
      'Culture' => (icon: Icons.museum_outlined, color: Color(0xFF8E6BD0)),
      'Cinema' => (icon: Icons.local_movies_outlined, color: Color(0xFF4A5BC4)),
      'Exhibition' => (icon: Icons.palette_outlined, color: Color(0xFFC4577E)),
      'Music' => (icon: Icons.music_note_outlined, color: Color(0xFFD07A3C)),
      'Travel' => (icon: Icons.landscape_outlined, color: Color(0xFF2F9E7F)),
      'Workshop' => (icon: Icons.handyman_outlined, color: Color(0xFF9A7B3F)),
      'Food' => (icon: Icons.restaurant_outlined, color: Color(0xFFCB5B4C)),
      'Festival' => (icon: Icons.celebration_outlined, color: Color(0xFFB8479B)),
      'Family' => (icon: Icons.family_restroom_outlined, color: Color(0xFF3E86B5)),
      'Community' => (icon: Icons.groups_outlined, color: Color(0xFF5C7CBA)),
      _ => (icon: Icons.event_outlined, color: AppColors.primary),
    };

class _DiscoveryPanel extends StatelessWidget {
  const _DiscoveryPanel({required this.categories, required this.onDateTap, required this.onCategoryFilterTap, required this.onSortTap, required this.onCategoryTap});

  /// Kutular elde ne varsa ondan cikiyor. Onceden dokuz kategori koda
  /// yazilmisti; bir yenisi panelden yayimlandiginda gorunmuyor, karsiligi
  /// olmayan sekiz tanesi ise dokununca hep bos ekran aciyordu.
  final List<String> categories;
  final VoidCallback onDateTap;
  final VoidCallback onCategoryFilterTap;
  final VoidCallback onSortTap;
  final void Function(String category, String label) onCategoryTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _EventFilterButton(label: 'Tarih', icon: Icons.calendar_today_outlined, onPressed: onDateTap),
          SizedBox(width: 8),
          _EventFilterButton(label: 'Kategori', icon: Icons.grid_view_rounded, onPressed: onCategoryFilterTap),
          SizedBox(width: 8),
          _EventFilterButton(label: 'Sırala', icon: Icons.swap_vert_rounded, onPressed: onSortTap),
        ]),
        if (categories.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('Etkinlik kategorileri', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (_, constraints) {
            final tileWidth = (constraints.maxWidth - 24) / 3;
            return Wrap(
              spacing: 12,
              runSpacing: 14,
              children: [
                for (final category in categories)
                  SizedBox(
                    width: tileWidth,
                    child: _CategoryTile(category: category, label: _categoryLabel(category), onTap: () => onCategoryTap(category, _categoryLabel(category))),
                  ),
              ],
            );
          }),
        ],
      ]),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.label, required this.onTap});
  final String category;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final art = _categoryArt(category);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          height: 92,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [art.color, Color.lerp(art.color, Colors.black, .28)!]),
          ),
          child: Icon(art.icon, color: Colors.white, size: 30),
        ),
        const SizedBox(height: 6),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
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
                ? const AppEmptyState(icon: Icons.event_busy_outlined, title: 'Bu kategoride etkinlik yok', message: 'Yeni etkinlikler eklendiğinde burada görünecek.')
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
              Row(children: [AppBadge(label: event.priceLabel, color: AppColors.accentAmber), const Spacer(), Text('${event.attendeeCount} katılıyor', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12))]),
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
                    if (current.isCancelled) _CancelledNotice(reason: current.cancellationReason),
                    _DetailSummary(event: current),
                    const Divider(height: 1, color: AppColors.surfaceBorder),
                    _PriceAndAttendance(event: current),
                    const Divider(height: 1, color: AppColors.surfaceBorder),
                    // Burada uc satirlik bir "avantajlar" bloğu vardi: "Mobil
                    // etkinlik bileti", "Toplulukla birlikte katil", "Planin
                    // degisirse kaydedebilirsin". Ucu de her etkinlikte aynen
                    // yaziyordu ve ucunun de karsiligi yoktu: uygulamada bilet
                    // diye bir sey hic olmadi, kaydetme de yok. Bilet gercekten
                    // varsa sunucu onu externalUrl olarak gonderiyor; asagidaki
                    // baglanti tam olarak o.
                    if (current.externalUrl != null) _ExternalLinkRow(url: current.externalUrl!),
                    Padding(padding: const EdgeInsets.fromLTRB(18, 18, 18, 120), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Etkinlik hakkında', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 10),
                      Text(current.description.isEmpty ? 'Bu etkinlik için ayrıntılı bir açıklama yazılmamış.' : current.description, style: const TextStyle(color: AppColors.textSecondary, height: 1.45)),
                      const SizedBox(height: 12),
                      // Onceki metin ayrica "etkinlik detaylari degisirse sana
                      // bildirim gondeririz" diyordu. Etkinlikler icin tek bir
                      // bildirim turu yazilmadi; soz veremeyecegimiz seyi
                      // soylemektense ne oldugunu soyluyoruz.
                      const Text('Katılacağını söylemek etkinliği düzenleyene yalnızca kaç kişi geldiğini gösterir; adın listelenmez.', style: TextStyle(color: AppColors.textSecondary, height: 1.45)),
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
            Text('${event.attendeeCount} kişi katılmayı planlıyor', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ])),
          // Burada her etkinlikte ayni yesil "Topluluk" rozeti duruyordu.
          // Kategori zaten solda yaziyor; rozet hicbir sey soylemiyordu.
          if (event.interestedCount > 0) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: const Color(0xFFE7F5E9), borderRadius: BorderRadius.circular(6)), child: Text('${event.interestedCount} ilgileniyor', style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w800, fontSize: 12))),
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
            const Text('Katılım ücreti', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(event.priceLabel, style: const TextStyle(color: Color(0xFF1D7A45), fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            // Onceden burada "Tum ucretler dahil" yaziyordu. Uygulamada odeme
            // diye bir sey yok; ucret bilgisi etkinligi yayimlayanin yazdigi
            // duz metinden ibaret ve odeme kapida yapiliyor.
            const Text('Ücret etkinlik yerinde ödenir', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const Text('Katılım', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 4),
            Text('${event.attendeeCount} kişi', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            // Kontenjan sunucuda ilk gunden beri var ve katilim aninda orada
            // uygulaniyor; uygulama bugune kadar hic gostermiyordu, dolayisiyla
            // "Katilacagim" dugmesi dolmus bir etkinlikte de acik duruyordu.
            if (event.remainingSeats != null) ...[
              const SizedBox(height: 2),
              Text(event.isFull ? 'Kontenjan doldu' : '${event.remainingSeats} kişilik yer kaldı', style: TextStyle(color: event.isFull ? AppColors.accentRose : AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ]),
        ]),
      );
}

/// Panelden iptal edilen etkinlik listeden dusuyor ama tek tek okunabiliyor:
/// takvimine yazan kisi 404 degil gerekcesini gormeli. Uygulama bugune kadar
/// iptali hic okumuyordu, yani panelden basilan "Iptal et" uyeye ulasmiyordu.
class _CancelledNotice extends StatelessWidget {
  const _CancelledNotice({required this.reason});
  final String? reason;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        color: const Color(0xFFFDECEF),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.event_busy_rounded, size: 19, color: AppColors.accentRose),
            SizedBox(width: 8),
            Text('Bu etkinlik iptal edildi', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.accentRose)),
          ]),
          if (reason != null && reason!.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(reason!, style: const TextStyle(color: AppColors.textSecondary, height: 1.4, fontSize: 13)),
          ],
        ]),
      );
}

/// Kayit her zaman uygulamada olmuyor. Sunucu bu durumda etkinligin kendi
/// bilet/kayit adresini gonderiyor -yalnizca https kabul ediliyor- ve bugune
/// kadar hicbir yerde gosterilmiyordu.
class _ExternalLinkRow extends StatelessWidget {
  const _ExternalLinkRow({required this.url});
  final String url;

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(url);
    final opened = uri != null && uri.scheme == 'https' && await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (opened || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bağlantı açılamadı.')));
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
        child: OutlinedButton.icon(
          onPressed: () => _open(context),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: const Text('Bilet ve kayıt sayfası'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 46), foregroundColor: AppColors.primary, side: const BorderSide(color: AppColors.surfaceBorder), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
      );
}

class _DetailBottomBar extends StatefulWidget {
  const _DetailBottomBar({required this.event, required this.controller});
  final CommunityEvent event;
  final EventsController controller;

  @override
  State<_DetailBottomBar> createState() => _DetailBottomBarState();
}

class _DetailBottomBarState extends State<_DetailBottomBar> {
  var _busy = false;

  /// Sunucu kontenjan dolu oldugunda 409 donuyor ve denetleyici iyimser
  /// degisikligi geri aliyor. Onceden bu hata hicbir yerde yakalanmiyordu:
  /// dugmeye basiliyor, yazi eski haline donuyor ve kullaniciya neden
  /// katilamadigi hic soylenmiyordu.
  Future<void> _toggle() async {
    setState(() => _busy = true);
    try {
      await widget.controller.setRsvp(widget.event, widget.event.isGoing ? EventRsvpStatus.none : EventRsvpStatus.going);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.event.isFull ? 'Kontenjan doldu, katılım kaydedilemedi.' : 'Katılım kaydedilemedi, tekrar dene.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    // Iptal edilmis ya da kontenjani dolmus etkinlikte dugme kapali: ikisinde
    // de sunucu zaten reddediyor, acik birakmak bos bir vaat oluyordu.
    final blocked = event.isCancelled || (event.isFull && !event.isGoing);
    return SafeArea(top: false, child: Container(padding: const EdgeInsets.fromLTRB(18, 12, 18, 14), decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.surfaceBorder))), child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [const Text('Katılım', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)), Text(event.priceLabel, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))])),
      const SizedBox(width: 12),
      FilledButton(
        onPressed: blocked || _busy ? null : _toggle,
        style: FilledButton.styleFrom(minimumSize: const Size(148, 46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        child: Text(event.isCancelled ? 'İptal edildi' : event.isFull && !event.isGoing ? 'Kontenjan doldu' : event.isGoing ? 'Katılmıyorum' : 'Katılacağım'),
      ),
    ])));
  }
}
