import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:reader_app/src/rust/frb_generated.dart';
import 'package:reader_app/app/app_shell.dart';
import 'package:reader_app/data/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive
  await Hive.initFlutter();
  Hive.registerAdapter(BookAdapter());

  // Initialize repositories
  final bookRepository = BookRepository();
  await bookRepository.init();

  // Initialize Rust library
  String? initError;
  try {
    await RustLib.init();
  } catch (e) {
    initError = e.toString();
  }

  runApp(ReaderApp(initError: initError, bookRepository: bookRepository));
}

class ReaderApp extends StatelessWidget {
  final String? initError;
  final BookRepository bookRepository;

  const ReaderApp({super.key, this.initError, required this.bookRepository});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<BookRepository>.value(value: bookRepository),
      ],
      child: MaterialApp(
        title: 'Antigravity Reader',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.dark,
            surface: Colors.black,
          ),
          useMaterial3: true,
        ),
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
      ),
    );
  }
}
