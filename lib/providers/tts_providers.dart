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

const _voicePrefsKey = 'ttsVoice';

/// The user's explicitly-chosen TTS voice (name + locale, as returned by
/// [TtsService.listVoices]) — null until they pick one via the voice
/// chooser, in which case [TtsService.selectDefaultMaleVoice]'s heuristic
/// guess is used instead. Persisted so the choice survives app restarts.
class TtsVoiceNotifier extends StateNotifier<Map<String, String>?> {
  TtsVoiceNotifier(this._prefs, Map<String, String>? initial) : super(initial);

  final SharedPreferences _prefs;

  void setVoice(Map<String, String> voice) {
    state = voice;
    _prefs.setString(_voicePrefsKey, '${voice['name']}|${voice['locale']}');
  }
}

/// Overridden in main() once the persisted preference has been read from
/// disk, same as themeModeProvider.
final ttsVoiceProvider =
    StateNotifierProvider<TtsVoiceNotifier, Map<String, String>?>((ref) {
      throw UnimplementedError('ttsVoiceProvider must be overridden in main()');
    });

Map<String, String>? loadInitialTtsVoice(SharedPreferences prefs) {
  final raw = prefs.getString(_voicePrefsKey);
  if (raw == null) return null;
  final parts = raw.split('|');
  if (parts.length != 2) return null;
  return {'name': parts[0], 'locale': parts[1]};
}
