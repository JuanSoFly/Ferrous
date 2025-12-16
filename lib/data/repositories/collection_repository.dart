import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'package:reader_app/data/models/collection.dart';

class CollectionRepository {
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

  Future<void> createCollection(String name) async {
    final collection = Collection(
      id: const Uuid().v4(),
      name: name,
      bookIds: [],
      createdAt: DateTime.now(),
    );
    await box.put(collection.id, collection);
  }

  Future<void> deleteCollection(String id) async {
    await box.delete(id);
  }

  Future<void> addBookToCollection(String collectionId, String bookId) async {
    final collection = box.get(collectionId);
    if (collection != null && !collection.bookIds.contains(bookId)) {
      collection.bookIds.add(bookId);
      await collection.save();
    }
  }

  Future<void> removeBookFromCollection(String collectionId, String bookId) async {
    final collection = box.get(collectionId);
    if (collection != null) {
      collection.bookIds.remove(bookId);
      await collection.save();
    }
  }
  
  Collection? getCollection(String id) {
    return box.get(id);
  }
}
