import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/telemetry/crash_reporter.dart';
import '../../../core/telemetry/telemetry_client.dart';
import '../../../core/utils/uuid.dart';
import '../data/support_repository.dart';
import '../domain/support_request.dart';

/// Destek ekranının denetleyicisi.
///
/// Hata metinleri burada üretiliyor ve hepsi aynı kurala uyuyor: liste
/// alınamadıysa ekran "talebiniz yok" demiyor, "liste alınamadı" diyor. Açılmış
/// bir talebi görünmez kılmak, üyeye kaybolmuş sanmasını öğretir.
class SupportController extends ChangeNotifier {
  SupportController({required SupportRepository repository})
    : _repository = repository;

  final SupportRepository _repository;

  List<SupportRequest> requests = const [];
  bool isLoading = false;
  bool isSending = false;

  /// Liste okunamadığında dolu. Boş listeyle karıştırılmaması için ekran önce
  /// buna bakıyor.
  String? listError;

  /// Form gönderilirken oluşan hata.
  String? formError;

  /// Açık talep sınırına takıldığında ayrı tutuluyor: bu bir arıza değil, bir
  /// kural — ve ekranın söylediği cümle de farklı olmalı.
  bool tooManyOpen = false;

  /// Açık yazışma ve onun kendi hatası. Liste durup dururken silinmesin diye
  /// ayrı alanlarda.
  SupportRequest? openThread;
  bool isThreadLoading = false;
  String? threadError;

  AppBuildInfo? _build;

  Future<void> load() async {
    isLoading = true;
    notifyListeners();
    try {
      requests = await _repository.list();
      listError = null;
    } on ApiException catch (error) {
      listError = error.message;
    } catch (_) {
      listError = 'Destek talepleri alınamadı.';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> openRequest(String id) async {
    isThreadLoading = true;
    threadError = null;
    openThread = null;
    notifyListeners();
    try {
      openThread = await _repository.thread(id);
    } on ApiException catch (error) {
      threadError = error.message;
    } catch (_) {
      threadError = 'Yazışma açılamadı.';
    } finally {
      isThreadLoading = false;
      notifyListeners();
    }
  }

  void closeThread() {
    openThread = null;
    threadError = null;
    notifyListeners();
  }

  /// Talebi gönderir. Sürüm ve platform bilgisi formdan değil cihazdan
  /// geliyor: "hangi sürümü kullanıyorsunuz" sorusunu üyeye sormak, cevabı
  /// zaten elimizde olan bir şeyi sormaktır.
  Future<bool> submit({
    required SupportTopic topic,
    required String subject,
    required String body,
  }) async {
    isSending = true;
    formError = null;
    tooManyOpen = false;
    notifyListeners();
    try {
      final build = _build ??= await _buildInfo();
      await _repository.create(
        SupportRequestDraft(
          topic: topic,
          subject: subject,
          body: body,
          clientToken: generateUuidV4(),
          appVersion: build?.appVersion,
          // Sunucu yalnızca android/ios/web kabul ediyor; masaüstü ya da
          // bilinmeyen bir platformu uydurmak yerine boş bırakıyoruz.
          platform: switch (build?.platform) {
            'android' => 'android',
            'ios' => 'ios',
            'web' => 'web',
            _ => null,
          },
        ),
      );
      await load();
      return true;
    } on ApiException catch (error) {
      tooManyOpen = error.code == 'SUPPORT_TOO_MANY_OPEN';
      formError = tooManyOpen
          ? 'Aynı anda en fazla beş açık talebin olabilir. Yeni bir tane açmak için önce açık olanlardan biri kapansın; acele bir durum varsa mevcut talebin altına yaz.'
          : error.message;
      return false;
    } catch (_) {
      formError = 'Talep gönderilemedi. Bağlantını kontrol edip tekrar dene.';
      return false;
    } finally {
      isSending = false;
      notifyListeners();
    }
  }

  /// Açık bir talebe ek yazar. Başarılıysa yazışmayı ve listeyi tazeler:
  /// gönderilen mesajı ekranda göstermeyen bir kutu, gitmediği izlenimi verir.
  Future<bool> reply(String id, String body) async {
    isSending = true;
    threadError = null;
    notifyListeners();
    try {
      await _repository.reply(id, body);
      openThread = await _repository.thread(id);
      await load();
      return true;
    } on ApiException catch (error) {
      threadError = error.statusCode == 409
          ? 'Bu talep kapandı, altına yazılamıyor. Konu sürüyorsa yeni bir talep aç.'
          : error.message;
      return false;
    } catch (_) {
      threadError = 'Mesaj gönderilemedi.';
      return false;
    } finally {
      isSending = false;
      notifyListeners();
    }
  }

  Future<AppBuildInfo?> _buildInfo() async {
    try {
      return await discoverBuildInfo();
    } catch (_) {
      // Sürüm okunamadıysa talep yine de açılmalı; eksik olan tek şey destek
      // ekibinin işini kolaylaştıracak bir satır.
      return null;
    }
  }
}
