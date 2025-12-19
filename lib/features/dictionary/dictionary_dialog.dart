import 'package:flutter/material.dart';
import 'package:reader_app/data/models/word_definition.dart';
import 'package:reader_app/data/repositories/dictionary_repository.dart';

class DictionaryDialog extends StatefulWidget {
  final String word;

  const DictionaryDialog({super.key, required this.word});

  @override
  State<DictionaryDialog> createState() => _DictionaryDialogState();
}

class _DictionaryDialogState extends State<DictionaryDialog> {
  final DictionaryRepository _repository = DictionaryRepository();
  bool _isLoading = true;
  String? _error;
  List<WordDefinition> _definitions = [];

  @override
  void initState() {
    super.initState();
    _fetchDefinition();
  }

  Future<void> _fetchDefinition() async {
    try {
      final definitions = await _repository.fetchDefinition(widget.word);
      if (mounted) {
        setState(() {
          _definitions = definitions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.word,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center),
          ],
        ),
      );
    }

    if (_definitions.isEmpty) {
      return const Center(child: Text('No definitions found.'));
    }

    final def = _definitions.first;
    return ListView(
      shrinkWrap: true,
      children: [
        if (def.phonetic != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(
              def.phonetic!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: Colors.grey,
                  ),
            ),
          ),
        ...def.meanings.map((meaning) => _buildMeaning(meaning)),
      ],
    );
  }

  Widget _buildMeaning(Meaning meaning) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            meaning.partOfSpeech,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          ...meaning.definitions.asMap().entries.map((entry) {
            final index = entry.key + 1;
            final definition = entry.value;
            return Padding(
              padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$index. ${definition.definition}'),
                  if (definition.example != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        '"${definition.example}"',
                        style: const TextStyle(
                          fontStyle: FontStyle.italic,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

Future<void> showDictionaryDialog(BuildContext context, String word) async {
  await showDialog(
    context: context,
    builder: (context) => DictionaryDialog(word: word),
  );
}
