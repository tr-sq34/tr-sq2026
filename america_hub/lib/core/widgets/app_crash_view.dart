import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Bir parça çizilemediğinde üyenin gördüğü şey.
///
/// Flutter'ın varsayılanı, hata ayıklama derlemesinde sarı çizgili kırmızı bir
/// kutu, yayın derlemesinde ise gri bir boşluk. İkisi de üyeye hiçbir şey
/// anlatmıyor; grisi ise projedeki "başarısız istek boş ekran gibi görünmesin"
/// kuralının tam olarak yasakladığı şey — bir şeyin çalışmadığını söylemeden
/// yok olmak.
///
/// Bu widget hiçbir üst katmana güvenmiyor: Material, Directionality ya da
/// tema olmadan da çizilebiliyor, çünkü hata tam da bunları kuran ağacın
/// içinde olmuş olabilir.
class AppCrashView extends StatelessWidget {
  const AppCrashView({super.key, this.detail});

  /// Hata ayıklama derlemesinde gösterilecek teknik ayrıntı. Yayın
  /// derlemesinde üyeye gösterilmiyor: rapor zaten panele gidiyor.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final showDetail = kDebugMode && detail != null;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: AppColors.background,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.report_gmailerrorred_rounded, color: AppColors.primaryLight, size: 40),
                const SizedBox(height: 12),
                const Text(
                  'Bu bölüm açılamadı',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Sorun bize bildirildi. Geri dönüp tekrar deneyebilirsin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                    decoration: TextDecoration.none,
                  ),
                ),
                if (showDetail) ...[
                  const SizedBox(height: 10),
                  Text(
                    detail!,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
