import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:ferrous/core/models/annotation.dart';

/// Repository for managing annotations with reactive notifications.
class AnnotationRepository extends ChangeNotifier {
  static const String _boxName = 'annotations';

  Box<Annotation>? _box;

  Future<void> init() async {
    _box = await Hive.openBox<Annotation>(_boxName);
  }

  Box<Annotation> get box {
    if (_box == null) {
      throw StateError('AnnotationRepository not initialized. Call init() first.');
    }
    return _box!;
  }

  List<Annotation> getAllAnnotations() {
    return box.values.toList();
  }

  List<Annotation> getAnnotationsForBook(String bookId) {
    return box.values.where((a) => a.bookId == bookId).toList();
  }

  Future<void> addAnnotation(Annotation annotation) async {
    await box.put(annotation.id, annotation);
    notifyListeners();
  }

  Future<void> updateAnnotation(Annotation annotation) async {
    await box.put(annotation.id, annotation);
    notifyListeners();
  }

  Future<void> deleteAnnotation(String id) async {
    await box.delete(id);
    notifyListeners();
  }

  Future<void> deleteAnnotationsForBook(String bookId) async {
    await deleteAnnotationsForBooks([bookId]);
  }

  Future<void> deleteAnnotationsForBooks(Iterable<String> bookIds) async {
    final idSet = bookIds.toSet();
    if (idSet.isEmpty) return;

    final idsToDelete = box.values
        .where((a) => idSet.contains(a.bookId))
        .map((a) => a.id)
        .toList();
    if (idsToDelete.isNotEmpty) {
      await box.deleteAll(idsToDelete);
      notifyListeners();
    }
  }
}
