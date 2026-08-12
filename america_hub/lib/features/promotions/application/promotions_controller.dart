import 'package:flutter/foundation.dart';

import '../../../core/state/async_state.dart';
import '../domain/entities/promotion.dart';
import '../domain/repositories/promotion_repository.dart';

/// Ana sayfadaki sponsorlu alanlar ile üyenin kendi talepleri tek denetleyicide:
/// ikisi de aynı kaydın iki görünümü, ve talep onaylandığında ana sayfada
/// göründüğünü aynı yerden görebilmek gerekiyor.
class PromotionsController extends ChangeNotifier {
  PromotionsController({required PromotionRepository repository})
    : _repository = repository;

  final PromotionRepository _repository;

  AsyncState<List<Promotion>> _active = const AsyncLoading();
  AsyncState<List<Promotion>> get active => _active;

  AsyncState<List<Promotion>> _mine = const AsyncLoading();
  AsyncState<List<Promotion>> get mine => _mine;

  /// Aynı kartın her kaydırmada yeniden sayılmaması için: bir tanıtım oturum
  /// başına bir kez gösterim sayılır. Aksi hâlde sayaç, ekranı aşağı yukarı
  /// kaydıran tek bir üyeyle şişerdi.
  final Set<String> _countedImpressions = {};

  List<Promotion> get _liveActive {
    if (_active case AsyncData<List<Promotion>>(:final value)) {
      final now = DateTime.now();
      return value
          .where((promotion) => promotion.isLiveAt(now))
          .toList(growable: false);
    }
    return const [];
  }

  /// Story şeridinin başındaki sponsorlu yuvalar.
  List<Promotion> get storySlots => _byPlacement(PromotionPlacement.storySlot);

  /// "Sana Özel Öne Çıkanlar" kartları.
  List<Promotion> get featuredCards =>
      _byPlacement(PromotionPlacement.featuredCard);

  List<Promotion> get banners => _byPlacement(PromotionPlacement.appBanner);

  List<Promotion> _byPlacement(PromotionPlacement placement) => _liveActive
      .where((promotion) => promotion.placement == placement)
      .toList(growable: false);

  Future<void> loadActive() async {
    _active = const AsyncLoading();
    notifyListeners();
    try {
      _active = AsyncData(await _repository.fetchActive());
    } catch (_) {
      // Sponsorlu alan boş kalır; ana sayfanın geri kalanı çalışmaya devam
      // eder, çünkü tanıtım ekranın içeriği değil süsü.
      _active = const AsyncFailure('Tanıtımlar yüklenemedi.');
    }
    notifyListeners();
  }

  Future<void> loadMine() async {
    _mine = const AsyncLoading();
    notifyListeners();
    try {
      _mine = AsyncData(await _repository.fetchMine());
    } catch (_) {
      _mine = const AsyncFailure('Tanıtım taleplerin yüklenemedi.');
    }
    notifyListeners();
  }

  /// Talebi gönderir ve listeyi tazeler. Hata yukarı taşınır: gönderemediğini
  /// bilmeyen üye talebinin sırada olduğunu sanır.
  Future<void> submit(PromotionRequestDraft draft) async {
    await _repository.submit(draft);
    await loadMine();
  }

  void recordImpression(String promotionId) {
    if (!_countedImpressions.add(promotionId)) return;
    _repository.recordEvent(promotionId, PromotionEventKind.impression).ignore();
  }

  void recordClick(String promotionId) =>
      _repository.recordEvent(promotionId, PromotionEventKind.click).ignore();
}
