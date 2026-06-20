import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/models/bookmark.dart';

class BookmarksNotifier extends StateNotifier<AsyncValue<List<Bookmark>>> {
  BookmarksNotifier() : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    try {
      final bookmarks = await DatabaseHelper.instance.getAllBookmarks();
      state = AsyncValue.data(bookmarks);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> add(Bookmark bookmark) async {
    await DatabaseHelper.instance.addBookmark(bookmark);
    await load();
  }

  Future<void> remove(String id) async {
    await DatabaseHelper.instance.removeBookmark(id);
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(current.where((b) => b.id != id).toList());
  }

  Future<void> updateNote(String id, String note) async {
    await DatabaseHelper.instance.updateBookmarkNote(id, note);
    await load();
  }
}

final bookmarksProvider =
    StateNotifierProvider<BookmarksNotifier, AsyncValue<List<Bookmark>>>(
  (ref) => BookmarksNotifier(),
);
