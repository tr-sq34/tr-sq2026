import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_remote_image.dart';
import '../../domain/entities/promotion.dart';

/// Hedefi olmayan bir tanıtıma dokunulduğunda açılan yüzey.
///
/// Bir tanıtımın gideceği yer her zaman olmak zorunda değil — çoğu yalnızca bir
/// duyuru. Böyle bir karta dokunmanın hiçbir şey yapmaması ise ekranı yalancı
/// yapardı; o yüzden dokunuş tanıtımın kendisini açıyor.
class PromotionDetailSheet extends StatelessWidget {
  const PromotionDetailSheet({super.key, required this.promotion});

  final Promotion promotion;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Center(
        child: Container(
          width: 38,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFFD8D5DF),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      const SizedBox(height: 16),
      if (promotion.imageUrl case final url?) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: 180,
            width: double.infinity,
            child: AppRemoteImage(imageUrl: url, semanticLabel: promotion.title),
          ),
        ),
        const SizedBox(height: 16),
      ],
      Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F3FF),
              borderRadius: BorderRadius.circular(6),
            ),
            // Parayı kim ödedi sorusunun cevabı. Platformun kendi kartına
            // "sponsorlu" demek, olmayan bir reklam ilişkisi uydurmak olur.
            child: Text(
              promotion.official ? 'TURKSQUARE' : 'SPONSORLU',
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            promotion.audienceLabel,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Text(
        promotion.title,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
      ),
      if (promotion.subtitle case final subtitle?) ...[
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            color: AppColors.textSecondary,
            height: 1.35,
          ),
        ),
      ],
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kapat'),
        ),
      ),
    ],
  );
}
