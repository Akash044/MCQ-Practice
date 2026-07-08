import '../models/question.dart';

/// Builds a random mix of [totalRequested] questions spread as evenly as
/// possible across the given exams (keyed by question_set_id).
///
/// The requested total is divided into per-exam quotas (base + a randomly
/// assigned extra one for the remainder). If an exam can't fill its quota,
/// the shortfall is redistributed round-robin across the other exams' spare
/// questions so the overall total is still met whenever the combined pool
/// is large enough — only falling short if every exam is exhausted.
List<Question> evenRandomMix(
  Map<String, List<Question>> questionsBySetId,
  int totalRequested,
) {
  final setIds = questionsBySetId.keys.toList();
  final k = setIds.length;
  if (k == 0 || totalRequested <= 0) return [];

  final base = totalRequested ~/ k;
  final remainder = totalRequested % k;
  final bonusOrder = [...setIds]..shuffle();
  final bonusSetIds = bonusOrder.take(remainder).toSet();

  final selected = <Question>[];
  final leftoverPools = <String, List<Question>>{};

  for (final setId in setIds) {
    final pool = [...questionsBySetId[setId]!]..shuffle();
    final quota = base + (bonusSetIds.contains(setId) ? 1 : 0);
    final take = quota.clamp(0, pool.length);
    selected.addAll(pool.take(take));
    leftoverPools[setId] = pool.skip(take).toList();
  }

  var stillNeeded = totalRequested - selected.length;
  var progress = true;
  while (stillNeeded > 0 && progress) {
    progress = false;
    for (final setId in setIds) {
      if (stillNeeded <= 0) break;
      final leftover = leftoverPools[setId]!;
      if (leftover.isNotEmpty) {
        selected.add(leftover.removeAt(0));
        stillNeeded--;
        progress = true;
      }
    }
  }

  selected.shuffle();
  return selected;
}
