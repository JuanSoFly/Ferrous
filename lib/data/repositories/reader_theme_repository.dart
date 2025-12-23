import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:reader_app/data/models/reader_theme_config.dart';

class ReaderThemeRepository extends ChangeNotifier {
  static const String _boxName = 'reader_theme';
  static const String _key = 'config';

  Box<ReaderThemeConfig>? _box;
  ReaderThemeConfig _config = const ReaderThemeConfig();
  bool _initialized = false;

  ReaderThemeConfig get config => _config;
  bool get isInitialized => _initialized;

  Future<void> init() async {
    try {
      _box = await Hive.openBox<ReaderThemeConfig>(_boxName);
    } catch (e) {
      debugPrint('Error opening ReaderThemeConfig box: $e. Deleting and recreating box.');
      try {
        await Hive.deleteBoxFromDisk(_boxName);
        _box = await Hive.openBox<ReaderThemeConfig>(_boxName);
      } catch (e2) {
        debugPrint('Failed to recover box: $e2. Operating without persistence.');
        _initialized = false;
        notifyListeners();
        return;
      }
    }
    
    // Ensure we handle potential type mismatches or incomplete data
    try {
      _config = _box!.get(_key, defaultValue: const ReaderThemeConfig())!;
    } catch (e) {
      debugPrint('Error reading config: $e. Using default.');
      _config = const ReaderThemeConfig();
      // Overwrite the corrupted/incompatible entry
      try {
        await _box!.put(_key, _config);
      } catch (_) {}
    }
    
    _initialized = true;
    notifyListeners();
  }

  Future<void> updateConfig(ReaderThemeConfig newConfig) async {
    _config = newConfig;
    notifyListeners(); // Notify immediately for instant UI update
    
    // Only persist if box is available
    if (_box != null) {
      try {
        await _box!.put(_key, newConfig);
      } catch (e) {
        debugPrint('Failed to persist config: $e');
      }
    }
  }

  Future<void> setFontSize(double size) async {
    await updateConfig(_config.copyWith(fontSize: size));
  }
  
  Future<void> setFontFamily(String family) async {
    await updateConfig(_config.copyWith(fontFamily: family));
  }

  Future<void> setLineHeight(double height) async {
    await updateConfig(_config.copyWith(lineHeight: height));
  }

  Future<void> setParagraphSpacing(double spacing) async {
    await updateConfig(_config.copyWith(paragraphSpacing: spacing));
  }

  Future<void> setTextAlign(String align) async {
    await updateConfig(_config.copyWith(textAlign: align));
  }
  
  Future<void> setWordSpacing(double spacing) async {
    await updateConfig(_config.copyWith(wordSpacing: spacing));
  }

  Future<void> togglePageMargins() async {
    await updateConfig(_config.copyWith(pageMargins: !_config.pageMargins));
  }

  Future<void> togglePageFlip() async {
    await updateConfig(_config.copyWith(pageFlip: !_config.pageFlip));
  }
  
  Future<void> toggleParagraphIndent() async {
    await updateConfig(_config.copyWith(paragraphIndent: !_config.paragraphIndent));
  }
  
  Future<void> toggleHyphenation() async {
    await updateConfig(_config.copyWith(hyphenation: !_config.hyphenation));
  }

  Future<void> setFontWeight(int weight) async {
    await updateConfig(_config.copyWith(fontWeight: weight));
  }
}
