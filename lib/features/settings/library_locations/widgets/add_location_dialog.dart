import 'package:flutter/material.dart';
import 'package:ferrous/core/widgets/storage_mode_dialog.dart';
import 'package:ferrous/data/services/saf_service.dart';

/// Adapter class delegating to the unified, theme-aware [StorageModeDialog].
class AddLocationDialog {
  const AddLocationDialog._();

  static Future<SafStorageMode?> show(BuildContext context) {
    return StorageModeDialog.show(
      context,
      targetType: StorageTargetType.folder,
    );
  }
}
