import 'package:flutter/widgets.dart';

import 'crash_reporter.dart';

/// "Nerede çöktü?" sorusunun cevabı.
///
/// Yığın izi hangi sınıfın hata verdiğini söylüyor ama üyenin o sırada hangi
/// ekranda olduğunu söylemiyor; ikisi çoğu zaman aynı şey değil. Uygulama adlı
/// rotalar kullandığı için bunu toplamak tek satır: rota değiştikçe adı
/// denetleyiciye yazılıyor.
///
/// Sayfa dışındaki katmanlar (diyalog, alt sayfa) adsız itiliyor; adı boş olan
/// rota son bilinen ekranı silmiyor, çünkü diyalog açan ekran hâlâ arkada
/// duruyor ve rapora yazılması gereken o.
class CrashScreenObserver extends NavigatorObserver {
  CrashScreenObserver(this.reporter);

  final CrashReporter reporter;

  void _note(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name != null && name.isNotEmpty) reporter.currentScreen = name;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _note(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _note(previousRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _note(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _note(newRoute);
}
