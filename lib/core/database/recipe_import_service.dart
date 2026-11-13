import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/recipe.dart';
import '../../models/recipe_transfer.dart';

class RecipeImportSummary {
  int added = 0, skipped = 0, categories = 0, photos = 0;
  @override
  String toString() =>
      '新增 $added 道菜谱，跳过 $skipped 道已有菜谱，合并 $categories 个分类，恢复 $photos 张图片';
}

class RecipeImportService {
  RecipeImportService(this.db);
  final Database db;

  static Future<RecipeTransferData> read(String path) async {
    final file = File(path);
    if (await file.length() > 100 * 1024 * 1024) {
      throw const FormatException('文件超过 100 MB');
    }
    return compute(RecipeTransferData.decode, await file.readAsString());
  }

  Future<RecipeImportSummary> importData(RecipeTransferData data) async {
    final summary = RecipeImportSummary();
    final created = <File>[];
    final dir = Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'photos'),
    );
    await dir.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final restored = <String, String>{};
    var sequence = 0;
    Future<String?> image(String? key) async {
      if (key == null) return null;
      if (restored.containsKey(key)) return restored[key];
      final extension = p.extension(key).toLowerCase();
      final target = File(
        p.join(
          dir.path,
          'import_${stamp}_${sequence++}${RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension) ? extension : '.jpg'}',
        ),
      );
      created.add(target);
      await target.writeAsBytes(data.images[key]!, flush: true);
      summary.photos++;
      return restored[key] = target.path;
    }

    try {
      await db.transaction((tx) async {
        final localCategories = {
          for (final row in await tx.query('recipe_categories'))
            recipeCategoryKey(row['name'] as String): row['name'] as String,
        };
        Future<String> category(String name, {int? order}) async {
          if (name == '未分类') return name;
          final key = recipeCategoryKey(name);
          final existing = localCategories[key];
          if (existing != null) {
            if (order != null) {
              await tx.update(
                'recipe_categories',
                {'sort_order': order},
                where: 'name = ?',
                whereArgs: [existing],
              );
            }
            return existing;
          }
          await tx.insert('recipe_categories', {
            'name': name,
            'sort_order': order ?? 0,
          });
          return localCategories[key] = name;
        }

        for (final row in data.tables['recipe_categories']!) {
          await category(
            row['name'] as String,
            order: row['sort_order'] as int,
          );
          summary.categories++;
        }
        final existingRecipes = {
          for (final row in await tx.query('recipes', columns: ['id']))
            row['id'] as String,
        };
        final importedRecipes = <String>{};
        for (final row in data.tables['recipes']!) {
          final id = row['id'] as String;
          if (existingRecipes.contains(id)) {
            summary.skipped++;
            continue;
          }
          await tx.insert('recipes', {
            ...row,
            'category': await category(row['category'] as String),
            'cover_image_path': await image(row['cover_image_path'] as String?),
          });
          importedRecipes.add(id);
          summary.added++;
        }
        // Child IDs can collide across devices; remap them without changing local rows.
        final versions = <String, String>{};
        final used = <String, Set<String>>{};
        Future<String> childId(String table, String original) async {
          final taken = used[table] ??= {
            for (final row in await tx.query(table, columns: ['id']))
              row['id'] as String,
          };
          var id = original;
          while (!taken.add(id)) {
            id = 'import_${stamp}_${sequence++}';
          }
          return id;
        }

        for (final row in data.tables['recipe_versions']!) {
          if (!importedRecipes.contains(row['recipe_id'])) continue;
          final id = await childId('recipe_versions', row['id'] as String);
          versions[row['id'] as String] = id;
          await tx.insert('recipe_versions', {...row, 'id': id});
        }
        for (final table in [
          'ingredients',
          'cooking_steps',
          'finished_records',
        ]) {
          for (final row in data.tables[table]!) {
            final version = versions[row['version_id']];
            if (version == null) continue;
            final values = {
              ...row,
              'id': await childId(table, row['id'] as String),
              'version_id': version,
            };
            if (table == 'finished_records') {
              final paths = <String>[];
              for (final key in FinishedRecord.readImagePaths(row)) {
                paths.add((await image(key))!);
              }
              values['image_path'] = paths.firstOrNull;
              values['image_paths'] = jsonEncode(paths);
            }
            await tx.insert(table, values);
          }
        }
      });
      return summary;
    } catch (_) {
      for (final file in created) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {
          // Keep the original import error.
        }
      }
      rethrow;
    }
  }
}
