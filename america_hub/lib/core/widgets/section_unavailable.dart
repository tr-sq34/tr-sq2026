import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Ana sayfadaki bir şeridin kaynağına ulaşılamadığında çizilen satır.
///
/// Şeritlerin hepsi aynı şeyi yapıyordu: liste boşsa `SizedBox.shrink()`.
/// Bu, "bugün etkinlik yok" ile "etkinlik servisine ulaşılamadı"yı aynı
/// görüntüye indiriyordu - üye ikisini de sayfada hiçbir şey olmaması olarak
/// görüyor, yeniden denemesi gereken şeyin ne olduğunu bilmiyordu.
///
/// Bölüm gerçekten boşken hâlâ çizilmiyor: içeriği olmayan bir şeridi başlıkla
/// göstermek de kendi başına bir yalan olurdu. Çizilen tek durum, istek
/// başarısız olduğu için elde hiçbir şey olmaması.
class SectionUnavailable extends StatelessWidget {
  const SectionUnavailable({
    super.key,
    required this.title,
    required this.message,
    required this.onRetry,
  });

  /// Neyin gelmediği. "Yaklaşan etkinlikler", "Manşetler" gibi - üyenin
  /// eksikliği fark ettiği yerin adı.
  final String title;

  /// Neden gelmediği; denetleyicinin kendi cümlesi.
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            size: 18,
            color: Color(0xFF94A3B8),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Yeniden dene',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
