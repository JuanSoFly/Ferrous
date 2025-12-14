import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:reader_app/src/rust/api/library.dart'; // FRB generated
import 'package:state_notifier/state_notifier.dart';

class LibraryState {
  final bool isLoading;
  final List<BookMetadata> books;
  final String? error;

  const LibraryState({
    this.isLoading = false,
    this.books = const [],
    this.error,
  });

  LibraryState copyWith({
    bool? isLoading,
    List<BookMetadata>? books,
    String? error,
  }) {
    return LibraryState(
      isLoading: isLoading ?? this.isLoading,
      books: books ?? this.books,
      error: error,
    );
  }
}

class LibraryController extends StateNotifier<LibraryState> {
  LibraryController() : super(const LibraryState());

  Future<void> pickAndScanDirectory() async {
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory == null) {
        return; // User canceled
      }

      state = state.copyWith(isLoading: true, error: null);

      // Call Rust backend
      final books = await scanLibrary(rootPath: selectedDirectory);

      state = state.copyWith(
        isLoading: false,
        books: books,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  // Reload current directory if we stored it (not implemented yet for prototype)
}
