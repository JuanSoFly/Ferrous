import 'package:hive/hive.dart';
import 'package:reader_app/data/models/annotation.dart';

class AnnotationRepository {
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
  }

  Future<void> updateAnnotation(Annotation annotation) async {
    await box.put(annotation.id, annotation);
  }

  Future<void> deleteAnnotation(String id) async {
    await box.delete(id);
  }
}
