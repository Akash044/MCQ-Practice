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

/// Top-level folders (subjects) shown on the home screen — subfolders
/// (chapters) live under [childFoldersProvider] so they only ever appear
/// nested inside their parent, never flattened in here too.
final foldersProvider = FutureProvider<List<Folder>>((ref) async {
  return withConnectivityCheck(
    () => ref.watch(supabaseServiceProvider).fetchRootFolders(),
  );
});

/// Subfolders (chapters) directly under the folder with id [parentId].
final childFoldersProvider = FutureProvider.family<List<Folder>, String>((
  ref,
  parentId,
) async {
  return withConnectivityCheck(
    () => ref.watch(supabaseServiceProvider).fetchChildFolders(parentId),
  );
});
