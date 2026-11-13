import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../models/recipe.dart';
import 'json_backup.dart';

class RecipeExportService {
  RecipeExportService(this.db);
  final Database db;

  Future<bool> exportData() async =>
      saveJsonBackup(await createBackup(), filenamePrefix: '菜谱备份');

  Future<Map<String, Object?>> createBackup() async {
    final snapshot = await db.transaction((tx) async {
      final tables = <String, List<Map<String, Object?>>>{};
      for (final table in [
        'recipe_categories',
        'recipes',
        'recipe_versions',
        'ingredients',
        'cooking_steps',
        'finished_records',
      ]) {
        tables[table] = await tx.query(table);
      }
      return tables;
    });
    final images = <String, String>{};
    final references = <String, String>{};
    var total = 0;

    Future<String?> exportImage(String? path) async {
      if (path == null || path.isEmpty) return null;
      if (references.containsKey(path)) return references[path];
      final file = File(path);
      if (!await file.exists()) {
        throw const FileSystemException('菜谱图片缺失，备份未保存；请先移除失效图片');
      }
      final size = await file.length();
      total += size;
      if (size > 20 * 1024 * 1024 || total > 65 * 1024 * 1024) {
        throw const FormatException('图片过大，暂支持单张 20 MB、总计 65 MB 的备份');
      }
      final key = 'photo_${images.length}${p.extension(path)}';
      images[key] = base64Encode(await file.readAsBytes());
      references[path] = key;
      return key;
    }

    final recipes = <Map<String, Object?>>[];
    for (final row in snapshot['recipes']!) {
      recipes.add({
        ...row,
        'cover_image_path': await exportImage(
          row['cover_image_path'] as String?,
        ),
      });
    }
    final records = <Map<String, Object?>>[];
    for (final row in snapshot['finished_records']!) {
      final paths = <String>[];
      for (final path in FinishedRecord.readImagePaths(row)) {
        paths.add((await exportImage(path))!);
      }
      records.add({
        ...row,
        'image_path': paths.firstOrNull,
        'image_paths': jsonEncode(paths),
      });
    }
    return {
      'format': 'noodles.recipes',
      'version': 1,
      'categories': snapshot['recipe_categories'],
      'recipes': recipes,
      'recipe_versions': snapshot['recipe_versions'],
      'ingredients': snapshot['ingredients'],
      'cooking_steps': snapshot['cooking_steps'],
      'finished_records': records,
      'images': images,
    };
  }
}
