import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_remote_image.dart';
import '../../application/marketplace_controller.dart';
import '../../domain/entities/marketplace_listing.dart';
import '../../domain/entities/marketplace_seller.dart';
import 'marketplace_screen.dart';

class MarketplaceSellerProfileScreen extends StatefulWidget {
  const MarketplaceSellerProfileScreen({
    super.key,
    required this.controller,
    required this.sellerId,
    this.embedded = false,
  });

  final MarketplaceController controller;
  final String sellerId;
  final bool embedded;

  @override
  State<MarketplaceSellerProfileScreen> createState() =>
      _MarketplaceSellerProfileScreenState();
}

class _MarketplaceSellerProfileScreenState
    extends State<MarketplaceSellerProfileScreen> {
  MarketplaceSellerProfile? _profile;
  List<MarketplaceListing>? _listings;
  bool _loading = true;
  String? _error;
  bool _isFollowing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.controller.sellerProfile(widget.sellerId),
        widget.controller.sellerListings(widget.sellerId),
      ]);
      if (mounted) {
        setState(() {
          _profile = results[0] as MarketplaceSellerProfile;
          _listings = results[1] as List<MarketplaceListing>;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Hata: $_error'),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Tekrar Dene')),
          ],
        ),
      );
    }

    final p = _profile!;
    final listings = _listings ?? [];

    return CustomScrollView(
      slivers: [
        // PREMIUM HEADER
        SliverToBoxAdapter(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1E1A47),
                  Color(0xFF3B3383),
                  Color(0xFF6355D8)
                ],
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(16, 56, 16, 24),
            child: Column(
              children: [
                // Nav Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _CircleIconBtn(
                      icon: Icons.chevron_left_rounded,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const Text(
                      'Satıcı vitrini',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                    _CircleIconBtn(
                      icon: Icons.more_vert_rounded,
                      onTap: () {},
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Identity Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar with Gradient Border
                    Stack(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2.5),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                Color(0xFFFBBF24),
                                Color(0xFFF43F5E),
                                Color(0xFF6355D8)
                              ],
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 32,
                            backgroundColor: const Color(0xFF1E1A47),
                            backgroundImage: (p.avatarUrl?.isNotEmpty ?? false)
                                ? NetworkImage(p.avatarUrl!)
                                : null,
                            onBackgroundImageError: (p.avatarUrl?.isNotEmpty ?? false)
                                ? (exception, stackTrace) {}
                                : null,
                            child: (p.avatarUrl?.isEmpty ?? true)
                                ? Text(
                                    p.displayName.substring(0, 1).toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 24,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        Positioned(
                          bottom: 2,
                          right: 2,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: const Color(0xFF1E1A47), width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    // Name & Tags
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  p.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color:
                                          Colors.amber.withValues(alpha: 0.5)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.shield_outlined,
                                        size: 10, color: Colors.amber),
                                    SizedBox(width: 4),
                                    Text(
                                      'Onaylı Satıcı',
                                      style: TextStyle(
                                        color: Colors.amber,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Katılım: ${_formatDate(p.memberSince)}',
                            style: const TextStyle(
                              color: Color(0xFFD9D6FE),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Rating
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.star_rounded,
                                        color: Colors.amber, size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${p.rating}',
                                      style: const TextStyle(
                                        color: Colors.amber,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '(${p.reviewCount} Değerlendirme)',
                                style: const TextStyle(
                                  color: Color(0xFFD9D6FE),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Actions
                Row(
                  children: [
                    Expanded(
                      child: _HeaderBtn(
                        label: 'Mesaj Gönder',
                        icon: Icons.send_rounded,
                        onTap: () {},
                        primary: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _HeaderBtn(
                        label: _isFollowing ? 'Takip Ediliyor' : 'Takip Et',
                        icon: _isFollowing
                            ? Icons.check_rounded
                            : Icons.person_add_rounded,
                        onTap: () =>
                            setState(() => _isFollowing = !_isFollowing),
                        primary: false,
                        active: _isFollowing,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // CONTENT
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Performance Summary
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: const Color(0xFFD9D6FE).withValues(alpha: 0.3)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF5F3FF),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.analytics_outlined,
                                      color: Color(0xFF6355D8), size: 18),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Güven & Performans Özeti',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Color(0xFF0F172A)),
                                      ),
                                      Text(
                                        'Son 30 günlük satıcı verileri',
                                        style: TextStyle(
                                            color: Color(0xFF94A3B8),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFA7F3D0)),
                            ),
                            child: const Text(
                              'Yüksek Puanlı',
                              style: TextStyle(
                                  color: Color(0xFF047857),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 9),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFF1F5F9)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _MetricItem(
                                icon: Icons.bolt_rounded,
                                iconColor: Colors.amber,
                                label: 'Yanıt Oranı',
                                value: '%${p.responseRate}',
                              ),
                            ),
                            Container(
                                width: 1,
                                height: 24,
                                color: const Color(0xFFE2E8F0)),
                            Expanded(
                              child: _MetricItem(
                                icon: Icons.access_time_rounded,
                                iconColor: const Color(0xFF6355D8),
                                label: 'Ort. Yanıt Süresi',
                                value: 'Ort. ${p.averageResponseMinutes} dk',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                const Text(
                  'GÜVEN ROZETLERİ',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF94A3B8),
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final b in p.badges)
                      _ModernBadgeChip(
                        label: b.label,
                        icon: _getBadgeIcon(b.icon),
                        color: _getBadgeColor(b.icon),
                      ),
                  ],
                ),

                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'AKTİF İLANLARI (${listings.length})',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF94A3B8),
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Text(
                      'Tümünü Gör',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6355D8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),

        // Listings Grid
        if (listings.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text('Henüz aktif bir ilan bulunmuyor.',
                    style: TextStyle(color: Colors.grey)),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.72,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => MarketplaceListingCard(
                  listing: listings[index],
                  controller: widget.controller,
                ),
                childCount: listings.length,
              ),
            ),
          ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık'
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  IconData _getBadgeIcon(String icon) => switch (icon) {
        'verified' => Icons.badge_rounded,
        'bolt' => Icons.bolt_rounded,
        'handshake' => Icons.handshake_rounded,
        'groups' => Icons.workspace_premium_rounded,
        _ => Icons.verified_user_rounded,
      };

  Color _getBadgeColor(String icon) => switch (icon) {
        'verified' => const Color(0xFF10B981),
        'bolt' => const Color(0xFFF59E0B),
        'handshake' => const Color(0xFF6355D8),
        'groups' => const Color(0xFF4F46E5),
        _ => const Color(0xFF64748B),
      };
}

class _CircleIconBtn extends StatelessWidget {
  const _CircleIconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white.withValues(alpha: 0.1),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      );
}

class _HeaderBtn extends StatelessWidget {
  const _HeaderBtn(
      {required this.label,
      required this.icon,
      required this.onTap,
      this.primary = true,
      this.active = false});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final bgColor = primary
        ? Colors.white
        : (active ? const Color(0xFF10B981) : Colors.white.withValues(alpha: 0.15));
    final textColor = primary ? const Color(0xFF1E1A47) : Colors.white;
    final iconColor = primary ? const Color(0xFF6355D8) : Colors.white;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: primary
                ? null
                : Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricItem extends StatelessWidget {
  const _MetricItem(
      {required this.icon,
      required this.iconColor,
      required this.label,
      required this.value});
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 9,
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.bold)),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF334155))),
              ],
            ),
          ),
        ],
      );
}

class _ModernBadgeChip extends StatelessWidget {
  const _ModernBadgeChip(
      {required this.label, required this.icon, required this.color});
  final String label;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 14),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF334155)),
            ),
          ],
        ),
      );
}
