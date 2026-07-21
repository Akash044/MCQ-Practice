import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/tts_service.dart';

final ttsServiceProvider = Provider<TtsService>((ref) => TtsService());

const _answerDelayPrefsKey = 'ttsAnswerDelaySeconds';
const defaultTtsAnswerDelaySeconds = 5;

/// How long the "listen & answer" playback waits after reading a question
/// and its options aloud, before reading the correct answer — gives the
/// user time to answer out loud first. Persisted so it's remembered as the
/// default the next time playback starts.
class TtsAnswerDelayNotifier extends StateNotifier<int> {
  TtsAnswerDelayNotifier(this._prefs, int initial) : super(initial);

  final SharedPreferences _prefs;

  void setSeconds(int seconds) {
    state = seconds;
    _prefs.setInt(_answerDelayPrefsKey, seconds);
  }
}

/// Overridden in main() once the persisted preference has been read from
/// disk, same as themeModeProvider.
final ttsAnswerDelaySecondsProvider =
    StateNotifierProvider<TtsAnswerDelayNotifier, int>((ref) {
      throw UnimplementedError(
        'ttsAnswerDelaySecondsProvider must be overridden in main()',
      );
    });

int loadInitialTtsAnswerDelaySeconds(SharedPreferences prefs) {
  return prefs.getInt(_answerDelayPrefsKey) ?? defaultTtsAnswerDelaySeconds;
}
