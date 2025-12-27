import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:reader_app/src/rust/frb_generated.dart';
import 'package:reader_app/app/app_shell.dart';
import 'package:reader_app/data/models/book_adapter.dart';
import 'package:reader_app/data/models/annotation_adapter.dart';
import 'package:reader_app/data/models/collection_adapter.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/repositories/annotation_repository.dart';
import 'package:reader_app/data/repositories/collection_repository.dart';
import 'package:provider/provider.dart';
import 'package:flutter_state_notifier/flutter_state_notifier.dart';
import 'package:reader_app/features/settings/theme_controller.dart';
import 'package:reader_app/data/repositories/reader_theme_repository.dart';
import 'package:reader_app/data/models/reader_theme_config.dart';
import 'package:reader_app/features/settings/app_themes.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  // Initialize Rust library
  String? initError;
  try {
    await RustLib.init();
  } catch (e) {
    initError = e.toString();
  }

  runApp(ReaderApp(
    initError: initError, 
    bookRepository: bookRepository,
    annotationRepository: annotationRepository,
    collectionRepository: collectionRepository,
    readerThemeRepository: readerThemeRepository,
  ));
}

Future<void> _cleanupLinkedCacheFiles() async {
  try {
    final dir = await getTemporaryDirectory();
    if (!await dir.exists()) return;
    final entries = dir.listSync();
    for (final entry in entries) {
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

  const ReaderApp({
    super.key, 
    this.initError, 
    required this.bookRepository,
    required this.annotationRepository,
    required this.collectionRepository,
    required this.readerThemeRepository,
  });


  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<BookRepository>.value(value: bookRepository),
        ChangeNotifierProvider<AnnotationRepository>.value(value: annotationRepository),
        ChangeNotifierProvider<CollectionRepository>.value(value: collectionRepository),
        StateNotifierProvider<ThemeController, AppTheme>(
          create: (_) => ThemeController(),
        ),
        ChangeNotifierProvider<ReaderThemeRepository>.value(value: readerThemeRepository),
      ],
      child: Builder(builder: (context) {
        final currentTheme = context.watch<AppTheme>();
        return MaterialApp(
          title: 'Ferrous',
          theme: AppThemes.themeData[currentTheme] ?? AppThemes.themeData[AppTheme.ferrous],
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
