import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Controller for reader chrome visibility and lock mode.
class ReaderChromeController extends ChangeNotifier {
  bool _showChrome = false;
  bool _isLocked = false;

  bool get showChrome => _showChrome;
  bool get isLocked => _isLocked;

  /// Toggle chrome visibility.
  void toggleChrome() {
    if (_isLocked) return;
    _showChrome = !_showChrome;
    _updateSystemUiMode();
    notifyListeners();
  }

  /// Set chrome visibility explicitly.
  void setShowChrome(bool value) {
    if (_showChrome == value) return;
    _showChrome = value;
    _updateSystemUiMode();
    notifyListeners();
  }

  /// Toggle lock mode.
  bool toggleLockMode() {
    _isLocked = !_isLocked;
    if (_isLocked) {
      _showChrome = false;
    } else {
      _showChrome = true;
    }
    _updateSystemUiMode();
    notifyListeners();
    return _isLocked;
  }

  /// Update system UI mode based on chrome/lock state.
  void _updateSystemUiMode() {
    if (_showChrome && !_isLocked) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  /// Force system UI to immersive mode (used when entering reader).
  void enterImmersiveMode() {
    _updateSystemUiMode();
  }

  /// Restore system UI to normal (used when exiting reader).
  void exitToNormalMode() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  /// Check if a global position is within the center tap zone.
  bool isCenterTap(Offset globalPosition, Size screenSize) {
    if (screenSize.isEmpty) return false;
    final centerWidth = screenSize.width * 0.45;
    final centerHeight = screenSize.height * 0.35;
    final left = (screenSize.width - centerWidth) / 2;
    final top = (screenSize.height - centerHeight) / 2;
    final rect = Rect.fromLTWH(left, top, centerWidth, centerHeight);
    return rect.contains(globalPosition);
  }

  /// Reset to default state.
  void reset() {
    _showChrome = false;
    _isLocked = false;
    notifyListeners();
  }
}
