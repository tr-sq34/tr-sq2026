import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/entities/us_place.dart';

/// Offline index of US cities and states, loaded once from
/// `assets/data/us_places.json` (regenerate with `tool/build_us_places.py`).
///
/// The onboarding location step used to show seven hardcoded suggestions under
/// a caption promising Google Maps results that were never wired up. This is
/// the honest replacement: no network call, no API key, no fabricated place.
class UsPlacesLocalDataSource {
  UsPlacesLocalDataSource({AssetBundle? bundle}) : _bundle = bundle;

  static const assetPath = 'assets/data/us_places.json';

  final AssetBundle? _bundle;

  List<UsPlace>? _places;
  Map<String, String>? _stateCodeByName;
  List<String>? _searchKeys;
  Future<void>? _loading;

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    final raw = await (_bundle ?? rootBundle).loadString(assetPath);
    final data = jsonDecode(raw) as Map<String, dynamic>;

    final states = <UsPlace>[];
    final byName = <String, String>{};
    for (final entry in (data['states'] as List<dynamic>? ?? const [])) {
      final map = entry as Map<String, dynamic>;
      final code = map['stateCode'] as String;
      final name = map['state'] as String;
      states.add(UsPlace(stateCode: code, state: name));
      byName[_fold(name)] = code;
      byName[_fold(code)] = code;
    }

    final cities = <UsPlace>[];
    for (final entry in (data['cities'] as List<dynamic>? ?? const [])) {
      final map = entry as Map<String, dynamic>;
      cities.add(
        UsPlace(
          stateCode: map['stateCode'] as String,
          state: map['state'] as String,
          city: map['city'] as String,
        ),
      );
    }

    // Cities first: someone typing "new" wants New York before New Jersey.
    final all = <UsPlace>[...cities, ...states];
    _places = List.unmodifiable(all);
    _stateCodeByName = Map.unmodifiable(byName);
    _searchKeys = List.unmodifiable(
      all.map((place) => _fold('${place.city ?? ''} ${place.state} ${place.stateCode}')),
    );
  }

  /// Ranked matches for a partial query. Empty for queries shorter than two
  /// characters, so the field stays quiet until the member has typed something.
  Future<List<UsPlace>> search(String query, {int limit = 8}) async {
    await ensureLoaded();
    return searchLoaded(query, limit: limit);
  }

  /// The same ranking without the wait: empty until [ensureLoaded] has
  /// finished. Typing runs through here so a keystroke never has to hop
  /// through the event loop before the list can be drawn.
  List<UsPlace> searchLoaded(String query, {int limit = 8}) {
    final places = _places;
    if (places == null) return const [];
    final needle = _fold(query);
    if (needle.length < 2) return const [];

    final keys = _searchKeys!;
    final scored = <({UsPlace place, int score})>[];
    for (var index = 0; index < places.length; index++) {
      final score = _score(keys[index], needle, places[index]);
      if (score > 0) scored.add((place: places[index], score: score));
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.place.label.length.compareTo(b.place.label.length);
    });
    return scored.take(limit).map((entry) => entry.place).toList(growable: false);
  }

  /// Resolves whatever the device geocoder reports as the administrative area
  /// ("New Jersey" or already "NJ") to the two-letter code the API expects.
  Future<String?> stateCodeFor(String administrativeArea) async {
    await ensureLoaded();
    final folded = _fold(administrativeArea);
    if (folded.isEmpty) return null;
    return _stateCodeByName![folded];
  }

  static int _score(String key, String needle, UsPlace place) {
    final position = key.indexOf(needle);
    if (position < 0) return 0;
    // Start of the entry beats start of a later word, which beats a mid-word
    // hit; cities outrank bare states at equal quality.
    var score = position == 0
        ? 100
        : (key[position - 1] == ' ' ? 60 : 20);
    if (!place.isState) score += 5;
    return score;
  }

  /// Case- and diacritic-insensitive key. Members type on a Turkish keyboard,
  /// so `İ`/`ı`/`ş` have to fold onto their ASCII counterparts.
  static String _fold(String value) {
    const from = 'ÇĞİIÖŞÜçğıiöşüáàâäéèêëíìîïóòôöúùûüÁÀÂÄÉÈÊËÍÌÎÏÓÒÔÖÚÙÛÜñÑ';
    const to = 'cgiiosucgiiosuaaaaeeeeiiiioooouuuuaaaaeeeeiiiioooouuuunn';
    final buffer = StringBuffer();
    for (final rune in value.trim().runes) {
      final char = String.fromCharCode(rune);
      final index = from.indexOf(char);
      buffer.write(index >= 0 ? to[index] : char.toLowerCase());
    }
    return buffer.toString().replaceAll(RegExp(r'[.,]'), '').replaceAll(RegExp(r'\s+'), ' ');
  }
}
