/// Everything the staged onboarding flow collects, in one value.
///
/// The flow grew from two fields to ten, so the screen hands back a single
/// object instead of a widening list of positional arguments.
class OnboardingDraft {
  const OnboardingDraft({
    required this.city,
    required this.interests,
    required this.primaryIntent,
    this.countryCode = 'US',
    this.regionCode,
    this.bornInUs = false,
    this.arrivedMonth,
    this.arrivedYear,
    this.originCountry,
    this.originCity,
  });

  /// Where the member lives now. Free text, e.g. `Jersey City, NJ`.
  final String city;

  /// ISO-3166 alpha-2 of the country they live in. `US` for almost everyone.
  final String countryCode;

  /// Two-letter US state code. Required while [countryCode] is `US`, absent
  /// otherwise — community locality ranking reads this column.
  final String? regionCode;

  /// Persona ids picked on the last step. At least one, at most twelve.
  final List<String> interests;

  /// The intent of the first selected persona; drives recommendations.
  final String primaryIntent;

  /// Set when the member was born in the United States. Implies no arrival
  /// date and no country of origin.
  final bool bornInUs;

  final int? arrivedMonth;
  final int? arrivedYear;

  /// ISO-3166 alpha-2 of the country they moved from, e.g. `TR`.
  final String? originCountry;
  final String? originCity;

  /// True once the location step has produced something the API will accept.
  bool get hasUsableLocation =>
      city.trim().length >= 2 &&
      (countryCode != 'US' || (regionCode != null && regionCode!.length == 2));
}
