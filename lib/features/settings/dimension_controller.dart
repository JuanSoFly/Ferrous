import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:state_notifier/state_notifier.dart';
import 'package:ferrous/core/models/app_dimension.dart';
import 'package:ferrous/features/settings/app_themes.dart';

/// State snapshot for Ferrous App Dimension.
class DimensionState {
  final AppDimension dimension;
  final bool autoSyncWithTheme;

  const DimensionState({
    this.dimension = AppDimension.modernist,
    this.autoSyncWithTheme = true,
  });

  DimensionConfig get config => DimensionConfig.forDimension(dimension);

  DimensionState copyWith({
    AppDimension? dimension,
    bool? autoSyncWithTheme,
  }) {
    return DimensionState(
      dimension: dimension ?? this.dimension,
      autoSyncWithTheme: autoSyncWithTheme ?? this.autoSyncWithTheme,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DimensionState &&
          runtimeType == other.runtimeType &&
          dimension == other.dimension &&
          autoSyncWithTheme == other.autoSyncWithTheme;

  @override
  int get hashCode => dimension.hashCode ^ autoSyncWithTheme.hashCode;
}

/// Controller managing active App Dimension and Theme Coupling.
class DimensionController extends StateNotifier<DimensionState> {
  static const String _boxName = 'settings';
  static const String _keyDimension = 'app_dimension';
  static const String _keyAutoSync = 'sync_dimension_with_theme';

  DimensionController() : super(const DimensionState()) {
    _loadDimension();
  }

  Future<void> _loadDimension() async {
    try {
      final box = await Hive.openBox(_boxName);
      final dimensionName = box.get(_keyDimension) as String?;
      final autoSync = box.get(_keyAutoSync, defaultValue: true) as bool;

      AppDimension loadedDimension = AppDimension.modernist;
      if (dimensionName != null) {
        try {
          loadedDimension = AppDimension.values.byName(dimensionName);
        } catch (_) {
          loadedDimension = AppDimension.modernist;
        }
      }

      state = DimensionState(
        dimension: loadedDimension,
        autoSyncWithTheme: autoSync,
      );
    } catch (e) {
      debugPrint('Error loading dimension settings: $e');
    }
  }

  Future<void> setDimension(AppDimension dimension) async {
    state = state.copyWith(dimension: dimension);
    try {
      final box = await Hive.openBox(_boxName);
      await box.put(_keyDimension, dimension.name);
    } catch (e) {
      debugPrint('Error persisting dimension: $e');
    }
  }

  Future<void> setAutoSync(bool enabled) async {
    state = state.copyWith(autoSyncWithTheme: enabled);
    try {
      final box = await Hive.openBox(_boxName);
      await box.put(_keyAutoSync, enabled);
    } catch (e) {
      debugPrint('Error persisting auto-sync: $e');
    }
  }

  /// Called by ThemeController whenever the user changes the color theme.
  Future<void> onThemeChanged(AppTheme theme) async {
    if (!state.autoSyncWithTheme) return;
    final targetDimension = DimensionConfig.dimensionForTheme(theme);
    if (targetDimension != state.dimension) {
      await setDimension(targetDimension);
    }
  }
}
