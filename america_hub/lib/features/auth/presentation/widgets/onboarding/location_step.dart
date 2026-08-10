import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/datasources/device_location_source.dart';
import '../../../data/datasources/us_places_local_datasource.dart';
import '../../../domain/entities/country_option.dart';
import '../../../domain/entities/us_place.dart';
import 'aurora_surfaces.dart';
import 'onboarding_step_scaffold.dart';

/// What the location step produces. `regionCode` is a US state and is present
/// exactly when `countryCode` is `US`.
class LocationSelection {
  const LocationSelection({
    required this.city,
    required this.countryCode,
    this.regionCode,
  });

  final String city;
  final String countryCode;
  final String? regionCode;

  bool get isUnitedStates => countryCode == 'US';

  String get label => isUnitedStates && regionCode != null
      ? '$city, $regionCode'
      : city;
}

class LocationStep extends StatefulWidget {
  const LocationStep({
    super.key,
    required this.places,
    required this.locationSource,
    required this.selection,
    required this.onSelected,
    this.searchDebounce = const Duration(milliseconds: 180),
  });

  final UsPlacesLocalDataSource places;
  final DeviceLocationSource locationSource;
  final LocationSelection? selection;

  /// How long typing has to settle before the index is searched. Zero searches
  /// on every keystroke, which is what tests use to keep the flow synchronous.
  final Duration searchDebounce;

  /// [confirmed] is true for a deliberate pick (GPS hit, tapped suggestion),
  /// which is what the shell auto-advances on. Free typing reports false.
  final void Function(LocationSelection? value, {required bool confirmed})
  onSelected;

  @override
  State<LocationStep> createState() => _LocationStepState();
}

class _LocationStepState extends State<LocationStep> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<UsPlace> _suggestions = const [];
  bool _locating = false;
  String? _notice;
  bool _abroad = false;
  CountryOption? _abroadCountry;

  @override
  void initState() {
    super.initState();
    // Parsing the index takes a moment; if it lands while the member is
    // already typing, redo their query so the list is not silently empty.
    widget.places.ensureLoaded().then((_) {
      if (mounted && _query.text.isNotEmpty) _search(_query.text, immediate: true);
    });
    final selection = widget.selection;
    if (selection != null) {
      _query.text = selection.isUnitedStates ? selection.label : selection.city;
      _abroad = !selection.isUnitedStates;
      _abroadCountry = countryByCode(selection.countryCode);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _useDeviceLocation() async {
    setState(() {
      _locating = true;
      _notice = null;
    });
    DeviceLocationResult result;
    try {
      result = await widget.locationSource.resolve();
    } catch (_) {
      result = const DeviceLocationResult(DeviceLocationStatus.unresolved);
    }
    if (!mounted) return;

    if (!result.isUsable) {
      setState(() {
        _locating = false;
        _notice = switch (result.status) {
          DeviceLocationStatus.serviceDisabled =>
            'Konum servisi kapalı. Açabilir ya da şehrini aşağıdan seçebilirsin.',
          DeviceLocationStatus.permissionDenied =>
            'Konum izni verilmedi. Şehrini aşağıdan aratabilirsin.',
          _ => 'Konumunu çözemedik. Şehrini aşağıdan aratabilirsin.',
        };
      });
      return;
    }

    final country = (result.countryCode ?? 'US').toUpperCase();
    if (country == 'US' && result.stateCode == null) {
      // We know the city but not which state it belongs to; asking is better
      // than guessing at a value the community ranking depends on.
      setState(() {
        _locating = false;
        _query.text = result.city!;
        _notice = 'Şehrini bulduk ama eyaleti doğrulayamadık. Listeden seç.';
      });
      _search(result.city!, immediate: true);
      return;
    }

    setState(() {
      _locating = false;
      _notice = null;
      _abroad = country != 'US';
      _abroadCountry = country == 'US' ? null : countryByCode(country);
      _suggestions = const [];
      _query.text = country == 'US'
          ? '${result.city}, ${result.stateCode}'
          : result.city!;
    });
    widget.onSelected(
      LocationSelection(
        city: result.city!,
        countryCode: country,
        regionCode: country == 'US' ? result.stateCode : null,
      ),
      confirmed: true,
    );
  }

  void _search(String value, {bool immediate = false}) {
    _debounce?.cancel();
    if (_abroad) {
      // Outside the US there is no offline index to search; the typed value is
      // the answer, paired with the chosen country.
      final country = _abroadCountry;
      widget.onSelected(
        country == null || value.trim().length < 2
            ? null
            : LocationSelection(city: value.trim(), countryCode: country.code),
        confirmed: false,
      );
      setState(() => _suggestions = const []);
      return;
    }
    widget.onSelected(null, confirmed: false);
    void run() {
      if (mounted) {
        setState(() => _suggestions = widget.places.searchLoaded(value));
      }
    }

    if (immediate || widget.searchDebounce == Duration.zero) {
      run();
    } else {
      _debounce = Timer(widget.searchDebounce, run);
    }
  }

  void _pick(UsPlace place) {
    setState(() {
      _suggestions = const [];
      _notice = null;
      _query.text = place.label;
    });
    FocusScope.of(context).unfocus();
    widget.onSelected(
      LocationSelection(
        city: place.city ?? place.state,
        countryCode: 'US',
        regionCode: place.stateCode,
      ),
      confirmed: true,
    );
  }

  Future<void> _pickCountry() async {
    final selected = await showModalBottomSheet<CountryOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1636),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => _CountrySheet(selected: _abroadCountry),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _abroadCountry = selected;
      _suggestions = const [];
    });
    _search(_query.text);
  }

  void _toggleAbroad(bool value) {
    setState(() {
      _abroad = value;
      _abroadCountry = value ? (_abroadCountry ?? kCountryOptions.first) : null;
      _suggestions = const [];
      _notice = null;
      _query.clear();
    });
    widget.onSelected(null, confirmed: false);
  }

  @override
  Widget build(BuildContext context) => OnboardingStepScaffold(
    icon: Icons.location_on_rounded,
    title: 'Sana en yakın\nTurkSquare’i bulalım',
    subtitle:
        'Nerede yaşadığını bilirsek akışını, çarşıyı ve etkinlikleri '
        'çevrendeki Türk topluluğuna göre kurarız.',
    children: [
      if (!_abroad) ...[
        _DeviceLocationButton(loading: _locating, onPressed: _useDeviceLocation),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: Divider(color: Colors.white.withValues(alpha: .16))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('veya', style: AuroraText.body(size: 13, weight: FontWeight.w500, alpha: .5)),
            ),
            Expanded(child: Divider(color: Colors.white.withValues(alpha: .16))),
          ],
        ),
        const SizedBox(height: 14),
      ],
      if (_abroad) ...[
        AuroraCard(
          onTap: _pickCountry,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Text(_abroadCountry?.flag ?? '🌍', style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _abroadCountry?.name ?? 'Ülke seç',
                  style: AuroraText.body(size: 15),
                ),
              ),
              Icon(Icons.expand_more_rounded, color: Colors.white.withValues(alpha: .6)),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
      AuroraTextField(
        controller: _query,
        hintText: _abroad ? 'Şehrini yaz' : 'Şehir veya eyalet ara',
        prefixIcon: Icons.search_rounded,
        onChanged: _search,
      ),
      if (_notice != null) ...[
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 17, color: Colors.white.withValues(alpha: .65)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_notice!, style: AuroraText.body(size: 13, weight: FontWeight.w500, alpha: .72)),
            ),
          ],
        ),
      ],
      if (_suggestions.isNotEmpty) ...[
        const SizedBox(height: 12),
        AuroraCard(
          padding: EdgeInsets.zero,
          borderRadius: 20,
          child: Column(
            children: [
              for (final place in _suggestions)
                ListTile(
                  onTap: () => _pick(place),
                  dense: true,
                  leading: Icon(
                    place.isState ? Icons.map_rounded : Icons.location_city_rounded,
                    color: Colors.white.withValues(alpha: .7),
                    size: 20,
                  ),
                  title: Text(place.label, style: AuroraText.body(size: 15)),
                  subtitle: place.isState
                      ? null
                      : Text(place.state, style: AuroraText.body(size: 12, weight: FontWeight.w400, alpha: .5)),
                ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 18),
      _AbroadToggle(value: _abroad, onChanged: _toggleAbroad),
      const SizedBox(height: 14),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, size: 16, color: Colors.white.withValues(alpha: .5)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Sadece şehir bilgin saklanır; kesin konumun hiçbir zaman kaydedilmez.',
              style: AuroraText.body(size: 12, weight: FontWeight.w500, alpha: .55),
            ),
          ),
        ],
      ),
    ],
  );
}

