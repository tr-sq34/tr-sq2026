import 'package:america_hub/features/safety/data/sos_location_source.dart';
import 'package:america_hub/features/safety/data/sos_repository.dart';
import 'package:america_hub/features/safety/domain/sos_alert.dart';

/// Bellekte duran bir SOS deposu. Tek açık çağrı kuralını sunucudaki gibi
/// uyguluyor: aynı çağrıyı iki kez göndermek ikinci bir kart açmıyor.
class FakeSosRepository implements SosRepository {
  SosAlert? current;
  final List<SosDraft> sent = [];
  bool failOnTrigger = false;

  @override
  Future<SosAlert?> active() async => current;

  @override
  Future<void> trigger(SosDraft draft) async {
    if (failOnTrigger) throw StateError('offline');
    sent.add(draft);
    current = SosAlert(
      id: current?.id ?? 'alert-1',
      kind: draft.kind.wire,
      status: SosStatus.active,
      note: draft.note,
      locationNote: draft.locationNote,
      locationShared: draft.point != null || (current?.locationShared ?? false),
      createdAt: current?.createdAt ?? DateTime.now(),
      acknowledgedAt: null,
      activeLocationWatchers: 0,
    );
  }

  @override
  Future<void> cancel(String id) async {
    if (current?.id == id) current = null;
  }
}

class FakeSosLocationSource implements SosLocationSource {
  FakeSosLocationSource(this.result);

  SosLocationResult result;
  int calls = 0;

  @override
  Future<SosLocationResult> take() async {
    calls++;
    return result;
  }
}
