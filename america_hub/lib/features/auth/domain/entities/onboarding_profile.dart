class OnboardingProfile {
  const OnboardingProfile({
    required this.completed,
    this.city,
    this.regionCode,
    this.interests = const [],
    this.primaryIntent,
  });

  final bool completed;
  final String? city;
  final String? regionCode;
  final List<String> interests;
  final String? primaryIntent;
}
