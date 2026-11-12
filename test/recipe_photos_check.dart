import 'dart:io';

import 'package:noodles/models/recipe.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  final legacy = {
    'id': 'old',
    'version_id': 'v1',
    'image_path': 'old.jpg',
    'note': '保留反馈',
    'next_improvement': '少放盐',
    'created_at': '2026-11-12T00:00:00.000',
  };
  check(
    FinishedRecord.fromMap(legacy).imagePaths.single == 'old.jpg',
    'Read legacy photo',
  );
  check(
    FinishedRecord.fromMap({...legacy, 'image_paths': '[]'})
            .imagePaths
            .single ==
        'old.jpg',
    'Read migrated legacy photo',
  );
  final paths = List.generate(maxRecipeImages, (i) => '$i.jpg');
  final record = FinishedRecord(
    id: 'new',
    versionId: 'v2',
    imagePaths: paths,
    rating: 4.5,
    note: '反馈',
    nextImprovement: '改进',
    createdAt: DateTime(2026, 11, 12),
  );
  final restored = FinishedRecord.fromMap(record.toMap());
  check(
    restored.imagePaths.join(',') == paths.join(','),
    'Preserve all five photos in order',
  );
  check(restored.imagePath == paths.first, 'First photo is the cover');
  check(restored.rating == 4.5 && restored.note == '反馈', 'Preserve review');
  check(
    FinishedRecord.fromMap({
      ...record.toMap(),
      'image_path': null,
      'image_paths': '[]',
    }).imagePaths.isEmpty,
    'Remove all photos without restoring a stale cover',
  );
  const original = Ingredient(
    id: 'i1',
    versionId: 'v1',
    name: '低筋 面粉',
    amount: '一小碗',
    unit: '约100克',
    sortOrder: 0,
  );
  final ingredients = parseRecipeIngredients(
    '${formatRecipeIngredient(original)}\n番茄 2个\n盐 随便写',
    existing: [original],
  );
  check(
    ingredients.first.name == original.name &&
        ingredients.first.amount == original.amount &&
        ingredients.first.unit == original.unit,
    'Editing preserves existing ingredient fields',
  );
  check(
    ingredients[1].name == '番茄' &&
        ingredients[1].amount == '2个' &&
        ingredients[1].unit.isEmpty,
    'New and edited recipes parse ingredients alike',
  );
  check(ingredients[2].amount == '随便写', 'Parse arbitrary amount text');
  final steps = parseRecipeSteps('1. 洗菜\n180度烤20分钟\n2、装盘');
  check(
    steps.join('|') == '洗菜|180度烤20分钟|装盘',
    'Strip list markers without stripping temperatures',
  );
  check(
    parseRecipeSteps('1. 保留已有编号', existing: ['1. 保留已有编号']).single ==
        '1. 保留已有编号',
    'Preserve unchanged existing step',
  );
  check(
    parseRecipeSteps('洗菜\n沥干\n下锅', existing: ['洗菜\n沥干', '下锅']).length == 2,
    'Preserve existing multiline step boundaries when unchanged',
  );
  stdout.writeln(
    'PASS: legacy photos, five-photo round trip, first cover, removal, ingredients and steps',
  );
}
