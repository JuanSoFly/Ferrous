import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:reader_app/core/models/word_definition.dart';

class DictionaryRepository {
  static const String _baseUrl = 'https://api.dictionaryapi.dev/api/v2/entries/en';

  /// Fetches definitions for a word.
  Future<List<WordDefinition>> fetchDefinition(String word) async {
    final cleanWord = word.trim().toLowerCase();
    if (cleanWord.isEmpty) {
      throw Exception('Word cannot be empty');
    }

    final uri = Uri.parse('$_baseUrl/$cleanWord');
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data
          .map((item) => WordDefinition.fromJson(item as Map<String, dynamic>))
          .toList();
    } else if (response.statusCode == 404) {
      throw Exception('No definition found for "$cleanWord"');
    } else {
      throw Exception('Failed to fetch definition: ${response.statusCode}');
    }
  }
}
