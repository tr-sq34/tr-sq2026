class OnboardingProfile {
  const OnboardingProfile({
    required this.completed,
    this.city,
    this.countryCode,
    this.regionCode,
    this.interests = const [],
    this.primaryIntent,
    this.bornInUs = false,
    this.arrivedMonth,
    this.arrivedYear,
    this.originCountry,
    this.originCity,
  });

  final bool completed;
  final String? city;
  final String? countryCode;
  final String? regionCode;
  final List<String> interests;
  final String? primaryIntent;
  final bool bornInUs;
  final int? arrivedMonth;
  final int? arrivedYear;
  final String? originCountry;
  final String? originCity;
}
