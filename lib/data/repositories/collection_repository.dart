import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'package:ferrous/core/models/collection.dart';

class CollectionRepository extends ChangeNotifier {
  static const String _boxName = 'collections';

  Box<Collection>? _box;

  Future<void> init() async {
    _box = await Hive.openBox<Collection>(_boxName);
  }

  Box<Collection> get box {
    if (_box == null) {
      throw StateError('CollectionRepository not initialized. Call init() first.');
    }
    return _box!;
  }

  List<Collection> getAllCollections() {
    return box.values.toList();
  }

  Future<Collection> createCollection(String name) async {
    final collection = Collection(
      id: const Uuid().v4(),
      name: name,
      bookIds: [],
      createdAt: DateTime.now(),
    );
    await box.put(collection.id, collection);
    notifyListeners();
    return collection;
  }

  Future<void> deleteCollection(String id) async {
    await box.delete(id);
    notifyListeners();
  }

  Future<int> addBooksToCollection(String collectionId, Iterable<String> bookIds) async {
    final collection = box.get(collectionId);
    if (collection == null) return 0;

    int addedCount = 0;
    for (final bookId in bookIds) {
      if (!collection.bookIds.contains(bookId)) {
        collection.bookIds.add(bookId);
        addedCount++;
      }
    }
    if (addedCount > 0) {
      await collection.save();
      notifyListeners();
    }
    return addedCount;
  }

  Future<void> addBookToCollection(String collectionId, String bookId) async {
    await addBooksToCollection(collectionId, [bookId]);
  }

  Future<void> removeBookFromCollection(String collectionId, String bookId) async {
    final collection = box.get(collectionId);
    if (collection != null) {
      collection.bookIds.remove(bookId);
      await collection.save();
      notifyListeners();
    }
  }

  Future<void> removeBookFromAllCollections(String bookId) async {
    await removeBooksFromAllCollections([bookId]);
  }

  Future<void> removeBooksFromAllCollections(Iterable<String> bookIds) async {
    final idSet = bookIds.toSet();
    if (idSet.isEmpty) return;

    bool changed = false;
    for (final collection in box.values) {
      final initialCount = collection.bookIds.length;
      collection.bookIds.removeWhere((id) => idSet.contains(id));
      if (collection.bookIds.length != initialCount) {
        await collection.save();
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
    }
  }
  
  Collection? getCollection(String id) {
    return box.get(id);
  }
}
