import 'package:flutter/material.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../auth/data/datasources/device_location_source.dart';
import '../../../auth/data/datasources/us_places_local_datasource.dart';
import '../../../auth/domain/entities/onboarding_draft.dart';
import '../../../auth/domain/entities/onboarding_profile.dart';
import '../../../auth/presentation/widgets/onboarding/aurora_background.dart';
import '../../../auth/presentation/widgets/onboarding/aurora_surfaces.dart';
import '../../../auth/presentation/widgets/onboarding/location_step.dart';

/// Yaşanan şehri sonradan değiştirme ekranı.
///
/// "Haritaya İğne Koy" görevi bir ekran adı söylüyordu ama o ekran yoktu:
/// konum yalnızca kayıt sırasında bir kez soruluyordu. Burası aynı adımı —
/// aynı arama kutusu, aynı GPS düğmesi — kayıttan sonra da açıyor.
///
/// Sunucu konumu tek başına güncellemiyor; `PUT /v1/auth/onboarding` bütün
/// tercihleri birlikte istiyor. O yüzden ekran önce kayıtlı cevapları okuyor,
/// yalnızca konumu değiştirip geri kalanını olduğu gibi geri gönderiyor.
class LocationEditScreen extends StatefulWidget {
  LocationEditScreen({
    super.key,
    required this.authController,
    this.onSaved,
    UsPlacesLocalDataSource? places,
    DeviceLocationSource? locationSource,
    this.searchDebounce = const Duration(milliseconds: 180),
  }) : places = places ?? UsPlacesLocalDataSource(),
       locationSource =
           locationSource ??
           GeolocatorDeviceLocationSource(
             places: places ?? UsPlacesLocalDataSource(),
           );

  final AuthController authController;

  /// Kayıt sunucuya gittikten sonra çağrılıyor: profil sekmesi şehri kendi
  /// deposundan okuduğu için oradaki kopyanın tazelenmesi gerekiyor.
  final Future<void> Function()? onSaved;

  final UsPlacesLocalDataSource places;
  final DeviceLocationSource locationSource;
  final Duration searchDebounce;

  @override
  State<LocationEditScreen> createState() => _LocationEditScreenState();
}

class _LocationEditScreenState extends State<LocationEditScreen> {
  OnboardingProfile? _saved;
  LocationSelection? _selection;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final profile = await widget.authController.getOnboarding();
      if (!mounted) return;
      final city = profile.city?.trim() ?? '';
      setState(() {
        _saved = profile;
        _selection = city.isEmpty
            ? null
            : LocationSelection(
                city: city,
                countryCode: profile.countryCode ?? 'US',
                regionCode: profile.regionCode,
              );
        _loading = false;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _fail(error.message));
    } catch (_) {
      if (mounted) {
        setState(
          () => _fail('Kayıtlı tercihlerin okunamadı. Bağlantını kontrol et.'),
        );
      }
    }
  }

  /// Okuma başarısızsa boş bir form açılmıyor: kaydetmek, okunamayan
  /// tercihlerin üzerine yazmak demek olurdu.
  void _fail(String message) {
    _loading = false;
    _loadError = message;
  }

  bool get _canSave {
    final selection = _selection;
    if (selection == null || _saving) return false;
    return selection.city.trim().length >= 2 &&
        (!selection.isUnitedStates || (selection.regionCode?.length ?? 0) == 2);
  }

  Future<void> _save() async {
    final saved = _saved;
    final selection = _selection;
    if (saved == null || selection == null) return;
    final intent = saved.primaryIntent;
    if (saved.interests.isEmpty || intent == null) {
      // Sunucu konumu ilgi alanlarından ayrı kabul etmiyor; ikisi eksikken
      // gönderilen istek reddedilir. Nedenini burada söylemek, sunucudan
      // dönen doğrulama hatasını beklemekten dürüst.
      setState(() {
        _saveError =
            'Kayıt sırasındaki ilgi alanların bulunamadı. Konumu tek başına '
            'güncelleyemiyoruz; destek ekibine yazman gerekiyor.';
      });
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.authController.saveOnboarding(
        OnboardingDraft(
          city: selection.city,
          countryCode: selection.countryCode,
          regionCode: selection.regionCode,
          interests: saved.interests,
          primaryIntent: intent,
          bornInUs: saved.bornInUs,
          arrivedMonth: saved.arrivedMonth,
          arrivedYear: saved.arrivedYear,
          originCountry: saved.originCountry,
          originCity: saved.originCity,
        ),
      );
      await widget.onSaved?.call();
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Konumun ${selection.label} olarak kaydedildi.')),
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _saveError = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _saveError = 'Konum kaydedilemedi. İstek sunucuya ulaşmadı.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF12102A),
    body: AuroraBackground(
      palette: AuroraPalette.location,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  ),
                  Expanded(
                    child: Text('Konumunu değiştir', style: AuroraText.body(size: 16)),
                  ),
                ],
              ),
            ),
            Expanded(child: _body()),
            if (!_loading && _loadError == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
                child: Column(
                  children: [
                    if (_saveError != null) ...[
                      Text(
                        _saveError!,
                        textAlign: TextAlign.center,
                        style: AuroraText.body(size: 13, weight: FontWeight.w500, alpha: .85),
                      ),
                      const SizedBox(height: 12),
                    ],
                    AppButton(
                      label: 'Kaydet',
                      variant: AppButtonVariant.onDark,
                      isLoading: _saving,
                      onPressed: _canSave ? _save : null,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    final error = _loadError;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error,
                textAlign: TextAlign.center,
                style: AuroraText.body(size: 14, weight: FontWeight.w500, alpha: .85),
              ),
              const SizedBox(height: 16),
              AppButton(
                label: 'Tekrar dene',
                variant: AppButtonVariant.onDark,
                onPressed: _load,
              ),
            ],
          ),
        ),
      );
    }
    return LocationStep(
      places: widget.places,
      locationSource: widget.locationSource,
      selection: _selection,
      searchDebounce: widget.searchDebounce,
      onSelected: (value, {required bool confirmed}) {
        setState(() {
          _selection = value;
          _saveError = null;
        });
      },
    );
  }
}
