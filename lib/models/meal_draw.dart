import 'dart:math';

import 'recipe.dart';

List<Recipe> drawMeal(
  List<Recipe> candidates, {
  required int count,
  List<String> previousIds = const [],
  Set<String> lockedIds = const {},
  Random? random,
}) {
  if (count <= 0) return [];
  final byId = {for (final recipe in candidates) recipe.id: recipe};
  final locked = previousIds
      .toSet()
      .where((id) => lockedIds.contains(id) && byId.containsKey(id))
      .take(count)
      .map((id) => byId[id]!)
      .toList();
  final kept = locked.map((recipe) => recipe.id).toSet();
  final previous = previousIds.toSet();
  final fresh =
      byId.values.where((recipe) => !previous.contains(recipe.id)).toList()
        ..shuffle(random);
  final repeats =
      byId.values
          .where(
            (recipe) =>
                previous.contains(recipe.id) && !kept.contains(recipe.id),
          )
          .toList()
        ..shuffle(random);
  return [
    ...locked,
    ...[...fresh, ...repeats].take(count - locked.length),
  ];
}
