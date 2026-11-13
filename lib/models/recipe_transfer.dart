import 'dart:convert';
import 'dart:typed_data';

import 'recipe.dart';

// SQLite NOCASE only folds ASCII letters; non-ASCII names remain distinct.
String recipeCategoryKey(String name) =>
    name.replaceAllMapped(RegExp('[A-Z]'), (match) => match[0]!.toLowerCase());

class RecipeTransferData {
  RecipeTransferData._(this.tables, this.images);
  final Map<String, List<Map<String, Object?>>> tables;
  final Map<String, Uint8List> images;
  int get recipeCount => tables['recipes']!.length;
  int get versionCount => tables['recipe_versions']!.length;
  int get categoryCount => tables['recipe_categories']!.length;

  static RecipeTransferData decode(String text) {
    try {
      final root = jsonDecode(text) as Map<String, dynamic>;
      if (root['format'] != 'noodles.recipes' || root['version'] != 1) {
        throw const FormatException('请选择此应用导出的菜谱备份 JSON（版本 1）');
      }
      List<Map<String, Object?>> rows(String key) => (root[key] as List)
          .map((row) => Map<String, Object?>.from(row as Map))
          .toList();
      final categories = rows('categories');
      final names = <String>{};
      for (final row in categories) {
        final name = row['name'] as String;
        final order = row['sort_order'] as int;
        if (name.trim().isEmpty ||
            name == '未分类' ||
            order < 0 ||
            !names.add(recipeCategoryKey(name))) {
          throw const FormatException('菜谱分类名称或排序无效，或分类重复');
        }
      }
      final recipes = rows('recipes');
      final versions = rows('recipe_versions');
      for (final row in recipes) {
        if (row['is_favorite'] != 0 && row['is_favorite'] != 1) {
          throw const FormatException('菜谱收藏标记无效');
        }
      }
      for (final row in versions) {
        if ((row['version_number'] as int) < 1 ||
            (row['is_best'] != 0 && row['is_best'] != 1)) {
          throw const FormatException('烹饪版本编号或最佳版本标记无效');
        }
      }
      final tables = <String, List<Map<String, Object?>>>{
        'recipe_categories': [
          for (final row in categories)
            {'name': row['name'], 'sort_order': row['sort_order']},
        ],
        'recipes': [for (final row in recipes) Recipe.fromMap(row).toMap()],
        'recipe_versions': [
          for (final row in versions) RecipeVersion.fromMap(row).toMap(),
        ],
        'ingredients': [
          for (final row in rows('ingredients'))
            Ingredient.fromMap(row).toMap(),
        ],
        'cooking_steps': [
          for (final row in rows('cooking_steps'))
            CookingStep.fromMap(row).toMap(),
        ],
        'finished_records': [
          for (final row in rows('finished_records'))
            FinishedRecord.fromMap(row).toMap(),
        ],
      };
      final ids = <String, Set<String>>{};
      for (final entry in tables.entries.where(
        (entry) => entry.key != 'recipe_categories',
      )) {
        final seen = ids[entry.key] = <String>{};
        for (final row in entry.value) {
          final id = row['id'] as String;
          if (id.trim().isEmpty || !seen.add(id)) {
            throw const FormatException('菜谱备份含空白或重复 ID');
          }
          for (final field in ['title', 'category', 'name', 'content']) {
            if (row.containsKey(field) &&
                (row[field] as String).trim().isEmpty) {
              throw FormatException('菜谱备份的 $field 不能为空');
            }
          }
          if (row['sort_order'] case final int order when order < 0) {
            throw const FormatException('食材或步骤排序无效');
          }
          if (row['rating'] case final num rating when !rating.isFinite) {
            throw const FormatException('菜谱评分无效');
          }
        }
      }
      for (final row in tables['recipe_versions']!) {
        if (!ids['recipes']!.contains(row['recipe_id'])) {
          throw const FormatException('烹饪版本缺少对应菜谱');
        }
      }
      for (final table in [
        'ingredients',
        'cooking_steps',
        'finished_records',
      ]) {
        for (final row in tables[table]!) {
          if (!ids['recipe_versions']!.contains(row['version_id'])) {
            throw const FormatException('食材、步骤或成品记录缺少对应版本');
          }
        }
      }
      final images = <String, Uint8List>{};
      var total = 0;
      for (final entry in (root['images'] as Map).entries) {
        final key = entry.key as String;
        final encoded = entry.value as String;
        if (key.isEmpty || encoded.length > 28 * 1024 * 1024) {
          throw const FormatException('图片名称无效或图片过大');
        }
        final bytes = base64Decode(encoded);
        total += bytes.length;
        if (bytes.length > 20 * 1024 * 1024 || total > 65 * 1024 * 1024) {
          throw const FormatException('图片超过单张 20 MB 或合计 65 MB 限制');
        }
        images[key] = bytes;
      }
      void checkImage(String? path) {
        if (path != null && !images.containsKey(path)) {
          throw const FormatException('菜谱备份缺少引用的图片，请重新导出');
        }
      }

      for (final row in tables['recipes']!) {
        checkImage(row['cover_image_path'] as String?);
      }
      for (final row in tables['finished_records']!) {
        final paths = FinishedRecord.readImagePaths(row);
        if (paths.length > maxRecipeImages) {
          throw const FormatException('每个烹饪版本最多 5 张图片');
        }
        paths.forEach(checkImage);
      }
      return RecipeTransferData._(tables, images);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('菜谱备份格式无效或字段不完整，请重新导出');
    }
  }
}
