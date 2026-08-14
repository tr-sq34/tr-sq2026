import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_remote_image.dart';
import '../../../../core/widgets/app_state_views.dart';
import '../../application/marketplace_controller.dart';
import '../../domain/entities/marketplace_category.dart';
import '../../domain/entities/marketplace_listing.dart';
import '../../domain/entities/marketplace_seller.dart';
import 'marketplace_seller_profile_screen.dart';
import '../../../messaging/presentation/messaging_launcher.dart';
import '../../../verification/application/member_capabilities_controller.dart';

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({
    super.key,
    required this.controller,
    required this.memberCapabilitiesController,
    required this.messaging,
  });
  final MarketplaceController controller;
  final MemberCapabilitiesController memberCapabilitiesController;

  /// Satıcıyla konuşmanın yolu. Çarşı'nın her yerinde aynı düğme aynı yere
  /// gitsin diye tek bir nesne aşağıya iniyor.
  final MessagingLauncher messaging;

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  var _tab = 1;

  @override
  void initState() {
    super.initState();
    widget.controller.load();
    widget.controller.loadSellerDashboard();
    widget.memberCapabilitiesController.load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        if (widget.controller.isInitialLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        return Material(
          color: AppColors.background,
          child: Column(
            children: [
              // Ekranın kendi "Çarşı" başlığı kaldırıldı: kabuk zaten üst
              // barda sekmenin adını yazıyor, ikisi üst üste gelince başlık
              // iki kere görünüyordu. Yanındaki iki düğme de hiçbir yere
              // gitmiyordu.
              const SizedBox(height: 8),
              _TopTabs(
                index: _tab,
                onChanged: (value) {
                  setState(() => _tab = value);
                  if (value == 1) {
                    widget.controller.selectFeed(MarketplaceFeed.forYou);
                  }
                  if (value == 2) {
                    widget.controller.selectFeed(MarketplaceFeed.local);
                  }
                  if (value == 3) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MarketplaceCategoriesScreen(
                          controller: widget.controller,
                        ),
                      ),
                    );
                  }
                },
              ),
              Expanded(
                child: _tab == 0
                    ? SellerOverviewScreen(
                        controller: widget.controller,
                        memberCapabilitiesController:
                            widget.memberCapabilitiesController,
                        messaging: widget.messaging,
                      )
                    : MarketplaceFeedView(
                        controller: widget.controller,
                        local: _tab == 2,
                        messaging: widget.messaging,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TopTabs extends StatelessWidget {
  const _TopTabs({required this.index, required this.onChanged});
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = ['Satış Yap', 'Sana Özel', 'Yakınımda', 'Kategori'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: labels.asMap().entries.map((entry) {
            final i = entry.key;
            final label = entry.value;
            return InkWell(
              onTap: () => onChanged(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Column(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: index == i
                            ? AppColors.textPrimary
                            : AppColors.textMuted,
                        fontSize: 14,
                        fontWeight: index == i
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 3,
                      width: 28,
                      decoration: BoxDecoration(
                        color: index == i
                            ? AppColors.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class MarketplaceFeedView extends StatelessWidget {
  const MarketplaceFeedView({
    super.key,
    required this.controller,
    required this.local,
    required this.messaging,
  });
  final MarketplaceController controller;
  final bool local;
  final MessagingLauncher messaging;

  @override
  Widget build(BuildContext context) {
    final listings = controller.visibleItems;
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  local ? 'Yakınındaki ilanlar' : 'Bugünün seçkileri',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                local ? 'New York, NY' : 'Senin için',
                maxLines: 1,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Açık süzgeç ekranda görünüyor ve kapatması tek dokunuş: aksi halde
          // üye boş bir listeye bakıp Çarşı'da hiç ilan yok sanıyor.
          if (controller.savedOnly) ...[
            _OpenFilterRow(
              icon: Icons.bookmark_rounded,
              label: 'Kaydedilenler',
              onClear: () => controller.updateFilters(savedOnly: false),
            ),
            const SizedBox(height: 4),
          ],
          if (controller.category != 'all') ...[
            _OpenFilterRow(
              icon: MarketplaceCategory.of(controller.category).icon,
              label: MarketplaceCategory.labelOf(controller.category),
              onClear: () => controller.updateFilters(category: 'all'),
            ),
            const SizedBox(height: 4),
          ],
          if (listings.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 80),
              child: controller.savedOnly
                  ? const AppEmptyState(
                      icon: Icons.bookmark_border_rounded,
                      title: 'Kaydedilen ilan yok',
                      message:
                          'Beğendiğin ilanı kaydet, buradan kolayca geri dön.',
                    )
                  : controller.category != 'all'
                  ? AppEmptyState(
                      icon: MarketplaceCategory.of(controller.category).icon,
                      title:
                          '${MarketplaceCategory.labelOf(controller.category)} bölümünde ilan yok',
                      message: 'Başka bir bölüme bakmayı dene.',
                    )
                  : const AppEmptyState(
                      icon: Icons.location_off_outlined,
                      title: 'İlan bulunamadı',
                      message: 'Yeni ilanlar eklendiğinde burada görünecek.',
                    ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final width = (constraints.maxWidth - 10) / 2;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final listing in listings)
                      SizedBox(
                        width: width,
                        height: 246,
                        child: MarketplaceListingCard(
                          listing: listing,
                          controller: controller,
                          messaging: messaging,
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class MarketplaceListingCard extends StatelessWidget {
  const MarketplaceListingCard({
    super.key,
    required this.listing,
    required this.controller,
    required this.messaging,
  });
  final MarketplaceListing listing;
  final MarketplaceController controller;
  final MessagingLauncher messaging;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            builder: (_) => MarketplaceDetailScreen(
              listing: listing,
              controller: controller,
              messaging: messaging,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x120E0B18),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AppRemoteImage(
                    imageUrl: listing.imageUrl,
                    semanticLabel: listing.title,
                  ),
                  Positioned(
                    top: 7,
                    right: 7,
                    child: IconButton.filledTonal(
                      onPressed: () => controller.toggleSaved(listing.id),
                      icon: Icon(
                        listing.isSaved
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 18,
                        color: listing.isSaved
                            ? AppColors.accentRose
                            : AppColors.textSecondary,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '\$${listing.price.toStringAsFixed(0)} · ${listing.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    listing.location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MarketplaceCategoriesScreen extends StatelessWidget {
  const MarketplaceCategoriesScreen({super.key, required this.controller});
  final MarketplaceController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kategoriler')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        children: [
          TextField(
            onChanged: (value) => controller.updateFilters(query: value),
            decoration: InputDecoration(
              hintText: 'Ne satın almak istiyorsun?',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: const Color(0xFFF1F2F6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _CategoryRow(
            label: 'Kaydedilenler',
            icon: Icons.bookmark_outline_rounded,
            onTap: () {
              controller.updateFilters(savedOnly: true);
              Navigator.of(context).pop();
            },
          ),
          // "Etkinlik biletleri" satırı buradaydı ve hiçbir yere gitmiyordu:
          // dokunulabilir görünen, dokunulunca hiçbir şey olmayan bir satır.
          // Bilet diye bir kayıt yok; olduğu gün geri gelir.
          const Divider(height: 24),
          const Text(
            'Bölümler',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 6),
          // Bu satırların dördü eskiden hiçbir şey süzmüyordu: "Araçlar"a
          // dokunmak da "Elektronik"e dokunmak da tüm Çarşı'yı geri veriyordu,
          // çünkü sunucu her ilana aynı kategoriyi yazıyordu.
          for (final category in MarketplaceCategory.values)
            _CategoryRow(
              label: category.label,
              icon: category.icon,
              onTap: () {
                controller.updateFilters(category: category.key);
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
    );
  }
}

/// Açık bir süzgeç ve onu kapatan düğme.
class _OpenFilterRow extends StatelessWidget {
  const _OpenFilterRow({
    required this.icon,
    required this.label,
    required this.onClear,
  });
  final IconData icon;
  final String label;
  final VoidCallback onClear;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: AppColors.primary),
      const SizedBox(width: 6),
      Expanded(
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      TextButton(onPressed: onClear, child: const Text('Tüm ilanlar')),
    ],
  );
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.label, required this.icon, this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(
      backgroundColor: const Color(0xFFF0F1F4),
      child: Icon(icon, color: AppColors.textPrimary),
    ),
    title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    trailing: const Icon(Icons.chevron_right_rounded),
  );
}

class SellerOverviewScreen extends StatelessWidget {
  const SellerOverviewScreen({
    super.key,
    required this.controller,
    required this.memberCapabilitiesController,
    required this.messaging,
  });
  final MarketplaceController controller;
  final MemberCapabilitiesController memberCapabilitiesController;
  final MessagingLauncher messaging;

  @override
  Widget build(BuildContext context) {
    final dashboard = controller.dashboard;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
      children: [
        _AuctionEligibilityCard(controller: memberCapabilitiesController),
        const SizedBox(height: 16),
        InkWell(
          onTap: () => Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(
              // Kendi sayfasi: kimlik panelin kendisinden geliyor, sabit bir
              // demo kimliginden degil.
              builder: (_) => MarketplaceSellerProfileScreen(
                controller: controller,
                sellerId: dashboard?.sellerId ?? '',
                messaging: messaging,
              ),
            ),
          ),
          child: Row(
            children: [
              const CircleAvatar(radius: 22, child: Text('A')),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Satış merkezim',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      'Çarşıdaki ilanların ve taleplerin',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            builder: (_) => ListingTypeSheet(controller: controller),
          ),
          icon: const Icon(Icons.add_rounded),
          label: const Text('İlan oluştur'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        const SizedBox(height: 18),
        // Yalnızca Çarşı'nın gerçekten saydığı şeyler. "Görüntülenme" ve
        // "Teklif" kutuları kalktı: hiçbiri bu sistemde tutulmuyordu, ikisi de
        // her üyeye sabit sıfır gösteriyordu.
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _Metric(
              label: 'Aktif ilan',
              value: '${dashboard?.activeListings ?? 0}',
            ),
            _Metric(label: 'Kaydedilme', value: '${dashboard?.saves ?? 0}'),
            _Metric(label: 'Beğeni', value: '${dashboard?.likes ?? 0}'),
            _Metric(label: 'Paylaşım', value: '${dashboard?.shares ?? 0}'),
            if ((dashboard?.soldListings ?? 0) > 0)
              _Metric(label: 'Satıldı', value: '${dashboard!.soldListings}'),
            if ((dashboard?.reservedListings ?? 0) > 0)
              _Metric(
                label: 'Rezerve',
                value: '${dashboard!.reservedListings}',
              ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const Text(
              'Performansın',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            TextButton(
              onPressed: controller.loadSellerDashboard,
              child: const Text('Yenile'),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F3FF),
            borderRadius: BorderRadius.circular(18),
          ),
          child: dashboard == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dashboard.hasWeeklyActivity
                          ? 'Son 7 gün'
                          : 'Son 7 günde yeni bir hareket yok',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (dashboard.hasWeeklyActivity) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          if (dashboard.saves7d > 0)
                            Text('${dashboard.saves7d} kaydetme'),
                          if (dashboard.likes7d > 0)
                            Text('${dashboard.likes7d} beğeni'),
                          if (dashboard.shares7d > 0)
                            Text('${dashboard.shares7d} paylaşım'),
                        ],
                      ),
                    ],
                    // Kaydeden kimse yokken "en iyi ilan" diye bir şey yok.
                    if (dashboard.topListing case final top?
                        when top.saves > 0) ...[
                      const SizedBox(height: 10),
                      Text(
                        'En çok kaydedilen: ${top.title} (${top.saves})',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _AuctionEligibilityCard extends StatelessWidget {
  const _AuctionEligibilityCard({required this.controller});
  final MemberCapabilitiesController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final eligible = controller.value.auctionSellerEligible;
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: eligible ? const Color(0xFFEAFBF3) : const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: eligible ? const Color(0xFF86E2B3) : const Color(0xFFFDD29A),
          ),
        ),
        child: Row(
          children: [
            Icon(
              eligible ? Icons.gavel_rounded : Icons.verified_user_outlined,
              color: eligible
                  ? const Color(0xFF059669)
                  : const Color(0xFFB45309),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                eligible
                    ? 'Canlı ihale açma yetkin aktif.'
                    : 'Canlı ihale açmak için Onaylı Hesap rozeti gerekir.',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    child: Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F3FF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
          ),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    ),
  );
}

class ListingTypeSheet extends StatelessWidget {
  const ListingTypeSheet({super.key, required this.controller});
  final MarketplaceController controller;
  @override
  Widget build(BuildContext context) {
    const options = [
      (MarketplaceListingType.item, 'Tek ürün', Icons.inventory_2_outlined),
      (MarketplaceListingType.bundle, 'Çoklu ürün', Icons.sell_outlined),
      (MarketplaceListingType.vehicle, 'Araç', Icons.directions_car_outlined),
      (
        MarketplaceListingType.home,
        'Satılık veya kiralık ev',
        Icons.home_outlined,
      ),
      (
        MarketplaceListingType.saleEvent,
        'Satış etkinliği',
        Icons.event_outlined,
      ),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Yeni ilan oluştur',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final option in options)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFF0F1F4),
                  child: Icon(option.$3),
                ),
                title: Text(
                  option.$2,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () async {
                  await controller.beginDraft(option.$1);
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ListingComposerScreen(controller: controller),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class ListingComposerScreen extends StatefulWidget {
  const ListingComposerScreen({super.key, required this.controller});
  final MarketplaceController controller;
  @override
  State<ListingComposerScreen> createState() => _ListingComposerScreenState();
}

class _ListingComposerScreenState extends State<ListingComposerScreen> {
  final _title = TextEditingController();
  final _price = TextEditingController();
  final _description = TextEditingController();
  final _location = TextEditingController(text: 'New York, NY');
  final _fields = <String, TextEditingController>{};
  final _picker = ImagePicker();
  bool _uploading = false;

  /// Seçilen fotoğraflar tek tek yükleniyor ve her biri taramadan geçtikçe
  /// şeride ekleniyor. Biri reddedilirse yalnızca o düşüyor, diğerleri kalıyor:
  /// altı fotoğraf seçen birine "hepsini baştan seç" demek gereksiz.
  Future<void> _pickPhotos() async {
    final files = await _picker.pickMultiImage(imageQuality: 85);
    if (files.isEmpty || !mounted) return;
    final draft = widget.controller.draft;
    if (draft == null) return;
    final room = MarketplaceController.maxDraftPhotos - draft.mediaIds.length;
    if (room <= 0) return;
    setState(() => _uploading = true);
    for (final file in files.take(room)) {
      final bytes = await file.readAsBytes();
      final error = await widget.controller.attachDraftPhoto(
        localUri: file.path,
        fileName: file.name,
        sizeBytes: bytes.length,
      );
      if (!mounted) return;
      setState(() {});
      if (error != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      }
    }
    if (mounted) setState(() => _uploading = false);
  }

  @override
  void initState() {
    super.initState();
    final draft = widget.controller.draft!;
    _title.text = draft.title;
    _price.text = draft.price?.toString() ?? '';
    _description.text = draft.description;
    if (draft.location.isNotEmpty) _location.text = draft.location;
  }

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    _description.dispose();
    _location.dispose();
    for (final item in _fields.values) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _pickChoice(String key, String label) async {
    final choices = switch (key) {
      'propertyType' => const [
        'Daire',
        'Müstakil Ev',
        'Villa',
        'Arsa',
        'Ticari',
      ],
      'parking' => const ['Açık Otopark', 'Kapalı Otopark', 'Garaj', 'Yok'],
      'vehicleType' => const ['Otomobil', 'SUV', 'Motosiklet', 'Ticari Araç'],
      _ => <String>[],
    };

    final selection = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ...choices.map(
              (c) => ListTile(
                title: Text(c),
                onTap: () => Navigator.of(context).pop(c),
              ),
            ),
          ],
        ),
      ),
    );
    if (selection != null)
      setState(
        () => _fields.putIfAbsent(key, TextEditingController.new).text =
            selection,
      );
  }

  Future<void> _save({bool publish = false}) async {
    final current = widget.controller.draft!;
    await widget.controller.updateDraft(
      current.copyWith(
        title: _title.text,
        price: double.tryParse(_price.text),
        description: _description.text,
        location: _location.text,
        fields: {
          for (final entry in _fields.entries) entry.key: entry.value.text,
        },
      ),
    );
    if (!publish) return;
    final error = widget.controller.validateDraft();
    if (error != null) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    final listing = await widget.controller.publishDraft();
    if (listing != null && mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('İlan yayınlandı.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.controller.draft!.type;
    final extras = switch (type) {
      MarketplaceListingType.vehicle => const [
        ('vehicleType', 'Araç türü'),
        ('year', 'Yıl'),
        ('make', 'Marka'),
        ('model', 'Model'),
        ('owners', 'Sahip sayısı'),
      ],
      MarketplaceListingType.home => const [
        ('propertyType', 'Mülk türü'),
        ('bedrooms', 'Yatak odası'),
        ('bathrooms', 'Banyo'),
        ('squareFeet', 'Metrekare'),
        ('parking', 'Park türü'),
      ],
      MarketplaceListingType.saleEvent => const [
        ('eventDate', 'Tarih'),
        ('venue', 'Mekan'),
      ],
      MarketplaceListingType.bundle => const [('itemCount', 'Ürün adedi')],
      MarketplaceListingType.item => const [],
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('İlan detayları'),
        actions: [
          TextButton(
            onPressed: () => _save(publish: true),
            child: const Text('Yayınla'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          _ListingPhotoStrip(
            urls: widget.controller.draft!.mediaUrls,
            busy: _uploading,
            onAdd: widget.controller.canAttachPhotos ? _pickPhotos : null,
            onRemove: widget.controller.removeDraftPhoto,
          ),
          const SizedBox(height: 14),
          // Burada "AI ile taslağı doldur" düğmesi vardı. Fotoğrafa hiç
          // bakmadan, yalnızca ilan türüne göre başlık, fiyat ve açıklama
          // uyduruyordu; sattığı arabaya kendiliğinden 8500 yazıyordu. Yerini
          // aldığı tek gerçek iş buydu: kategoriyi seçmek. Onu da satıcı
          // seçiyor artık ve seçtiği şey sunucuya gidiyor.
          _CategoryField(
            value: MarketplaceCategory.of(widget.controller.draft!.category),
            onChanged: (category) async {
              await _save();
              await widget.controller.updateDraft(
                widget.controller.draft!.copyWith(category: category.key),
              );
              if (mounted) setState(() {});
            },
          ),
          _Field(controller: _title, hint: 'Başlık', icon: Icons.title_rounded),
          _Field(
            controller: _price,
            hint: 'Fiyat',
            icon: Icons.sell_outlined,
            // Kutuda 'TL' yazıyordu, ilan yayınlanınca aynı sayı listede
            // "$145" olarak çiziliyordu. Çarşı Amerika'da: para dolar.
            suffixText: r'$',
            keyboardType: TextInputType.number,
          ),
          _Field(
            controller: _location,
            hint: 'Konum',
            icon: Icons.location_on_outlined,
          ),
          for (final item in extras)
            if (item.$1 == 'bedrooms' || item.$1 == 'bathrooms')
              _SegmentedField(
                label: item.$2,
                icon: item.$1 == 'bedrooms'
                    ? Icons.bed_outlined
                    : Icons.bathtub_outlined,
                value: _fields
                    .putIfAbsent(item.$1, TextEditingController.new)
                    .text,
                onSelected: (value) =>
                    setState(() => _fields[item.$1]!.text = value),
              )
            else if (item.$1 == 'propertyType' ||
                item.$1 == 'parking' ||
                item.$1 == 'vehicleType')
              _ChoiceField(
                label: item.$2,
                icon: item.$1 == 'propertyType'
                    ? Icons.home_work_outlined
                    : item.$1 == 'parking'
                    ? Icons.local_parking_outlined
                    : Icons.directions_car_outlined,
                value: _fields
                    .putIfAbsent(item.$1, TextEditingController.new)
                    .text,
                onTap: () => _pickChoice(item.$1, item.$2),
              )
            else
              _Field(
                controller: _fields.putIfAbsent(
                  item.$1,
                  TextEditingController.new,
                ),
                hint: item.$2,
                icon: item.$1 == 'squareFeet'
                    ? Icons.square_foot_outlined
                    : Icons.edit_outlined,
                suffixText: item.$1 == 'squareFeet' ? 'm²' : null,
                keyboardType:
                    item.$1 == 'squareFeet' ||
                        item.$1 == 'year' ||
                        item.$1 == 'owners' ||
                        item.$1 == 'itemCount'
                    ? TextInputType.number
                    : null,
              ),
          _Field(
            controller: _description,
            hint: 'Açıklama',
            icon: Icons.notes_rounded,
            lines: 5,
          ),
          FilledButton(
            onPressed: () => _save(publish: true),
            child: const Text('Yayınla'),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    this.lines = 1,
    this.keyboardType,
    this.icon,
    this.suffixText,
  });
  final TextEditingController controller;
  final String hint;
  final int lines;
  final TextInputType? keyboardType;
  final IconData? icon;
  final String? suffixText;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      minLines: lines,
      maxLines: lines,
      keyboardType: keyboardType,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: hint,
        prefixIcon: icon == null ? null : Icon(icon, color: AppColors.primary),
        suffixText: suffixText,
        suffixStyle: const TextStyle(fontWeight: FontWeight.w800),
        filled: true,
        fillColor: const Color(0xFFFCFBFE),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.surfaceBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    ),
  );
}

/// İlanın hangi bölümde görüneceği. Alıcının Çarşı'da "Araçlar"a dokunduğunda
/// bu ilanı bulup bulamayacağı buna bakıyor, o yüzden düzenleyicinin en
/// üstünde ve her zaman dolu.
class _CategoryField extends StatelessWidget {
  const _CategoryField({required this.value, required this.onChanged});
  final MarketplaceCategory value;
  final ValueChanged<MarketplaceCategory> onChanged;

  Future<void> _pick(BuildContext context) async {
    final selection = await showModalBottomSheet<MarketplaceCategory>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'İlan hangi bölümde görünsün?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            for (final category in MarketplaceCategory.values)
              ListTile(
                leading: Icon(category.icon, color: AppColors.textPrimary),
                title: Text(category.label),
                trailing: category == value
                    ? const Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(category),
              ),
          ],
        ),
      ),
    );
    if (selection != null) onChanged(selection);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(16),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Bölüm',
          prefixIcon: Icon(value.icon, color: AppColors.primary),
          filled: true,
          fillColor: const Color(0xFFFCFBFE),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.surfaceBorder),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value.label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(Icons.expand_more_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    ),
  );
}

/// İlanın fotoğraf şeridi. Buradaki kutu eskiden yalnızca bir çizimdi:
/// dokunulduğunda hiçbir şey olmuyordu ve her ilan aynı stok mutfak
/// fotoğrafıyla yayına giriyordu.
class _ListingPhotoStrip extends StatelessWidget {
  const _ListingPhotoStrip({
    required this.urls,
    required this.busy,
    required this.onAdd,
    required this.onRemove,
  });
  final List<String> urls;
  final bool busy;
  final VoidCallback? onAdd;
  final Future<void> Function(int index) onRemove;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 116,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final (index, url) in urls.indexed)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 116,
                    height: 116,
                    child: AppRemoteImage(
                      imageUrl: url,
                      semanticLabel: 'İlan fotoğrafı ${index + 1}',
                    ),
                  ),
                ),
                // İlk fotoğraf kapak oluyor; satıcının bunu bilmesi gerekiyor.
                if (index == 0)
                  const Positioned(left: 6, bottom: 6, child: _CoverTag()),
                Positioned(
                  right: 2,
                  top: 2,
                  child: IconButton(
                    tooltip: 'Fotoğrafı kaldır',
                    icon: const CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.black54,
                      child: Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                    onPressed: () => onRemove(index),
                  ),
                ),
              ],
            ),
          ),
        if (urls.length < MarketplaceController.maxDraftPhotos)
          SizedBox(
            width: 116,
            child: InkWell(
              onTap: busy ? null : onAdd,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.surfaceBorder),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.add_a_photo_outlined),
                            const SizedBox(height: 6),
                            Text(
                              onAdd == null
                                  ? 'Fotoğraf eklenemiyor'
                                  : 'Fotoğraf ekle',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _CoverTag extends StatelessWidget {
  const _CoverTag();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(6),
    ),
    child: const Text(
      'Kapak',
      style: TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class MarketplaceDetailScreen extends StatefulWidget {
  const MarketplaceDetailScreen({
    super.key,
    required this.listing,
    required this.controller,
    required this.messaging,
  });
  final MarketplaceListing listing;
  final MarketplaceController controller;
  final MessagingLauncher messaging;
  @override
  State<MarketplaceDetailScreen> createState() =>
      _MarketplaceDetailScreenState();
}

class _MarketplaceDetailScreenState extends State<MarketplaceDetailScreen> {
  /// İlanın altındaki hazır soru. Ekranda ne yazıyorsa satıcıya o gidiyor.
  static const _quickQuestion = 'Hâlâ satılık mı?';

  bool _opening = false;

  /// İlanın altındaki düğme aylardır hiçbir şey göndermeden "Mesaj İsteği
  /// Gönderildi" diyordu. Artık satıcıyla sohbeti gerçekten açıyor; alıcı ne
  /// söyleyeceğini kendi yazıyor.
  Future<void> _contactSeller({String? firstMessage}) async {
    if (_opening) return;
    setState(() => _opening = true);
    final opened = await widget.messaging.openWithMember(
      context,
      userId: widget.listing.sellerId,
      firstMessage: firstMessage,
    );
    if (!mounted) return;
    setState(() => _opening = false);
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Satıcıyla sohbet şu anda açılamadı.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final canContact = widget.messaging.canMessage(listing.sellerId);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leadingWidth: 64,
        leading: Center(
          child: Container(
            margin: const EdgeInsets.only(left: 12),
            decoration: const BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(
                Icons.chevron_left,
                color: Colors.white,
                size: 20,
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),
        actions: [
          Container(
            decoration: const BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: () => widget.controller.toggleSaved(listing.id),
              icon: Icon(
                listing.isSaved
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                color: listing.isSaved ? Colors.amber : Colors.white,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: const BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: () => widget.controller.registerShare(listing.id),
              icon: const Icon(
                Icons.share_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      // Kendi ilanında satıcı sensin: kendine mesaj gönderilmiyor, o yüzden
      // düğme de yok.
      bottomNavigationBar: !canContact
          ? null
          : Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10 + 20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                border: const Border(top: BorderSide(color: Color(0xFFF1F5F9))),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _opening ? null : _contactSeller,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3B3383), Color(0xFF6355D8)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6355D8).withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Satıcı ile İletişime Geç',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.zero,
            children: [
              _ListingGallery(listing: listing),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing.title,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F3FF),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF6355D8).withValues(alpha: 0.1),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 8,
                            backgroundColor: Color(0xFF6355D8),
                            child: Icon(
                              Icons.check,
                              size: 10,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Onaylı Satıcı',
                              style: TextStyle(
                                color: Color(0xFF3B3383),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Flexible(
                            child: Text(
                              ' · Doğrulanmış Mağaza',
                              style: TextStyle(
                                color: Color(0xFF6355D8),
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFF1F5F9)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3B3383),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF3B3383,
                                      ).withValues(alpha: 0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.store_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'ÇARŞI FİYATI',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF94A3B8),
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  Text(
                                    '\$${listing.price.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF2D2768),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFA7F3D0),
                              ),
                            ),
                            child: const Text(
                              'Stokta Var',
                              style: TextStyle(
                                color: Color(0xFF047857),
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _PremiumActionChip(
                            icon: listing.isLiked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            label: listing.isLiked ? 'Beğenildi' : 'Beğen',
                            isactive: listing.isLiked,
                            onTap: () =>
                                widget.controller.toggleLiked(listing.id),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _PremiumActionChip(
                            icon: listing.isSaved
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_border_rounded,
                            label: listing.isSaved ? 'Kaydedildi' : 'Kaydet',
                            isactive: listing.isSaved,
                            onTap: () =>
                                widget.controller.toggleSaved(listing.id),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _PremiumActionChip(
                            icon: Icons.ios_share_rounded,
                            label: 'Paylaş',
                            onTap: () =>
                                widget.controller.registerShare(listing.id),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Hazir soru kutusu da satici konusulabilir oldugunda var.
                    if (canContact)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFF1F5F9)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  color: Color(0xFF6355D8),
                                  size: 16,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Hızlı Soru Sor',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Color(0xFF334155),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            InkWell(
                              onTap: _opening
                                  ? null
                                  : () => _contactSeller(
                                      firstMessage: _quickQuestion,
                                    ),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFFD9D6FE),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.03,
                                      ),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 12,
                                          backgroundColor: Color(0xFFF5F3FF),
                                          child: Icon(
                                            Icons.send_rounded,
                                            size: 12,
                                            color: Color(0xFF6355D8),
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          _quickQuestion,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                            color: Color(0xFF1E293B),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        Text(
                                          'Gönder',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                            color: Color(0xFF6355D8),
                                          ),
                                        ),
                                        Icon(
                                          Icons.chevron_right_rounded,
                                          size: 14,
                                          color: Color(0xFF6355D8),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    const Text(
                      'AÇIKLAMA',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF94A3B8),
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC).withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFF1F5F9)),
                      ),
                      child: Text(
                        listing.description.isEmpty
                            ? 'Ürün ayrıntıları için satıcıyla iletişime geçin.'
                            : listing.description,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF475569),
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'SATICI',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF94A3B8),
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () {
                        Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute<void>(
                            builder: (_) => MarketplaceSellerProfileScreen(
                              controller: widget.controller,
                              sellerId: listing.sellerId,
                              messaging: widget.messaging,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFF1F5F9)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Stack(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xFF6355D8),
                                        Color(0xFF4F46E5),
                                      ],
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      listing.sellerName.isEmpty
                                          ? '?'
                                          : listing.sellerName.substring(0, 1),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.check,
                                      size: 8,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          listing.sellerName.isEmpty
                                              ? 'Satıcı'
                                              : listing.sellerName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      const Icon(
                                        Icons.verified_rounded,
                                        size: 14,
                                        color: Color(0xFF6355D8),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.star_rounded,
                                        size: 14,
                                        color: Color(0xFFFBBF24),
                                      ),
                                      const SizedBox(width: 4),
                                      const Text(
                                        '4.8',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: Color(0xFF1E293B),
                                        ),
                                      ),
                                      Flexible(
                                        child: Text(
                                          ' · Profili Gör',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: const Color(0xFF64748B),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: Color(0xFFCBD5E1),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'KONUM',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF94A3B8),
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Burada harita gibi görünen bir kutu vardı: koda yazılmış
                    // tek bir stok hava fotoğrafı, ortasında bir iğne ve
                    // altında ilanın şehri. İğne hiçbir yeri göstermiyordu,
                    // fotoğraf da her ilanda aynıydı - satılan şey nerede
                    // olursa olsun aynı sokakları gösteriyordu. Sunucu ilanın
                    // koordinatını hiç tutmuyor, yalnızca şehir ve bölge; o
                    // yüzden çizilecek bir harita yok. Yazan da bu.
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFF1F5F9)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFF6355D8).withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.location_on_rounded,
                              color: Color(0xFF6355D8),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  listing.location.isEmpty
                                      ? 'Konum belirtilmemiş'
                                      : listing.location,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'Satıcı yalnızca şehrini paylaşıyor; tam adres verilmiyor.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF64748B),
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PremiumActionChip extends StatelessWidget {
  const _PremiumActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isactive = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isactive;

  @override
  Widget build(BuildContext context) => Material(
    color: isactive ? const Color(0xFFFFF1F2) : const Color(0xFFF5F3FF),
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isactive ? const Color(0xFFFECDD3) : const Color(0xFFEBE9FE),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isactive
                  ? const Color(0xFFE11D48)
                  : const Color(0xFF6355D8),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isactive
                    ? const Color(0xFF9F1239)
                    : const Color(0xFF3B3383),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ListingGallery extends StatefulWidget {
  const _ListingGallery({required this.listing});
  final MarketplaceListing listing;
  @override
  State<_ListingGallery> createState() => _ListingGalleryState();
}

class _ListingGalleryState extends State<_ListingGallery> {
  var _index = 0;
  final _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.listing.mediaUrls.isEmpty
        ? [widget.listing.imageUrl]
        : widget.listing.mediaUrls;
    return SizedBox(
      height: 250,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: images.length,
            onPageChanged: (index) => setState(() => _index = index),
            itemBuilder: (_, index) => Stack(
              fit: StackFit.expand,
              children: [
                AppRemoteImage(
                  imageUrl: images[index],
                  semanticLabel: widget.listing.title,
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x77000000),
                        Color(0x00000000),
                        Color(0x00000000),
                        Color(0x22000000),
                      ],
                      stops: [0.0, 0.25, 0.8, 1.0],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Navigation Arrows
          if (images.length > 1) ...[
            Positioned(
              left: 12,
              top: 0,
              bottom: 0,
              child: Center(
                child: _ArrowButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: () => _pageController.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 12,
              top: 0,
              bottom: 0,
              child: Center(
                child: _ArrowButton(
                  icon: Icons.chevron_right_rounded,
                  onTap: () => _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  ),
                ),
              ),
            ),
          ],
          // Index Badge
          Positioned(
            bottom: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.image_outlined,
                    color: Colors.white,
                    size: 12,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${_index + 1} / ${images.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: Colors.black38,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _ChoiceField extends StatelessWidget {
  const _ChoiceField({
    required this.label,
    required this.icon,
    required this.value,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final String value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        decoration: BoxDecoration(
          color: const Color(0xFFFCFBFE),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.surfaceBorder),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                  Text(
                    value.isEmpty ? 'Seçiniz' : value,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: value.isEmpty
                          ? AppColors.textMuted
                          : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    ),
  );
}

class _SegmentedField extends StatelessWidget {
  const _SegmentedField({
    required this.label,
    required this.icon,
    required this.value,
    required this.onSelected,
  });
  final String label;
  final IconData icon;
  final String value;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 7),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: '1', label: Text('1')),
            ButtonSegment(value: '2', label: Text('2')),
            ButtonSegment(value: '3', label: Text('3')),
            ButtonSegment(value: '4+', label: Text('4+')),
          ],
          selected: value.isEmpty ? const {} : {value},
          emptySelectionAllowed: true,
          onSelectionChanged: (selected) {
            if (selected.isNotEmpty) onSelected(selected.first);
          },
        ),
      ],
    ),
  );
}
