import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart' show Brightness;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'themeMode';

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._prefs, ThemeMode initial) : super(initial);

  final SharedPreferences _prefs;

  void setMode(ThemeMode mode) {
    state = mode;
    _prefs.setString(_prefsKey, mode.name);
  }

  /// Flips between light and dark, given the currently *resolved* brightness
  /// (which may come from [ThemeMode.system] rather than an explicit choice).
  void toggle(Brightness resolved) {
    setMode(resolved == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
  }
}

/// Overridden in main() once the persisted preference has been read from
/// disk, so the app never flashes the wrong theme on startup.
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((
  ref,
) {
  throw UnimplementedError('themeModeProvider must be overridden in main()');
});

ThemeMode loadInitialThemeMode(SharedPreferences prefs) {
  final saved = prefs.getString(_prefsKey);
  return ThemeMode.values.firstWhere(
    (m) => m.name == saved,
    orElse: () => ThemeMode.system,
  );
}
