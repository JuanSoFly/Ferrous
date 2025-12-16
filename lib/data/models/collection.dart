import 'package:hive/hive.dart';

@HiveType(typeId: 2)
class Collection extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final List<String> bookIds;

  @HiveField(3)
  final DateTime createdAt;

  Collection({
    required this.id,
    required this.name,
    required this.bookIds,
    required this.createdAt,
  });

  Collection copyWith({
    String? id,
    String? name,
    List<String>? bookIds,
    DateTime? createdAt,
  }) {
    return Collection(
      id: id ?? this.id,
      name: name ?? this.name,
      bookIds: bookIds ?? this.bookIds,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
