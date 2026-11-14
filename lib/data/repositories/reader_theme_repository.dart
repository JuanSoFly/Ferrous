import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ferrous/data/models/reader_theme_config.dart';
import 'package:ferrous/data/models/tts_highlight_style.dart';

class ReaderThemeRepository extends ChangeNotifier {
  static const String _boxName = 'reader_theme';
  static const String _key = 'config';
  static const String _keyHighlightStyle = 'tts_highlight_style';

  Box<ReaderThemeConfig>? _box;
  ReaderThemeConfig _config = const ReaderThemeConfig();
  TtsHighlightStyle _highlightStyle = TtsHighlightStyle.softPill;
  bool _initialized = false;

  ReaderThemeConfig get config => _config;
  TtsHighlightStyle get highlightStyle => _highlightStyle;
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
      if (_config.fontSize < 12.0 || _config.fontSize > 100.0) {
        _config = _config.copyWith(fontSize: _config.fontSize.clamp(12.0, 100.0));
        _box?.put(_key, _config).catchError((_) {});
      }
    } catch (e) {
      debugPrint('Error reading config: $e. Using default.');
      _config = const ReaderThemeConfig();
      // Overwrite the corrupted/incompatible entry
      try {
        await _box!.put(_key, _config);
      } catch (_) {}
    }
    
    try {
      final settingsBox = await Hive.openBox('settings');
      final styleString = settingsBox.get(_keyHighlightStyle) as String?;
      if (styleString != null) {
        _highlightStyle = TtsHighlightStyle.values.byName(styleString);
      }
    } catch (e) {
      debugPrint('Error reading tts highlight style: $e. Using default.');
      _highlightStyle = TtsHighlightStyle.softPill;
    }
    
    _initialized = true;
    notifyListeners();
  }

  Future<void> setTtsHighlightStyle(TtsHighlightStyle style) async {
    _highlightStyle = style;
    notifyListeners();
    try {
      final settingsBox = await Hive.openBox('settings');
      await settingsBox.put(_keyHighlightStyle, style.name);
    } catch (e) {
      debugPrint('Failed to persist tts highlight style: $e');
    }
  }

  Future<void> updateConfig(ReaderThemeConfig newConfig) async {
    final clampedFontSize = newConfig.fontSize.clamp(12.0, 100.0);
    final sanitized = newConfig.fontSize != clampedFontSize
        ? newConfig.copyWith(fontSize: clampedFontSize)
        : newConfig;
    _config = sanitized;
    notifyListeners();
    
    // Only persist if box is available
    if (_box != null) {
      try {
        await _box!.put(_key, sanitized);
      } catch (e) {
        debugPrint('Failed to persist config: $e');
      }
    }
  }

  Future<void> setFontSize(double size) async {
    final clamped = size.clamp(12.0, 100.0);
    if (_config.fontSize == clamped) return;
    await updateConfig(_config.copyWith(fontSize: clamped));
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

  Future<void> setPageFlip(bool enabled) async {
    await updateConfig(_config.copyWith(pageFlip: enabled));
  }

  Future<void> setPaperTexture(String texture) async {
    await updateConfig(_config.copyWith(paperTexture: texture));
  }

  Future<void> toggleBookSpine() async {
    await updateConfig(_config.copyWith(showBookSpine: !_config.showBookSpine));
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
