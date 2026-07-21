import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../models/question.dart';
import '../../models/question_set.dart';
import '../../providers/exam_providers.dart';
import '../../providers/tts_providers.dart';
import '../../widgets/error_state.dart';

enum _Phase { question, waitingForAnswer, answer, done }

const _correctColor = Color(0xFF16A34A);
const _interQuestionGapSeconds = 2;

/// Hands-free "listen & answer" playback: reads each question and its
/// options aloud, waits [answerDelaySeconds] (long enough to answer out
/// loud), then reads the correct answer, before moving on to the next
/// question — the audio-flashcard companion to [ExamRunnerScreen], with no
/// scoring or attempt recorded.
class ListenPlaybackScreen extends ConsumerStatefulWidget {
  const ListenPlaybackScreen({
    super.key,
    required this.questionSet,
    required this.answerDelaySeconds,
  });

  final QuestionSet questionSet;
  final int answerDelaySeconds;

  @override
  ConsumerState<ListenPlaybackScreen> createState() =>
      _ListenPlaybackScreenState();
}

class _ListenPlaybackScreenState extends ConsumerState<ListenPlaybackScreen> {
  List<Question>? _questions;
  int _index = 0;
  bool _playing = false;
  _Phase _phase = _Phase.question;
  int _secondsLeft = 0;

  /// Bumped on every pause/skip/dispose so an in-flight playback loop can
  /// notice it's been superseded and stop advancing on its own.
  int _runToken = 0;

  @override
  void dispose() {
    _runToken++;
    ref.read(ttsServiceProvider).stop();
    super.dispose();
  }

  void _startIfNeeded(List<Question> questions) {
    if (_questions != null) return;
    _questions = questions;
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  String _optionsSpeech(Question q) {
    final letters = List.generate(
      q.options.length,
      (i) => String.fromCharCode(65 + i),
    );
    return [
      for (var i = 0; i < q.options.length; i++) '${letters[i]}. ${q.options[i]}',
    ].join('. ');
  }

  Future<void> _play() async {
    if (_playing) return;
    setState(() => _playing = true);
    await _runFrom(_index, ++_runToken);
  }

  Future<void> _runFrom(int index, int token) async {
    final questions = _questions;
    if (questions == null) return;
    while (index < questions.length) {
      if (token != _runToken || !mounted) return;
      setState(() {
        _index = index;
        _phase = _Phase.question;
      });
      final question = questions[index];
      final tts = ref.read(ttsServiceProvider);
      await tts.speak('${question.questionText}. ${_optionsSpeech(question)}');
      if (token != _runToken || !mounted) return;

      setState(() => _phase = _Phase.waitingForAnswer);
      await _countdown(widget.answerDelaySeconds, token);
      if (token != _runToken || !mounted) return;

      setState(() => _phase = _Phase.answer);
      final letters = List.generate(
        question.options.length,
        (i) => String.fromCharCode(65 + i),
      );
      await tts.speak(
        'The correct answer is ${letters[question.correctAnswer]}. '
        '${question.options[question.correctAnswer]}',
      );
      if (token != _runToken || !mounted) return;

      await _countdown(_interQuestionGapSeconds, token, silent: true);
      if (token != _runToken || !mounted) return;
      index += 1;
    }
    if (token == _runToken && mounted) {
      setState(() {
        _phase = _Phase.done;
        _playing = false;
      });
    }
  }

  Future<void> _countdown(int seconds, int token, {bool silent = false}) async {
    for (var remaining = seconds; remaining > 0; remaining--) {
      if (!silent && mounted) setState(() => _secondsLeft = remaining);
      await Future.delayed(const Duration(seconds: 1));
      if (token != _runToken || !mounted) return;
    }
    if (!silent && mounted) setState(() => _secondsLeft = 0);
  }

  void _pause() {
    _runToken++;
    ref.read(ttsServiceProvider).stop();
    setState(() => _playing = false);
  }

  void _seek(int delta) {
    final questions = _questions;
    if (questions == null) return;
    final target = (_index + delta).clamp(0, questions.length - 1);
    _runToken++;
    ref.read(ttsServiceProvider).stop();
    setState(() {
      _index = target;
      _playing = true;
    });
    _runFrom(target, _runToken);
  }

  String _phaseLabel() {
    switch (_phase) {
      case _Phase.question:
        return 'Reading question…';
      case _Phase.waitingForAnswer:
        return 'Your turn — answer out loud ($_secondsLeft)';
      case _Phase.answer:
        return 'Reading answer…';
      case _Phase.done:
        return "That's the last question.";
    }
  }

  @override
  Widget build(BuildContext context) {
    final questionsAsync = ref.watch(
      questionsForSetProvider(widget.questionSet.id),
    );

    return FScaffold(
      header: FHeader.nested(
        title: Text('Listen: ${widget.questionSet.title}'),
        prefixes: [
          FHeaderAction.back(
            onPress: () {
              _runToken++;
              ref.read(ttsServiceProvider).stop();
              Navigator.pop(context);
            },
          ),
        ],
      ),
      child: questionsAsync.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (err, stack) =>
            ErrorState(error: err, label: 'Failed to load questions'),
        data: (questions) {
          if (questions.isEmpty) {
            return const Center(child: Text('This exam has no questions.'));
          }
          _startIfNeeded(questions);
          final current = questions[_index.clamp(0, questions.length - 1)];
          final revealed =
              _phase == _Phase.answer || _phase == _Phase.done;

          return SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Question ${_index + 1} / ${questions.length}',
                  style: context.theme.typography.sm,
                ),
                const SizedBox(height: 4),
                Text(_phaseLabel(), style: context.theme.typography.xs),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(current.questionText),
                        const SizedBox(height: 12),
                        FTileGroup(
                          children: [
                            for (var i = 0; i < current.options.length; i++)
                              FTile(
                                title: Text(current.options[i]),
                                suffix: revealed && i == current.correctAnswer
                                    ? const Icon(
                                        FIcons.circleCheck,
                                        color: _correctColor,
                                      )
                                    : null,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FButton(
                        variant: FButtonVariant.outline,
                        onPress: _index > 0 ? () => _seek(-1) : null,
                        prefix: const Icon(FIcons.skipBack),
                        child: const Text('Previous'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FButton(
                        onPress: _playing ? _pause : _play,
                        prefix: Icon(
                          _playing ? FIcons.pause : FIcons.play,
                        ),
                        child: Text(_playing ? 'Pause' : 'Play'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FButton(
                        variant: FButtonVariant.outline,
                        onPress: _index < questions.length - 1
                            ? () => _seek(1)
                            : null,
                        suffix: const Icon(FIcons.skipForward),
                        child: const Text('Next'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
