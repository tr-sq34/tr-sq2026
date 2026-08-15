import 'package:america_hub/core/telemetry/crash_reporter.dart';
import 'package:america_hub/core/telemetry/screen_observer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Çökme raporlayıcının sınandığı şey, gönderdiği veri değil davranışı: ne
/// zaman susması gerektiği ve hiçbir koşulda hata fırlatmaması.
void main() {
  late List<({String path, Map<String, dynamic> body})> sent;

  CrashReporter build({int cap = 8, bool failing = false}) {
    sent = [];
    return CrashReporter(
      maxReportsPerSession: cap,
      send: (path, body) async {
        sent.add((path: path, body: body));
        if (failing) throw StateError('ağ yok');
      },
    );
  }

  const info = AppBuildInfo(
    platform: 'android',
    appVersion: '1.0.0+1',
    osVersion: 'Android 14',
    deviceModel: 'Pixel 7',
  );

  test('açılış bildirimi oturum kimliği ve sürümle gidiyor', () async {
    final reporter = build();
    await reporter.start(info);

    expect(sent.single.path, 'app/launches');
    expect(sent.single.body['sessionId'], reporter.sessionId);
    expect(sent.single.body['platform'], 'android');
    expect(sent.single.body['appVersion'], '1.0.0+1');
    // Kimlik, sürüm 4 UUID biçiminde olmalı: sunucu sütunu UUID.
    expect(
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
          .hasMatch(reporter.sessionId),
      isTrue,
    );
  });

  test('başlamadan gelen hata gönderilmiyor', () {
    final reporter = build();
    reporter.recordError(StateError('erken'), StackTrace.current);
    expect(sent, isEmpty);
  });

  test('aynı hata tekrar tekrar gönderilmiyor', () async {
    final reporter = build();
    await reporter.start(info);
    sent.clear();

    for (var i = 0; i < 50; i++) {
      reporter.recordError(StateError('aynı hata'), StackTrace.current);
    }

    expect(sent, hasLength(1));
  });

  test('oturum başına rapor sayısı sınırlı', () async {
    final reporter = build(cap: 3);
    await reporter.start(info);
    sent.clear();

    for (var i = 0; i < 20; i++) {
      reporter.recordError(StateError('hata $i'), StackTrace.current);
    }

    expect(sent, hasLength(3));
  });

  test('gönderim başarısız olursa hata dışarı sızmıyor', () async {
    final reporter = build(failing: true);
    await reporter.start(info);
    // Beklemesi olmayan bir gönderim de patlamamalı; testin kendisi bunu
    // yakalar çünkü fırlatılan hata bu bölgeye düşerdi.
    reporter.recordError(StateError('yine'), StackTrace.current);
    await Future<void>.delayed(Duration.zero);
    expect(sent, hasLength(2));
  });

  test('çizim hatası ölümcül sayılmıyor, çalışma zamanı hatası sayılıyor', () async {
    final reporter = build();
    await reporter.start(info);
    sent.clear();

    reporter.recordFlutterError(
      FlutterErrorDetails(
        exception: StateError('çizim'),
        stack: StackTrace.current,
        context: ErrorDescription('while building Feed'),
      ),
    );
    reporter.recordError(ArgumentError('asenkron'), StackTrace.current);

    expect(sent[0].body['fatal'], isFalse);
    expect(sent[0].body['screen'], contains('Feed'));
    expect(sent[1].body['fatal'], isTrue);
  });

  test('gezinti gözlemcisi son adlı ekranı tutuyor', () async {
    final reporter = build();
    await reporter.start(info);
    final observer = CrashScreenObserver(reporter);

    Route<void> named(String? name) =>
        PageRouteBuilder(settings: RouteSettings(name: name), pageBuilder: (_, _, _) => const SizedBox());

    observer.didPush(named('/home'), null);
    observer.didPush(named('/news'), named('/home'));
    // Diyalog adsız itiliyor; arkadaki ekranın adı korunmalı.
    observer.didPush(named(null), named('/news'));
    expect(reporter.currentScreen, '/news');

    observer.didPop(named(null), named('/news'));
    expect(reporter.currentScreen, '/news');

    sent.clear();
    reporter.recordError(StateError('haberlerde'), StackTrace.current);
    expect(sent.single.body['screen'], '/news');
  });
}
