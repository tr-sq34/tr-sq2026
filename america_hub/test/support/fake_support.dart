import 'package:america_hub/core/network/api_exception.dart';
import 'package:america_hub/features/support/data/support_repository.dart';
import 'package:america_hub/features/support/domain/support_request.dart';

/// Bellekte duran bir destek deposu.
///
/// Sunucudaki iki kuralı da uyguluyor, çünkü ekranın davranışı bu iki kurala
/// göre değişiyor: aynı `clientToken` ikinci bir talep açmıyor ve kapanmış bir
/// talebin altına yazılamıyor.
class FakeSupportRepository implements SupportRepository {
  final List<SupportRequest> items = [];
  final List<SupportRequestDraft> sent = [];
  final Set<String> _tokens = {};

  /// Doluysa liste okuması bu hatayla düşüyor — "talebin yok" ile "liste
  /// alınamadı" arasındaki farkı sınamak için.
  Object? listFailure;

  @override
  Future<List<SupportRequest>> list() async {
    if (listFailure case final Object failure) throw failure;
    return List.unmodifiable(items);
  }

  @override
  Future<SupportRequest> thread(String id) async =>
      items.firstWhere((item) => item.id == id);

  @override
  Future<String> create(SupportRequestDraft draft) async {
    sent.add(draft);
    if (!_tokens.add(draft.clientToken)) return items.first.id;
    final now = DateTime.now();
    final request = SupportRequest(
      id: 'talep-${items.length + 1}',
      topic: draft.topic,
      subject: draft.subject,
      status: SupportStatus.open,
      createdAt: now,
      updatedAt: now,
      lastStaffAt: null,
      closureReason: null,
      messages: [
        SupportMessage(
          id: 'm-${items.length + 1}',
          fromStaff: false,
          body: draft.body,
          createdAt: now,
        ),
      ],
    );
    items.insert(0, request);
    return request.id;
  }

  @override
  Future<void> reply(String id, String body) async {
    final index = items.indexWhere((item) => item.id == id);
    final request = items[index];
    if (request.status == SupportStatus.closed) {
      // Sunucunun döndürdüğü kodun aynısı; ekran 409'a bakarak farklı bir
      // cümle kuruyor.
      throw const ApiException(
        message: 'Request is closed.',
        statusCode: 409,
        code: 'SUPPORT_REQUEST_CLOSED',
      );
    }
    items[index] = SupportRequest(
      id: request.id,
      topic: request.topic,
      subject: request.subject,
      status: SupportStatus.open,
      createdAt: request.createdAt,
      updatedAt: DateTime.now(),
      lastStaffAt: request.lastStaffAt,
      closureReason: request.closureReason,
      messages: [
        ...request.messages,
        SupportMessage(
          id: 'm-${request.messages.length + 1}',
          fromStaff: false,
          body: body,
          createdAt: DateTime.now(),
        ),
      ],
    );
  }

  /// Panelden yazılmış bir cevabı taklit eder.
  void answer(String id, String body, {bool close = false}) {
    final index = items.indexWhere((item) => item.id == id);
    final request = items[index];
    final now = DateTime.now();
    items[index] = SupportRequest(
      id: request.id,
      topic: request.topic,
      subject: request.subject,
      status: close ? SupportStatus.closed : SupportStatus.answered,
      createdAt: request.createdAt,
      updatedAt: now,
      lastStaffAt: now,
      closureReason: request.closureReason,
      messages: [
        ...request.messages,
        SupportMessage(
          id: 'm-${request.messages.length + 1}',
          fromStaff: true,
          body: body,
          createdAt: now,
        ),
      ],
    );
  }
}
