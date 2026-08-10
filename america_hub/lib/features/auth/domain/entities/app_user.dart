class AppUser {
  const AppUser({required this.id, required this.email, this.displayName});

  final String id;
  final String email;

  /// The name the member signed up with. Nullable because a session stored by
  /// an older build predates the field, and because the UI must fall back
  /// rather than invent a name.
  final String? displayName;

  /// What to greet the member with. The part of the address before the `@` is a
  /// poor substitute, but it is at least theirs — unlike a placeholder name.
  String get shortName {
    final name = displayName?.trim() ?? '';
    if (name.isNotEmpty) return name.split(RegExp(r'\s+')).first;
    final local = email.split('@').first.trim();
    return local.isEmpty ? 'Hoş geldin' : local;
  }

  /// The whole name, for bylines that name the author rather than greet them.
  /// Falls back the same way [shortName] does: something that is at least the
  /// member's own, never a stand-in person.
  String get fullName {
    final name = displayName?.trim() ?? '';
    return name.isNotEmpty ? name : shortName;
  }

  /// Up to two letters for an avatar placeholder, until a real photo exists.
  String get initials {
    final name = displayName?.trim() ?? '';
    final source = name.isNotEmpty ? name : email.split('@').first;
    final words = source
        .split(RegExp(r'[\s._\-]+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) return '?';
    final letters = words.length == 1
        ? _firstLetters(words.first, 2)
        : '${_firstLetters(words.first, 1)}${_firstLetters(words[1], 1)}';
    return letters.toUpperCase();
  }

  static String _firstLetters(String word, int count) =>
      word.length <= count ? word : word.substring(0, count);
}
