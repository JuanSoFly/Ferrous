import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ferrous/src/rust/frb_generated.dart';
import 'package:ferrous/src/rust/api/pdf.dart';
import 'package:ferrous/app/app_shell.dart';
import 'package:ferrous/core/services/diagnostic_logger.dart';
import 'package:ferrous/data/models/book_adapter.dart';
import 'package:ferrous/data/models/annotation_adapter.dart';
import 'package:ferrous/data/models/collection_adapter.dart';
import 'package:ferrous/data/repositories/book_repository.dart';
import 'package:ferrous/data/repositories/annotation_repository.dart';
import 'package:ferrous/data/repositories/collection_repository.dart';
import 'package:ferrous/data/repositories/library_location_repository.dart';
import 'package:ferrous/data/services/saf_service.dart';
import 'package:provider/provider.dart';
import 'package:flutter_state_notifier/flutter_state_notifier.dart';
import 'package:ferrous/features/settings/theme_controller.dart';
import 'package:ferrous/features/settings/dimension_controller.dart';
import 'package:ferrous/data/repositories/reader_theme_repository.dart';
import 'package:ferrous/data/models/reader_theme_config.dart';
import 'package:ferrous/features/settings/app_themes.dart';
import 'package:ferrous/core/constants/e_ink_tokens.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Wire global error handlers into DiagnosticLogger
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    DiagnosticLogger.instance.logError('Flutter', details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    DiagnosticLogger.instance.logError('PlatformDispatcher', error, stack);
    return false;
  };

  DiagnosticLogger.instance.log('App', 'Ferrous initializing');

  // Initialize Hive
  await Hive.initFlutter();
  Hive.registerAdapter(BookAdapter());
  Hive.registerAdapter(AnnotationAdapter());
  Hive.registerAdapter(CollectionAdapter());
  try {
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(ReaderThemeConfigAdapter());
    }
  } catch (e) {
    debugPrint('Failed to register ReaderThemeConfigAdapter: $e');
  }

  await _cleanupLinkedCacheFiles();

  // Initialize repositories
  final bookRepository = BookRepository();
  await bookRepository.init();
  
  final annotationRepository = AnnotationRepository();
  await annotationRepository.init();

  final collectionRepository = CollectionRepository();
  await collectionRepository.init();

  ReaderThemeRepository readerThemeRepository = ReaderThemeRepository();
  try {
    await readerThemeRepository.init();
  } catch (e) {
    debugPrint('ReaderThemeRepository init failed: $e. Using non-initialized repository.');
    // Repository will use its default config
  }

  final libraryLocationRepository = LibraryLocationRepository(
    bookRepository: bookRepository,
  );
  try {
    await libraryLocationRepository.init();
  } catch (e) {
    debugPrint('LibraryLocationRepository init failed: $e');
  }

  // Initialize Rust library
  String? initError;
  try {
    await RustLib.init();
    DiagnosticLogger.instance.log('RustLib', 'RustLib successfully initialized');
    
    // Initialize PDFium path on Android
    if (Platform.isAndroid) {
      try {
        final safService = SafService();
        final nativeLibDir = await safService.getNativeLibraryDir();
        if (nativeLibDir != null) {
          await initPdfium(path: nativeLibDir);
          DiagnosticLogger.instance.log('PDFium', 'PDFium successfully initialized');
        }
      } catch (e, stack) {
        DiagnosticLogger.instance.logError('PDFium', e, stack);
        debugPrint('Failed to initialize PDFium path: $e');
      }
    }
  } catch (e, stack) {
    initError = e.toString();
    DiagnosticLogger.instance.logError('RustLib', e, stack);
  }

  runApp(ReaderApp(
    initError: initError, 
    bookRepository: bookRepository,
    annotationRepository: annotationRepository,
    collectionRepository: collectionRepository,
    readerThemeRepository: readerThemeRepository,
    libraryLocationRepository: libraryLocationRepository,
  ));
}

Future<void> _cleanupLinkedCacheFiles() async {
  try {
    final dir = await getTemporaryDirectory();
    if (!await dir.exists()) return;
    await for (final entry in dir.list()) {
      if (entry is! File) continue;
      final name = entry.path.split(Platform.pathSeparator).last;
      if (name.startsWith('linked_')) {
        try {
          await entry.delete();
        } catch (_) {
          // Ignore cleanup failures
        }
      }
    }
  } catch (_) {
    // Ignore cleanup failures
  }
}

class ReaderApp extends StatelessWidget {
  final String? initError;
  final BookRepository bookRepository;
  final AnnotationRepository annotationRepository;
  final CollectionRepository collectionRepository;
  final ReaderThemeRepository readerThemeRepository;
  final LibraryLocationRepository libraryLocationRepository;

  const ReaderApp({
    super.key, 
    this.initError, 
    required this.bookRepository,
    required this.annotationRepository,
    required this.collectionRepository,
    required this.readerThemeRepository,
    required this.libraryLocationRepository,
  });


  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<BookRepository>.value(value: bookRepository),
        ChangeNotifierProvider<AnnotationRepository>.value(value: annotationRepository),
        ChangeNotifierProvider<CollectionRepository>.value(value: collectionRepository),
        ChangeNotifierProvider<LibraryLocationRepository>.value(value: libraryLocationRepository),
        StateNotifierProvider<DimensionController, DimensionState>(
          create: (_) => DimensionController(),
        ),
        StateNotifierProvider<ThemeController, AppTheme>(
          create: (context) {
            final dimensionController = context.read<DimensionController>();
            return ThemeController(
              onThemeChanged: (theme) {
                dimensionController.onThemeChanged(theme);
                if (theme == AppTheme.eInk) {
                  if (!readerThemeRepository.config.pageFlip || !readerThemeRepository.config.showBookSpine) {
                    readerThemeRepository.updateConfig(
                      readerThemeRepository.config.copyWith(
                        pageFlip: true,
                        showBookSpine: true,
                      ),
                    );
                  }
                }
              },
            );
          },
        ),
        ChangeNotifierProvider<ReaderThemeRepository>.value(value: readerThemeRepository),
      ],
      child: Builder(builder: (context) {
        final currentTheme = context.watch<AppTheme>();
        return MaterialApp(
          title: 'Ferrous',
          theme: AppThemes.themeData[currentTheme] ?? AppThemes.themeData[AppTheme.ferrous],
          builder: (context, child) {
            final appWidget = child ?? const SizedBox.shrink();
            if (currentTheme == AppTheme.eInk) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  appWidget,
                  const IgnorePointer(
                    child: RepaintBoundary(
                      child: EInkPaperNoiseOverlay(),
                    ),
                  ),
                ],
              );
            }
            return appWidget;
          },
          home: initError != null
              ? Scaffold(
                  body: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline,
                              size: 64, color: Colors.red),
                          const SizedBox(height: 16),
                          const Text('Rust Library Init Error',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text(initError!, textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ),
                )
              : const AppShell(),
        );
      }),
    );
  }
}
