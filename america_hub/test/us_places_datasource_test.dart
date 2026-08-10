import 'package:america_hub/features/auth/data/datasources/us_places_local_datasource.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercises the real bundled `assets/data/us_places.json`, so a regenerated or
/// truncated dataset fails here rather than in front of a member.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UsPlacesLocalDataSource places;

  setUp(() => places = UsPlacesLocalDataSource());

  test('a partial city name finds the city and carries its state code', () async {
    final results = await places.search('jers');

    expect(results.first.city, 'Jersey City');
    expect(results.first.stateCode, 'NJ');
    expect(results.first.label, 'Jersey City, NJ');
  });

  test('cities the Turkish community actually lives in are in the index', () async {
    for (final query in ['paterson', 'sunnyside', 'astoria', 'dearborn']) {
      expect(
        (await places.search(query)).map((place) => place.city),
        contains(isNotNull),
        reason: '"$query" should match at least one city',
      );
    }
  });

  test('a Turkish keyboard still matches ASCII place names', () async {
    // Someone typing on a Turkish layout produces "İ", which lowercases to "i̇"
    // under the Turkish locale and would otherwise never match "Indianapolis".
    final results = await places.search('İndian');

    expect(results.map((place) => place.city), contains('Indianapolis'));
  });

  test('one character is too little to suggest anything', () async {
    expect(await places.search('n'), isEmpty);
  });

  test('the device geocoder\'s administrative area maps to a state code', () async {
    expect(await places.stateCodeFor('New Jersey'), 'NJ');
    expect(await places.stateCodeFor('NJ'), 'NJ');
    expect(await places.stateCodeFor('Ontario'), isNull);
  });
}
