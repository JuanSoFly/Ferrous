import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/services/book_file_resolver.dart';
import 'package:reader_app/src/rust/api/cbz.dart' as cbz_api;
import 'package:reader_app/core/utils/performance.dart';
import 'cbz_cache_controller.dart';

class CbzPageController extends ChangeNotifier {
  final Book book;
  final BookRepository repository;
  
  int _pageCount = 0;
  int get pageCount => _pageCount;
  
  List<String> _pageNames = [];
  List<String> get pageNames => _pageNames;
  
  int _currentPage = 0;
  int get pageIndex => _currentPage;
  
  bool _isLoading = true;
  bool get isLoading => _isLoading;
  
  String? _error;
  String? get error => _error;
  
  String? _archivePath;
  String? get archivePath => _archivePath;
  
  ResolvedBookFile? _resolvedFile;
  ResolvedBookFile? get resolvedFile => _resolvedFile;
  
  final ScrollController scrollController = ScrollController();
  Timer? _progressSaveTimer;
  bool isRestoringScroll = false;
  
  ReadingMode _readingMode;
  ReadingMode get readingMode => _readingMode;
  
  double _lastScrollPosition;
  
  CbzCacheController? _cacheController;
  CbzCacheController? get cacheController => _cacheController;

  CbzPageController({
    required this.book,
    required this.repository,
  }) : _currentPage = book.currentPage,
       _readingMode = book.readingMode,
       _lastScrollPosition = book.scrollPosition {
    scrollController.addListener(_handleScrollUpdate);
  }

  @override
  void dispose() {
    _progressSaveTimer?.cancel();
    _saveProgressOnDispose();
    _cacheController?.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Future<void> loadDocument() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    await measureAsync('cbz_load_document', () async {
      try {
        final resolver = BookFileResolver();
        final resolved = await resolver.resolve(book);
        _resolvedFile = resolved;
        _archivePath = resolved.path;
        
        final names = await cbz_api.getCbzPageNames(path: resolved.path);
        
        _pageNames = names;
        _pageCount = names.length;
        
        _cacheController = CbzCacheController(
          archivePath: resolved.path,
          pageNames: names,
        );

        if (_currentPage >= names.length) {
          _currentPage = 0;
        }

        _isLoading = false;
        notifyListeners();
        
      } catch (e) {
        _error = e.toString();
        _isLoading = false;
        notifyListeners();
      }
    }, metadata: {'book_id': book.id});
  }

  void _handleScrollUpdate() {
    if (!isContinuousMode) return;
    if (isRestoringScroll) return;
    _scheduleContinuousProgressSave();
  }

  bool get isContinuousMode =>
      _readingMode == ReadingMode.verticalContinuous ||
      _readingMode == ReadingMode.webtoon ||
      _readingMode == ReadingMode.horizontalContinuous;

  void _scheduleContinuousProgressSave() {
    if (_progressSaveTimer?.isActive ?? false) return;
    _progressSaveTimer = Timer(const Duration(milliseconds: 350), () {
      saveContinuousProgress();
    });
  }

  void flushContinuousProgressSave() {
    _progressSaveTimer?.cancel();
    saveContinuousProgress();
  }

  void saveContinuousProgress() {
    if (!scrollController.hasClients) return;
    if (_pageCount == 0) return;
    
    final offset = scrollController.offset;
    final viewport = scrollController.position.viewportDimension;
    final approxIndex = viewport <= 0
        ? 0
        : (offset / viewport).round().clamp(0, _pageCount - 1);
        
    _lastScrollPosition = offset;
    _currentPage = approxIndex;
    
    repository.updateReadingProgress(
      book.id,
      currentPage: approxIndex,
      totalPages: _pageCount,
      scrollPosition: offset,
    );
    
    // We don't notifyListeners here to avoid jumps during scrolling
  }

  void restoreContinuousScroll() {
    if (!scrollController.hasClients) return;
    if (_lastScrollPosition <= 0 && _currentPage <= 0) return;

    isRestoringScroll = true;
    var attempts = 0;

    void tryRestore() {
      if (!scrollController.hasClients) {
        isRestoringScroll = false;
        return;
      }

      final position = scrollController.position;
      if (!position.hasContentDimensions) {
        attempts++;
        if (attempts < 5) {
          Future.delayed(const Duration(milliseconds: 50), tryRestore);
        } else {
          isRestoringScroll = false;
        }
        return;
      }

      final baseOffset = _lastScrollPosition > 0
          ? _lastScrollPosition
          : position.viewportDimension * _currentPage;
      final clamped = baseOffset.clamp(0.0, position.maxScrollExtent);
      
      if ((position.pixels - clamped).abs() > 1.0) {
        scrollController.jumpTo(clamped);
      }

      isRestoringScroll = false;
    }

    tryRestore();
  }

  void jumpToPage(int page) {
    if (page < 0 || page >= _pageCount) return;
    _currentPage = page;
    notifyListeners();
    
    repository.updateReadingProgress(
      book.id,
      currentPage: page,
      totalPages: _pageCount,
    );
  }

  void swipeToPage(int delta) {
    jumpToPage(_currentPage + delta);
  }

  void updateReadingMode(ReadingMode mode) {
    if (_readingMode == mode) return;
    
    // Save progress before switching
    if (isContinuousMode) {
      saveContinuousProgress();
    } else {
      repository.updateReadingProgress(
        book.id,
        currentPage: _currentPage,
        totalPages: _pageCount,
      );
    }
    
    _readingMode = mode;
    repository.updateReadingProgress(book.id, readingMode: mode);
    
    // If switching to continuous, handle scroll position
    if (isContinuousMode) {
       Future.delayed(const Duration(milliseconds: 50), () {
          if (!scrollController.hasClients) return;
          final viewport = scrollController.position.viewportDimension;
          final targetScroll = _currentPage * viewport;
          scrollController.jumpTo(targetScroll.clamp(0.0, scrollController.position.maxScrollExtent));
       });
    }
    
    notifyListeners();
  }

  void _saveProgressOnDispose() {
    if (isContinuousMode) {
      saveContinuousProgress();
    } else if (_pageCount > 0) {
      repository.updateReadingProgress(
        book.id,
        currentPage: _currentPage,
        totalPages: _pageCount,
      );
    }
  }

  void cleanupTempFile() {
    if (_resolvedFile == null || !_resolvedFile!.isTemp) return;
    try {
      File(_resolvedFile!.path).deleteSync();
    } catch (_) {}
  }
}
