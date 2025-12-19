// Models for dictionary API responses.

class WordDefinition {
  final String word;
  final String? phonetic;
  final List<Meaning> meanings;

  WordDefinition({
    required this.word,
    this.phonetic,
    required this.meanings,
  });

  factory WordDefinition.fromJson(Map<String, dynamic> json) {
    return WordDefinition(
      word: json['word'] ?? '',
      phonetic: json['phonetic'] as String?,
      meanings: (json['meanings'] as List<dynamic>?)
              ?.map((m) => Meaning.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class Meaning {
  final String partOfSpeech;
  final List<Definition> definitions;

  Meaning({
    required this.partOfSpeech,
    required this.definitions,
  });

  factory Meaning.fromJson(Map<String, dynamic> json) {
    return Meaning(
      partOfSpeech: json['partOfSpeech'] ?? '',
      definitions: (json['definitions'] as List<dynamic>?)
              ?.map((d) => Definition.fromJson(d as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class Definition {
  final String definition;
  final String? example;

  Definition({
    required this.definition,
    this.example,
  });

  factory Definition.fromJson(Map<String, dynamic> json) {
    return Definition(
      definition: json['definition'] ?? '',
      example: json['example'] as String?,
    );
  }
}
