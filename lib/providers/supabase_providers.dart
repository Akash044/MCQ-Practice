import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/folder.dart';
import '../services/supabase_service.dart';
import '../utils/network_error.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final supabaseServiceProvider = Provider<SupabaseService>((ref) {
  return SupabaseService(ref.watch(supabaseClientProvider));
});

final foldersProvider = FutureProvider<List<Folder>>((ref) async {
  return withConnectivityCheck(
    () => ref.watch(supabaseServiceProvider).fetchFolders(),
  );
});
