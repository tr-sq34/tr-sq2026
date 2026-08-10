import 'package:flutter/material.dart';

import '../../../domain/entities/country_option.dart';
import 'aurora_surfaces.dart';
import 'month_year_wheel.dart';
import 'onboarding_step_scaffold.dart';

/// When and where from a member arrived in the United States.
class ArrivalAnswer {
  const ArrivalAnswer({
    this.bornInUs = false,
    this.month,
    this.year,
    this.originCountry,
    this.originCity,
  });

  final bool bornInUs;
  final int? month;
  final int? year;
  final String? originCountry;
  final String? originCity;

  /// The step is answered once we know either that they were born here or when
  /// they arrived. Country and city of origin stay optional throughout.
  bool get isComplete => bornInUs || (month != null && year != null);

  ArrivalAnswer copyWith({
    bool? bornInUs,
    int? month,
    int? year,
    String? originCountry,
    String? originCity,
    bool clearOrigin = false,
  }) => ArrivalAnswer(
    bornInUs: bornInUs ?? this.bornInUs,
    month: month ?? this.month,
    year: year ?? this.year,
    originCountry: clearOrigin ? null : (originCountry ?? this.originCountry),
    originCity: clearOrigin ? null : (originCity ?? this.originCity),
  );
}

class ArrivalStep extends StatefulWidget {
  const ArrivalStep({
    super.key,
    required this.answer,
    required this.onChanged,
    required this.currentYear,
  });

  final ArrivalAnswer answer;

  /// [confirmed] is true once the step holds a complete answer, which is what
  /// the shell auto-advances on.
  final void Function(ArrivalAnswer value, {required bool confirmed}) onChanged;

  final int currentYear;

  @override
  State<ArrivalStep> createState() => _ArrivalStepState();
}

class _ArrivalStepState extends State<ArrivalStep> {
  late final TextEditingController _originCity = TextEditingController(
    text: widget.answer.originCity ?? '',
  );

  @override
  void dispose() {
    _originCity.dispose();
    super.dispose();
  }

  void _emit(ArrivalAnswer next, {bool? confirmed}) {
    final wasComplete = widget.answer.isComplete;
    widget.onChanged(
      next,
      // Only the transition into a complete answer advances; editing an
      // already complete answer must not yank the member forward again.
      confirmed: confirmed ?? (next.isComplete && !wasComplete),
    );
  }

  @override
  Widget build(BuildContext context) {
    final answer = widget.answer;
    final origin = countryByCode(answer.originCountry) ?? kCountryOptions.first;

    return OnboardingStepScaffold(
      icon: Icons.flight_land_rounded,
      title: 'Amerika hikâyen\nne zaman başladı?',
      subtitle:
          'Aynı dönemde gelenlerle ve aynı şehirden çıkanlarla eşleştirebilmemiz '
          'için soruyoruz. Bu adımı atlayabilirsin.',
      accent: const Color(0xFFE8A33A),
      children: [
        AuroraCard(
          onTap: () => _emit(
            ArrivalAnswer(
              bornInUs: !answer.bornInUs,
              month: answer.bornInUs ? answer.month : null,
              year: answer.bornInUs ? answer.year : null,
            ),
          ),
          selected: answer.bornInUs,
          accent: const Color(0xFFE8A33A),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.flag_rounded, size: 20, color: Colors.white.withValues(alpha: .8)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Amerika’da doğdum',
                  style: AuroraText.body(size: 14, weight: FontWeight.w600),
                ),
              ),
              Switch(
                value: answer.bornInUs,
                onChanged: (value) => _emit(
                  ArrivalAnswer(
                    bornInUs: value,
                    month: value ? null : answer.month,
                    year: value ? null : answer.year,
                  ),
                ),
                activeThumbColor: Colors.white,
                activeTrackColor: const Color(0xFFE8A33A),
                inactiveThumbColor: Colors.white.withValues(alpha: .75),
                inactiveTrackColor: Colors.white.withValues(alpha: .14),
              ),
            ],
          ),
        ),
        if (!answer.bornInUs) ...[
          const SizedBox(height: 24),
          Text('NE ZAMAN GELDİN?', style: AuroraText.sectionLabel()),
          const SizedBox(height: 12),
          MonthYearWheel(
            month: answer.month,
            year: answer.year,
            currentYear: widget.currentYear,
            accent: const Color(0xFFE8A33A),
            // Built rather than copied: the wheels can go back to "unchosen",
            // which copyWith cannot express.
            onChanged: (month, year) => _emit(
              ArrivalAnswer(
                month: month,
                year: year,
                originCountry: answer.originCountry,
                originCity: answer.originCity,
              ),
            ),
          ),
          const SizedBox(height: 26),
          Text('NEREDEN GELDİN? (İSTEĞE BAĞLI)', style: AuroraText.sectionLabel()),
          const SizedBox(height: 12),
          AuroraCard(
            onTap: () => _pickOrigin(origin),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Text(origin.flag, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 12),
                Expanded(child: Text(origin.name, style: AuroraText.body(size: 15))),
                Icon(Icons.expand_more_rounded, color: Colors.white.withValues(alpha: .6)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          AuroraTextField(
            controller: _originCity,
            hintText: 'Hangi şehirden? (isteğe bağlı)',
            prefixIcon: Icons.location_city_rounded,
            onChanged: (value) => _emit(
              answer.copyWith(
                originCountry: answer.originCountry ?? origin.code,
                originCity: value.trim(),
              ),
              confirmed: false,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _pickOrigin(CountryOption current) async {
    final selected = await showModalBottomSheet<CountryOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF211838),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => _OriginSheet(selected: current),
    );
    if (selected == null || !mounted) return;
    _emit(widget.answer.copyWith(originCountry: selected.code), confirmed: false);
  }
}

class _OriginSheet extends StatelessWidget {
  const _OriginSheet({required this.selected});

  final CountryOption selected;

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
              child: Text(
                'Hangi ülkeden geldin?',
                style: AuroraText.body(size: 18, weight: FontWeight.w800),
              ),
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
                  trailing: option.code == selected.code
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
