import 'package:hive_flutter/hive_flutter.dart';
import 'package:state_notifier/state_notifier.dart';
import 'package:reader_app/utils/app_themes.dart';

class ThemeController extends StateNotifier<AppTheme> {
  static const String _boxName = 'settings';
  static const String _keyTheme = 'app_theme';

  ThemeController() : super(AppTheme.ferrous) {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final box = await Hive.openBox(_boxName);
    final themeName = box.get(_keyTheme) as String?;
    
    if (themeName != null) {
      try {
        state = AppTheme.values.byName(themeName);
      } catch (_) {
        state = AppTheme.ferrous; // Fallback
      }
    }
  }

  Future<void> setTheme(AppTheme theme) async {
    state = theme;
    final box = await Hive.openBox(_boxName);
    await box.put(_keyTheme, theme.name);
  }
}
