/// This is copied from Cargokit (which is the official way to use it currently)
/// Details: https://fzyzcjy.github.io/flutter_rust_bridge/manual/integrate/builtin
///
/// This file contains hardened file copy logic for large native artifacts.
///
/// Why: On some environments (notably WSL2 / networked filesystems), Dart's
/// `File.copySync` can intermittently fail with `errno=5 (EIO)` while copying
/// large `.so` files. The error is OS-level, but we can make the build step
/// more resilient by:
/// 1) Preferring hard-links (fast, avoids extra I/O), and
/// 2) Retrying transient failures, and
/// 3) Falling back to a manual read/write copy if needed.

import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';

final _log = Logger('file_copy');

/// Installs [sourcePath] into [destinationPath].
///
/// Prefers a hard-link to reduce I/O. Falls back to copy.
void installFileSync({
  required String sourcePath,
  required String destinationPath,
  Logger? logger,
}) {
  final log = logger ?? _log;

  final src = File(sourcePath);
  final dst = File(destinationPath);

  dst.parent.createSync(recursive: true);

  // On Windows, rename-overwrite is not guaranteed to work. Delete the existing
  // destination first to keep behavior consistent across platforms.
  if (dst.existsSync()) {
    dst.deleteSync();
  }

  // Fast path: hard-link (avoids copying a potentially huge `.so`).
  try {
    _createHardLinkSync(sourcePath: sourcePath, destinationPath: destinationPath);
    _verifySameSizeSync(src: src, dst: dst);
    return;
  } on FileSystemException catch (e) {
    log.finer(
      'Hard-link failed, will copy instead. src=$sourcePath dst=$destinationPath '
      'error=${e.osError ?? e}',
    );
  }

  // Retry copySync for transient OS I/O failures.
  const maxAttempts = 3;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      src.copySync(destinationPath);
      _verifySameSizeSync(src: src, dst: dst);
      return;
    } on FileSystemException catch (e) {
      final errno = e.osError?.errorCode;
      final isLastAttempt = attempt == maxAttempts;

      // EIO is commonly transient on some filesystems/virtualized setups.
      final shouldRetry = errno == 5 && !isLastAttempt;
      if (shouldRetry) {
        final backoffMs = 200 * attempt;
        log.warning(
          'copySync failed with errno=5 (EIO) installing native artifact; '
          'retrying in ${backoffMs}ms. src=$sourcePath dst=$destinationPath',
        );
        sleep(Duration(milliseconds: backoffMs));
        continue;
      }

      if (errno == 5) {
        log.warning(
          'copySync repeatedly failed with errno=5 (EIO); falling back to manual '
          'copy. src=$sourcePath dst=$destinationPath',
        );
        _manualCopySync(src: src, dst: dst);
        _verifySameSizeSync(src: src, dst: dst);
        return;
      }

      rethrow;
    }
  }
}

void _createHardLinkSync({
  required String sourcePath,
  required String destinationPath,
}) {
  // Dart's `dart:io` does not expose a cross-platform hard-link API on `File`.
  // Use platform tools and fall back to copy on failure.
  //
  // Note: Hard-links require source and destination to be on the same filesystem.
  final ProcessResult result;
  try {
    if (Platform.isWindows) {
      // mklink is a cmd built-in: mklink /H <link> <target>
      result = Process.runSync(
        'cmd',
        ['/c', 'mklink', '/H', destinationPath, sourcePath],
        runInShell: true,
        stdoutEncoding: systemEncoding,
        stderrEncoding: systemEncoding,
      );
    } else {
      // ln <existing> <new>
      result = Process.runSync(
        'ln',
        [sourcePath, destinationPath],
        stdoutEncoding: systemEncoding,
        stderrEncoding: systemEncoding,
      );
    }
  } on ProcessException catch (e) {
    throw FileSystemException(
      'Failed to execute hard-link helper (${e.message})',
      destinationPath,
      OSError(e.message, e.errorCode),
    );
  }

  if (result.exitCode != 0) {
    final stderr = (result.stderr ?? '').toString().trim();
    throw FileSystemException(
      'Hard-link helper failed with exitCode=${result.exitCode}: $stderr',
      destinationPath,
    );
  }
}

void _manualCopySync({required File src, required File dst}) {
  // Use RandomAccessFile for explicit synchronous reads/writes.
  final input = src.openSync(mode: FileMode.read);
  try {
    final output = dst.openSync(mode: FileMode.write);
    try {
      // 8 MiB buffer balances syscall overhead vs memory usage.
      final buffer = Uint8List(8 * 1024 * 1024);
      while (true) {
        final read = input.readIntoSync(buffer);
        if (read == 0) {
          break;
        }
        output.writeFromSync(buffer, 0, read);
      }
      output.flushSync();
    } finally {
      output.closeSync();
    }
  } finally {
    input.closeSync();
  }
}

void _verifySameSizeSync({required File src, required File dst}) {
  final srcSize = src.statSync().size;
  final dstSize = dst.statSync().size;
  if (srcSize != dstSize) {
    throw FileSystemException(
      'Native artifact install produced a size mismatch (possible partial copy)',
      dst.path,
      OSError(
        'srcSize=$srcSize dstSize=$dstSize',
        5,
      ),
    );
  }
}
