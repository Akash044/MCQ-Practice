import 'package:flutter_tts/flutter_tts.dart';

/// Thin wrapper around [FlutterTts] used by the "listen & answer" exam mode
/// to read questions and answers aloud. Kept free of Riverpod so it's easy
/// to unit test.
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _configured = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _tts.awaitSpeakCompletion(true);
    _configured = true;
  }

  /// Speaks [text] and completes once playback finishes (or is [stop]ped).
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _ensureConfigured();
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();
}
