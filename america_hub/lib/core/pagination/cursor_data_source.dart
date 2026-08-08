import 'cursor_page.dart';

abstract interface class CursorDataSource<T> {
  Future<CursorPage<T>> fetchPage({String? cursor, int limit = 20});
}
