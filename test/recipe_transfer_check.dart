// Run directly with `dart test/recipe_transfer_check.dart` (no Flutter runtime).
// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:noodles/models/recipe_transfer.dart';

Map<String, Object?> recipeBackupFixture() => {
  'format': 'noodles.recipes',
  'version': 1,
  'categories': [
    {'name': '面食', 'sort_order': 8},
  ],
  'recipes': [
    {
      'id': 'r1',
      'title': '番茄面',
      'category': '面食',
      'description': '家常',
      'cover_image_path': 'photo.jpg',
      'is_favorite': 1,
      'created_at': '2026-11-12T10:00:00.000',
      'updated_at': '2026-11-12T11:00:00.000',
    },
  ],
  'recipe_versions': [
    for (var i = 1; i <= 2; i++)
      {
        'id': 'v$i',
        'recipe_id': 'r1',
        'version_number': i,
        'title': '版本 $i',
        'note': '改良',
        'rating': 4.5,
        'is_best': i == 1 ? 1 : 0,
        'created_at': '2026-11-12T10:00:00.000',
        'updated_at': '2026-11-12T11:00:00.000',
      },
  ],
  'ingredients': [
    {
      'id': 'i1',
      'version_id': 'v1',
      'name': '面条',
      'amount': '200',
      'unit': '克',
      'sort_order': 0,
    },
  ],
  'cooking_steps': [
    {'id': 's1', 'version_id': 'v2', 'content': '煮面', 'sort_order': 0},
  ],
  'finished_records': [
    for (var i = 1; i <= 2; i++)
      {
        'id': 'f$i',
        'version_id': 'v$i',
        'image_path': 'photo.jpg',
        'image_paths': i == 1 ? '[]' : '["photo.jpg"]',
        'rating': 4.5,
        'note': '好吃',
        'next_improvement': '少盐',
        'created_at': '2026-11-12T10:00:00.000',
      },
  ],
  'images': {
    'photo.jpg': base64Encode([1, 2, 3, 4]),
  },
};

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

void main() {
  final data = RecipeTransferData.decode(jsonEncode(recipeBackupFixture()));
  check(
    data.recipeCount == 1 && data.versionCount == 2 && data.categoryCount == 1,
    'Counts',
  );
  check(data.tables['recipes']!.single['is_favorite'] == 1, 'Favorite');
  check(data.tables['recipe_versions']!.first['is_best'] == 1, 'Best version');
  check(data.tables['ingredients']!.single['unit'] == '克', 'Ingredient fields');
  check(
    data.tables['finished_records']!.first['image_paths'] == '["photo.jpg"]',
    'Legacy photo fallback',
  );
  check(data.images['photo.jpg']!.join(',') == '1,2,3,4', 'Embedded bytes');
  final unicode = recipeBackupFixture();
  unicode['categories'] = [
    {'name': 'Ä', 'sort_order': 1},
    {'name': 'ä', 'sort_order': 2},
  ];
  check(
    RecipeTransferData.decode(jsonEncode(unicode)).categoryCount == 2,
    'Distinct Unicode categories must match SQLite NOCASE',
  );
  check(recipeCategoryKey('AÄ') == 'aÄ', 'Only ASCII case folds');

  var rejected = 0;
  void rejects(void Function(Map<String, Object?>) change) {
    final root = recipeBackupFixture();
    change(root);
    try {
      RecipeTransferData.decode(jsonEncode(root));
    } on FormatException {
      rejected++;
      return;
    }
    throw StateError('Invalid backup was accepted');
  }

  rejects((root) => root['format'] = 'noodles.inventory');
  rejects((root) => root['version'] = 2);
  rejects((root) => root.remove('recipes'));
  rejects(
    (root) => (root['recipes'] as List).add((root['recipes'] as List).first),
  );
  rejects(
    (root) => ((root['recipe_versions'] as List).first as Map)['recipe_id'] =
        'missing',
  );
  rejects(
    (root) =>
        ((root['ingredients'] as List).first as Map)['version_id'] = 'missing',
  );
  rejects((root) => root['images'] = <String, String>{});
  rejects((root) => root['images'] = {'photo.jpg': 'bad base64!!'});
  rejects(
    (root) => ((root['finished_records'] as List).first as Map)['image_paths'] =
        jsonEncode(List.filled(6, 'photo.jpg')),
  );
  rejects(
    (root) => ((root['categories'] as List).first as Map)['sort_order'] = -1,
  );
  rejects(
    (root) =>
        ((root['recipes'] as List).first as Map)['created_at'] = 'invalid',
  );
  final empty = recipeBackupFixture();
  for (final key in [
    'recipes',
    'recipe_versions',
    'ingredients',
    'cooking_steps',
    'finished_records',
  ]) {
    empty[key] = <Object>[];
  }
  empty['images'] = <String, String>{};
  check(
    RecipeTransferData.decode(jsonEncode(empty)).recipeCount == 0,
    'Empty backup',
  );
  print(
    'PASS: recipe fields, relationships, photos, empty backup and $rejected invalid backups',
  );
}
