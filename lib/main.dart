import 'dart:async' show unawaited;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/folders/folder_list_screen.dart';
import 'services/supabase_service.dart';
import 'services/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // sqflite only ships a native implementation for Android/iOS; desktop dev
  // builds need the ffi-backed factory instead.
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await dotenv.load(fileName: '.env');
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // Flush any attempts that were queued locally while offline (see
  // lib/services/local_db.dart), now at startup and again whenever
  // connectivity comes back.
  final syncService = SyncService(SupabaseService(Supabase.instance.client));
  unawaited(syncService.flushPending());
  Connectivity().onConnectivityChanged.listen((results) {
    if (results.any((r) => r != ConnectivityResult.none)) {
      unawaited(syncService.flushPending());
    }
  });

  runApp(const ProviderScope(child: McqApp()));
}

class McqApp extends StatelessWidget {
  const McqApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = FThemes.zinc.light.touch;
    return MaterialApp(
      title: 'MCQ Practice',
      theme: theme.toApproximateMaterialTheme(),
      builder: (context, child) => FTheme(data: theme, child: FToaster(child: child!)),
      home: const FolderListScreen(),
    );
  }
}
