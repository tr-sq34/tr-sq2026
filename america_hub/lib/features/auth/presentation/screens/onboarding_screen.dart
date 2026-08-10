import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/widgets/app_button.dart';
import '../../data/datasources/device_location_source.dart';
import '../../data/datasources/us_places_local_datasource.dart';
import '../../domain/entities/onboarding_draft.dart';
import '../../domain/entities/onboarding_persona.dart';
import '../widgets/onboarding/arrival_step.dart';
import '../widgets/onboarding/aurora_background.dart';
import '../widgets/onboarding/aurora_surfaces.dart';
import '../widgets/onboarding/location_step.dart';
import '../widgets/onboarding/onboarding_progress.dart';
import '../widgets/onboarding/persona_step.dart';

enum _OnboardingStep { location, arrival, persona }

/// One-time setup a member walks through right after signing up.
///
/// Each step advances on its own once it holds a definite answer, so the flow
/// feels like a conversation rather than a form: pick a city and the arrival
/// question slides in by itself.
class OnboardingScreen extends StatefulWidget {
  OnboardingScreen({
    super.key,
    required this.onComplete,
    UsPlacesLocalDataSource? places,
    DeviceLocationSource? locationSource,
    this.now,
    this.searchDebounce = const Duration(milliseconds: 180),
  }) : places = places ?? UsPlacesLocalDataSource(),
       locationSource = locationSource ??
           GeolocatorDeviceLocationSource(
             places: places ?? UsPlacesLocalDataSource(),
           );

  final Future<void> Function(OnboardingDraft draft) onComplete;

  /// Injected in tests; both default to the real device-backed implementations.
  final UsPlacesLocalDataSource places;
  final DeviceLocationSource locationSource;

  /// Fixes the newest selectable arrival year. Tests pass a constant so the
  /// year list does not drift with the clock.
  final DateTime? now;

  /// Passed to the city search box; tests set it to zero.
  final Duration searchDebounce;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  Timer? _advanceTimer;

  int _index = 0;
  LocationSelection? _location;
  ArrivalAnswer _arrival = const ArrivalAnswer();
  final List<String> _personas = [];
  bool _submitting = false;
  String? _error;

  /// The arrival question only makes sense for someone living in the US, which
  /// is exactly the condition the member set on the previous step.
  List<_OnboardingStep> get _steps => [
    _OnboardingStep.location,
    if (_location?.isUnitedStates ?? true) _OnboardingStep.arrival,
    _OnboardingStep.persona,
  ];

  _OnboardingStep get _current => _steps[_index.clamp(0, _steps.length - 1)];

  @override
  void dispose() {
    _advanceTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    _advanceTimer?.cancel();
    if (index < 0 || index >= _steps.length) return;
    setState(() {
      _index = index;
      _error = null;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  /// A short pause before moving on: the member sees their choice land, and the
  /// haptic tick makes the jump feel deliberate rather than like a glitch.
  void _autoAdvanceFrom(int index) {
    _advanceTimer?.cancel();
    _advanceTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted || _index != index) return;
      HapticFeedback.selectionClick();
      _goTo(index + 1);
    });
  }

  void _onLocationSelected(LocationSelection? value, {required bool confirmed}) {
    setState(() {
      _location = value;
      _error = null;
    });
    if (confirmed && value != null) _autoAdvanceFrom(_index);
  }

  void _onArrivalChanged(ArrivalAnswer value, {required bool confirmed}) {
    setState(() => _arrival = value);
    if (confirmed) _autoAdvanceFrom(_index);
  }

  void _onPersonaToggled(String id) {
    _advanceTimer?.cancel();
    setState(() {
      _error = null;
      if (_personas.remove(id)) return;
      if (_personas.length < kMaxPersonaSelection) _personas.add(id);
    });
  }

  bool get _canContinue => switch (_current) {
    _OnboardingStep.location => _location != null,
    _OnboardingStep.arrival => true,
    _OnboardingStep.persona => _personas.isNotEmpty,
  };

  Future<void> _onPrimaryAction() async {
    if (_current != _OnboardingStep.persona) {
      _goTo(_index + 1);
      return;
    }
    await _submit();
  }

  Future<void> _submit() async {
    final location = _location;
    if (location == null || _personas.isEmpty) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      // Someone born here has no arrival date and no country of origin; the
      // server drops them too, but sending a contradiction is worse than not.
      final arrival = location.isUnitedStates ? _arrival : const ArrivalAnswer();
      final originCity = arrival.originCity?.trim();
      await widget.onComplete(
        OnboardingDraft(
          city: location.city,
          countryCode: location.countryCode,
          regionCode: location.regionCode,
          interests: List.of(_personas),
          primaryIntent: primaryIntentFor(_personas),
          bornInUs: arrival.bornInUs,
          arrivedMonth: arrival.bornInUs ? null : arrival.month,
          arrivedYear: arrival.bornInUs ? null : arrival.year,
          originCountry: arrival.bornInUs ? null : arrival.originCountry,
          originCity: arrival.bornInUs || originCity == null || originCity.length < 2
              ? null
              : originCity,
        ),
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Bir şeyler ters gitti. Lütfen tekrar dene.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _buildStep(_OnboardingStep step) => switch (step) {
    _OnboardingStep.location => LocationStep(
      places: widget.places,
      locationSource: widget.locationSource,
      selection: _location,
      onSelected: _onLocationSelected,
      searchDebounce: widget.searchDebounce,
    ),
    _OnboardingStep.arrival => ArrivalStep(
      answer: _arrival,
      onChanged: _onArrivalChanged,
      currentYear: (widget.now ?? DateTime.now()).year,
    ),
    _OnboardingStep.persona => PersonaStep(
      selected: _personas,
      onToggled: _onPersonaToggled,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    final step = _current;
    final palette = switch (step) {
      _OnboardingStep.location => AuroraPalette.location,
      _OnboardingStep.arrival => AuroraPalette.arrival,
      _OnboardingStep.persona => AuroraPalette.personas,
    };

    return Scaffold(
      backgroundColor: const Color(0xFF12102A),
      body: AuroraBackground(
        palette: palette,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: _index == 0
                          ? null
                          : IconButton(
                              onPressed: () => _goTo(_index - 1),
                              icon: const Icon(Icons.arrow_back_rounded),
                              color: Colors.white,
                              tooltip: 'Geri',
                            ),
                    ),
                    Expanded(
                      child: OnboardingProgress(
                        stepCount: steps.length,
                        currentStep: _index,
                      ),
                    ),
                    SizedBox(
                      width: 62,
                      child: step == _OnboardingStep.arrival
                          // Only the arrival question is optional, so this is
                          // the only step that offers a way past it.
                          ? TextButton(
                              onPressed: () {
                                setState(() => _arrival = const ArrivalAnswer());
                                _goTo(_index + 1);
                              },
                              child: Text(
                                'Atla',
                                style: AuroraText.body(size: 14, weight: FontWeight.w600, alpha: .8),
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [for (final each in steps) _buildStep(each)],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
                child: Column(
                  children: [
                    if (_error != null) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline_rounded, size: 18, color: Color(0xFFFF9A9A)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: AuroraText.body(size: 13, weight: FontWeight.w600)
                                  .copyWith(color: const Color(0xFFFF9A9A)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: AppButton(
                        label: step == _OnboardingStep.persona ? 'TurkSquare’e gir' : 'Devam',
                        variant: AppButtonVariant.onDark,
                        isLoading: _submitting,
                        onPressed: _canContinue ? _onPrimaryAction : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
