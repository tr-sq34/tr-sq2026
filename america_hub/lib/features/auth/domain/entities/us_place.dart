/// A selectable place in the onboarding location step.
///
/// Either a city inside a state (`Jersey City, NJ`) or a whole state on its own,
/// so a member whose town is missing from the offline index is never stuck.
class UsPlace {
  const UsPlace({required this.stateCode, required this.state, this.city});

  /// Two-letter US state code — the value stored as `region_code`.
  final String stateCode;

  /// Full state name, used for matching ("new jer" finds New Jersey).
  final String state;

  /// Null for a state-level entry.
  final String? city;

  bool get isState => city == null;

  /// What gets written to the profile's `city` column and shown in the field.
  String get label => city == null ? state : '$city, $stateCode';

  @override
  bool operator ==(Object other) =>
      other is UsPlace &&
      other.stateCode == stateCode &&
      other.city == city;

  @override
  int get hashCode => Object.hash(stateCode, city);

  @override
  String toString() => label;
}
