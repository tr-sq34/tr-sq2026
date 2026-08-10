import 'package:flutter/material.dart';

/// One card on the final onboarding step.
///
/// A persona answers "who are you here?" rather than "what topics do you like?"
/// — the community is a mix of employers, tradespeople, professionals, students
/// and people who landed last month, and recommendations only work if we know
/// which one is which.
class OnboardingPersona {
  const OnboardingPersona({
    required this.id,
    required this.label,
    required this.icon,
    required this.accent,
    required this.intent,
  });

  /// Stored verbatim in `interests`. Lowercase ASCII: the API lowercases with a
  /// Turkish locale, which would mangle anything containing `I`.
  final String id;
  final String label;
  final IconData icon;
  final Color accent;

  /// Contributes to `primaryIntent` when this is the first persona picked.
  final String intent;
}

class OnboardingPersonaGroup {
  const OnboardingPersonaGroup({required this.title, required this.personas});
  final String title;
  final List<OnboardingPersona> personas;
}

/// Interests are capped at twelve by the API contract
/// (`007_expand_onboarding_interests.sql`).
const int kMaxPersonaSelection = 12;

const _work = Color(0xFF7C6CF1);
const _service = Color(0xFF2FB4D9);
const _support = Color(0xFFE8A33A);
const _life = Color(0xFF19C29A);

const List<OnboardingPersonaGroup> kOnboardingPersonaGroups = [
  OnboardingPersonaGroup(
    title: 'İş & kariyer',
    personas: [
      OnboardingPersona(
        id: 'business_promote',
        label: 'İşletmemi tanıtıyorum',
        icon: Icons.storefront_rounded,
        accent: _work,
        intent: 'business',
      ),
      OnboardingPersona(
        id: 'hiring',
        label: 'Eleman arıyorum',
        icon: Icons.groups_2_rounded,
        accent: _work,
        intent: 'hiring',
      ),
      OnboardingPersona(
        id: 'job_seeking',
        label: 'İş arıyorum',
        icon: Icons.work_outline_rounded,
        accent: _work,
        intent: 'job_seeking',
      ),
      OnboardingPersona(
        id: 'freelance',
        label: 'Serbest çalışıyorum',
        icon: Icons.laptop_mac_rounded,
        accent: _work,
        intent: 'job_seeking',
      ),
    ],
  ),
  OnboardingPersonaGroup(
    title: 'Meslek & hizmet',
    personas: [
      OnboardingPersona(
        id: 'health_pro',
        label: 'Sağlık alanındayım',
        icon: Icons.medical_services_rounded,
        accent: _service,
        intent: 'professional_services',
      ),
      OnboardingPersona(
        id: 'tech_pro',
        label: 'Mühendislik & teknoloji',
        icon: Icons.memory_rounded,
        accent: _service,
        intent: 'professional_services',
      ),
      OnboardingPersona(
        id: 'legal_pro',
        label: 'Hukuk & göçmenlik',
        icon: Icons.gavel_rounded,
        accent: _service,
        intent: 'professional_services',
      ),
      OnboardingPersona(
        id: 'finance_pro',
        label: 'Muhasebe & vergi',
        icon: Icons.calculate_rounded,
        accent: _service,
        intent: 'professional_services',
      ),
      OnboardingPersona(
        id: 'realestate_pro',
        label: 'Emlak',
        icon: Icons.apartment_rounded,
        accent: _service,
        intent: 'professional_services',
      ),
      OnboardingPersona(
        id: 'advisor',
        label: 'Danışmanlık & koçluk',
        icon: Icons.lightbulb_rounded,
        accent: _service,
        intent: 'advisory',
      ),
    ],
  ),
  OnboardingPersonaGroup(
    title: 'Destek arıyorum',
    personas: [
      OnboardingPersona(
        id: 'newcomer',
        label: 'Amerika’ya yeni geldim',
        icon: Icons.flight_land_rounded,
        accent: _support,
        intent: 'newcomer',
      ),
      OnboardingPersona(
        id: 'legal_help',
        label: 'Hukuki destek arıyorum',
        icon: Icons.balance_rounded,
        accent: _support,
        intent: 'legal_support',
      ),
      OnboardingPersona(
        id: 'immigration_help',
        label: 'Vize & göçmenlik süreci',
        icon: Icons.assignment_ind_rounded,
        accent: _support,
        intent: 'legal_support',
      ),
      OnboardingPersona(
        id: 'housing_help',
        label: 'Ev veya oda arıyorum',
        icon: Icons.house_rounded,
        accent: _support,
        intent: 'newcomer',
      ),
    ],
  ),
  OnboardingPersonaGroup(
    title: 'Topluluk & yaşam',
    personas: [
      OnboardingPersona(
        id: 'community_meet',
        label: 'Türk topluluğuyla tanışmak',
        icon: Icons.handshake_rounded,
        accent: _life,
        intent: 'community',
      ),
      OnboardingPersona(
        id: 'student',
        label: 'Öğrenciyim',
        icon: Icons.school_rounded,
        accent: _life,
        intent: 'education',
      ),
      OnboardingPersona(
        id: 'family',
        label: 'Aile & çocuk',
        icon: Icons.family_restroom_rounded,
        accent: _life,
        intent: 'community',
      ),
      OnboardingPersona(
        id: 'events',
        label: 'Etkinlik & buluşma',
        icon: Icons.celebration_rounded,
        accent: _life,
        intent: 'events',
      ),
      OnboardingPersona(
        id: 'food',
        label: 'Yemek & restoran',
        icon: Icons.restaurant_rounded,
        accent: _life,
        intent: 'community',
      ),
      OnboardingPersona(
        id: 'sports',
        label: 'Spor & doğa',
        icon: Icons.sports_soccer_rounded,
        accent: _life,
        intent: 'community',
      ),
      OnboardingPersona(
        id: 'marketplace',
        label: 'Alışveriş & çarşı',
        icon: Icons.shopping_bag_rounded,
        accent: _life,
        intent: 'marketplace',
      ),
      OnboardingPersona(
        id: 'travel',
        label: 'Seyahat & bavulda yer',
        icon: Icons.luggage_rounded,
        accent: _life,
        intent: 'community',
      ),
    ],
  ),
];

final Map<String, OnboardingPersona> kOnboardingPersonasById = {
  for (final group in kOnboardingPersonaGroups)
    for (final persona in group.personas) persona.id: persona,
};

/// The intent recorded for a selection, taken from the first persona picked.
/// Falls back to `community` so a stale selection can never fail validation.
String primaryIntentFor(List<String> selectedIds) {
  for (final id in selectedIds) {
    final persona = kOnboardingPersonasById[id];
    if (persona != null) return persona.intent;
  }
  return 'community';
}
