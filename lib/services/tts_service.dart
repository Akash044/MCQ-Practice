import 'package:flutter_tts/flutter_tts.dart';

/// Thin wrapper around [FlutterTts] used by the "listen & answer" exam mode
/// to read questions and answers aloud. Kept free of Riverpod so it's easy
/// to unit test.
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _awaitConfigured = false;
  bool _autoVoiceAttempted = false;

  Future<void> _ensureAwaitConfigured() async {
    if (_awaitConfigured) return;
    await _tts.awaitSpeakCompletion(true);
    _awaitConfigured = true;
  }

  /// Every voice this device's TTS engine exposes, normalized to
  /// `{'name': ..., 'locale': ...}` maps — the shape [setVoice] expects.
  /// Not every platform/engine supports listing voices, in which case this
  /// returns an empty list rather than throwing.
  Future<List<Map<String, String>>> listVoices() async {
    try {
      final voices = await _tts.getVoices as List<dynamic>?;
      if (voices == null) return [];
      return [
        for (final raw in voices)
          if (raw is Map)
            {
              'name': '${raw['name'] ?? ''}',
              'locale': '${raw['locale'] ?? ''}',
            },
      ].where((v) => v['name']!.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  /// Switches the active voice — takes effect for every [speak] call after
  /// this until changed again.
  Future<void> setVoice(Map<String, String> voice) async {
    try {
      await _tts.setVoice(voice);
    } catch (_) {
      // Not every platform/engine supports explicit voice selection.
    }
  }

  /// Best-effort guess at a male-sounding voice, used only as a first-run
  /// default until the user explicitly picks one via the voice chooser —
  /// TTS engines don't reliably expose gender, so this is a heuristic on
  /// the voice name, not a guarantee.
  Future<void> selectDefaultMaleVoice() async {
    if (_autoVoiceAttempted) return;
    _autoVoiceAttempted = true;
    try {
      final voices = await _tts.getVoices as List<dynamic>?;
      if (voices == null || voices.isEmpty) return;

      Map<String, String>? bestMatch;
      var bestIsEnglish = false;
      for (final raw in voices) {
        if (raw is! Map) continue;
        final name = '${raw['name'] ?? ''}'.toLowerCase();
        final gender = '${raw['gender'] ?? ''}'.toLowerCase();
        final locale = '${raw['locale'] ?? ''}'.toLowerCase();
        final looksMale =
            (gender.contains('male') && !gender.contains('female')) ||
            (gender.isEmpty &&
                name.contains('male') &&
                !name.contains('female'));
        if (!looksMale) continue;

        final isEnglish = locale.startsWith('en');
        if (bestMatch == null || (isEnglish && !bestIsEnglish)) {
          bestMatch = {'name': '${raw['name']}', 'locale': '${raw['locale']}'};
          bestIsEnglish = isEnglish;
          if (isEnglish) break;
        }
      }

      if (bestMatch != null) {
        await _tts.setVoice(bestMatch);
      } else {
        await _tts.setPitch(0.85);
      }
    } catch (_) {
      // Voice listing/selection isn't supported on every platform/engine —
      // better to keep the default voice than fail playback over this.
    }
  }

  /// Speaks [text] and completes once playback finishes (or is [stop]ped).
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _ensureAwaitConfigured();
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();
}