class _DeviceLocationButton extends StatelessWidget {
  const _DeviceLocationButton({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => AuroraCard(
    onTap: loading ? null : onPressed,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    child: Row(
      children: [
        SizedBox(
          height: 22,
          width: 22,
          child: loading
              ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
              : const Icon(Icons.my_location_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            loading ? 'Konumun alınıyor…' : 'Konumumu kullan',
            style: AuroraText.body(size: 15, weight: FontWeight.w700),
          ),
        ),
        if (!loading)
          Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: .55)),
      ],
    ),
  );
}

class _AbroadToggle extends StatelessWidget {
  const _AbroadToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => AuroraCard(
    onTap: () => onChanged(!value),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(
      children: [
        Icon(Icons.public_rounded, size: 20, color: Colors.white.withValues(alpha: .75)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Şu an ABD dışındayım',
            style: AuroraText.body(size: 14, weight: FontWeight.w600),
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Colors.white,
          activeTrackColor: Colors.white.withValues(alpha: .40),
          inactiveThumbColor: Colors.white.withValues(alpha: .75),
          inactiveTrackColor: Colors.white.withValues(alpha: .14),
        ),
      ],
    ),
  );
}

class _CountrySheet extends StatelessWidget {
  const _CountrySheet({required this.selected});

  final CountryOption? selected;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            height: 4,
            width: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Ülke seç', style: AuroraText.body(size: 18, weight: FontWeight.w800)),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: kCountryOptions.length,
              itemBuilder: (context, index) {
                final option = kCountryOptions[index];
                return ListTile(
                  onTap: () => Navigator.of(context).pop(option),
                  leading: Text(option.flag, style: const TextStyle(fontSize: 24)),
                  title: Text(option.name, style: AuroraText.body(size: 15)),
                  trailing: option.code == selected?.code
                      ? const Icon(Icons.check_rounded, color: Colors.white)
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
