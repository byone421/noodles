import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/recipe.dart';

class RecipeRepository {
  RecipeRepository(this.db);
  final Database db;

  static Future<RecipeRepository> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final database = await openDatabase(p.join(dir.path, 'food_log.db'), version: 1, onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'), onCreate: (db, _) async {
      await db.execute('CREATE TABLE recipes (id TEXT PRIMARY KEY, title TEXT NOT NULL, category TEXT NOT NULL, description TEXT NOT NULL, cover_image_path TEXT, is_favorite INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)');
      await db.execute('CREATE TABLE recipe_versions (id TEXT PRIMARY KEY, recipe_id TEXT NOT NULL, version_number INTEGER NOT NULL, title TEXT NOT NULL, note TEXT NOT NULL, rating REAL, is_best INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, FOREIGN KEY(recipe_id) REFERENCES recipes(id) ON DELETE CASCADE)');
      await db.execute('CREATE TABLE ingredients (id TEXT PRIMARY KEY, version_id TEXT NOT NULL, name TEXT NOT NULL, amount TEXT NOT NULL, unit TEXT NOT NULL, sort_order INTEGER NOT NULL, FOREIGN KEY(version_id) REFERENCES recipe_versions(id) ON DELETE CASCADE)');
      await db.execute('CREATE TABLE cooking_steps (id TEXT PRIMARY KEY, version_id TEXT NOT NULL, content TEXT NOT NULL, sort_order INTEGER NOT NULL, FOREIGN KEY(version_id) REFERENCES recipe_versions(id) ON DELETE CASCADE)');
      await db.execute('CREATE TABLE finished_records (id TEXT PRIMARY KEY, version_id TEXT NOT NULL, image_path TEXT, rating REAL, note TEXT NOT NULL, next_improvement TEXT NOT NULL, created_at TEXT NOT NULL, FOREIGN KEY(version_id) REFERENCES recipe_versions(id) ON DELETE CASCADE)');
    });
    return RecipeRepository(database);
  }

  Future<List<Recipe>> listRecipes() async => (await db.query('recipes', orderBy: 'updated_at DESC')).map(Recipe.fromMap).toList();
  Future<Recipe?> getRecipe(String id) async { final rows = await db.query('recipes', where: 'id = ?', whereArgs: [id], limit: 1); return rows.isEmpty ? null : Recipe.fromMap(rows.first); }
  Future<List<RecipeVersion>> versions(String recipeId) async => (await db.query('recipe_versions', where: 'recipe_id = ?', whereArgs: [recipeId], orderBy: 'version_number DESC')).map(RecipeVersion.fromMap).toList();
  Future<VersionBundle?> bundle(String versionId) async { final v = await db.query('recipe_versions', where: 'id = ?', whereArgs: [versionId], limit: 1); if (v.isEmpty) return null; final ingredients = (await db.query('ingredients', where: 'version_id = ?', whereArgs: [versionId], orderBy: 'sort_order')).map(Ingredient.fromMap).toList(); final steps = (await db.query('cooking_steps', where: 'version_id = ?', whereArgs: [versionId], orderBy: 'sort_order')).map(CookingStep.fromMap).toList(); final records = await db.query('finished_records', where: 'version_id = ?', whereArgs: [versionId], orderBy: 'created_at DESC', limit: 1); return VersionBundle(version: RecipeVersion.fromMap(v.first), ingredients: ingredients, steps: steps, finishedRecord: records.isEmpty ? null : FinishedRecord.fromMap(records.first)); }

  Future<String> createRecipe({required String title, required String category, String description = '', String ingredientsText = '', String stepsText = ''}) async {
    final now = DateTime.now(); final recipeId = now.microsecondsSinceEpoch.toString(); final versionId = '${recipeId}_v1';
    await db.transaction((tx) async { await tx.insert('recipes', Recipe(id: recipeId, title: title, category: category, description: description, createdAt: now, updatedAt: now).toMap()); await tx.insert('recipe_versions', RecipeVersion(id: versionId, recipeId: recipeId, versionNumber: 1, title: '版本 1', note: '', createdAt: now, updatedAt: now).toMap()); await _replaceLists(tx, versionId, ingredientsText, stepsText); });
    return recipeId;
  }

  Future<String> saveVersion({required String recipeId, String? versionId, required String title, required String note, double? rating, required List<IngredientInput> ingredients, required List<String> steps, String? imagePath, String feedback = '', String improvement = ''}) async {
    final now = DateTime.now(); final id = versionId ?? '${now.microsecondsSinceEpoch}_v'; final existing = await versions(recipeId); RecipeVersion? previous; if (versionId != null) { for (final version in existing) { if (version.id == versionId) previous = version; } } final number = previous?.versionNumber ?? (existing.isEmpty ? 1 : existing.first.versionNumber + 1);
    final oldImages = await db.query('finished_records', columns: ['image_path'], where: 'version_id = ?', whereArgs: [id]);
    await db.transaction((tx) async { final version = RecipeVersion(id: id, recipeId: recipeId, versionNumber: number, title: title, note: note, rating: rating, isBest: previous?.isBest ?? false, createdAt: previous?.createdAt ?? now, updatedAt: now); if (previous == null) { await tx.insert('recipe_versions', version.toMap()); } else { await tx.update('recipe_versions', version.toMap(), where: 'id = ?', whereArgs: [id]); } await tx.delete('ingredients', where: 'version_id = ?', whereArgs: [id]); await tx.delete('cooking_steps', where: 'version_id = ?', whereArgs: [id]); await tx.delete('finished_records', where: 'version_id = ?', whereArgs: [id]); for (var i = 0; i < ingredients.length; i++) { final item = ingredients[i]; await tx.insert('ingredients', Ingredient(id: '${id}_i$i', versionId: id, name: item.name, amount: item.amount, unit: item.unit, sortOrder: i).toMap()); } for (var i = 0; i < steps.length; i++) { await tx.insert('cooking_steps', CookingStep(id: '${id}_s$i', versionId: id, content: steps[i], sortOrder: i).toMap()); } if (feedback.isNotEmpty || improvement.isNotEmpty || imagePath != null) { await tx.insert('finished_records', FinishedRecord(id: '${id}_record_${now.microsecondsSinceEpoch}', versionId: id, imagePath: imagePath, rating: rating, note: feedback, nextImprovement: improvement, createdAt: now).toMap()); } await tx.update('recipes', {'updated_at': now.toIso8601String()}, where: 'id = ?', whereArgs: [recipeId]); });
    await _deleteImages(oldImages);
    await _refreshCover(recipeId);
    return id;
  }

  Future<void> _replaceLists(DatabaseExecutor tx, String versionId, String ingredientsText, String stepsText) async { final ingredients = ingredientsText.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(); for (var i = 0; i < ingredients.length; i++) { final match = RegExp(r'^(.+?)\s+([0-9./]+|半|少量|适量)\s*(.*)$').firstMatch(ingredients[i]); await tx.insert('ingredients', Ingredient(id: '${versionId}_i$i', versionId: versionId, name: match?.group(1) ?? ingredients[i], amount: match?.group(2) ?? '', unit: match?.group(3) ?? '', sortOrder: i).toMap()); } final steps = stepsText.split('\n').map((s) => s.replaceFirst(RegExp(r'^\s*\d+[.)、]?\s*'), '').trim()).where((s) => s.isNotEmpty).toList(); for (var i = 0; i < steps.length; i++) { await tx.insert('cooking_steps', CookingStep(id: '${versionId}_s$i', versionId: versionId, content: steps[i], sortOrder: i).toMap()); } }
  Future<void> toggleFavorite(Recipe recipe) => db.update('recipes', {'is_favorite': recipe.isFavorite ? 0 : 1, 'updated_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [recipe.id]).then((_) {});
  Future<void> markBest(String versionId, String recipeId) async { await db.transaction((tx) async { await tx.update('recipe_versions', {'is_best': 0}, where: 'recipe_id = ?', whereArgs: [recipeId]); await tx.update('recipe_versions', {'is_best': 1}, where: 'id = ?', whereArgs: [versionId]); }); }
  Future<void> deleteVersion(String id) async { final rows = await db.query('finished_records', columns: ['image_path'], where: 'version_id = ?', whereArgs: [id]); final version = await db.query('recipe_versions', columns: ['recipe_id'], where: 'id = ?', whereArgs: [id], limit: 1); await db.delete('recipe_versions', where: 'id = ?', whereArgs: [id]); await _deleteImages(rows); if (version.isNotEmpty) await _refreshCover(version.first['recipe_id']! as String); }
  Future<void> deleteRecipe(String id) async { final rows = await db.rawQuery('SELECT f.image_path FROM finished_records f JOIN recipe_versions v ON v.id = f.version_id WHERE v.recipe_id = ?', [id]); await db.delete('recipes', where: 'id = ?', whereArgs: [id]); await _deleteImages(rows); }
  Future<void> _deleteImages(List<Map<String, Object?>> rows) async { for (final path in rows.map((r) => r['image_path'] as String?).whereType<String>().toSet()) { final references = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM finished_records WHERE image_path = ?', [path])) ?? 0; final file = File(path); if (references == 0 && await file.exists()) await file.delete(); } }
  Future<void> _refreshCover(String recipeId) async { final rows = await db.rawQuery('SELECT f.image_path FROM finished_records f JOIN recipe_versions v ON v.id = f.version_id WHERE v.recipe_id = ? AND f.image_path IS NOT NULL ORDER BY f.created_at DESC LIMIT 1', [recipeId]); await db.update('recipes', {'cover_image_path': rows.isEmpty ? null : rows.first['image_path']}, where: 'id = ?', whereArgs: [recipeId]); }
  Future<Map<String, int>> stats() async {
    final recipes = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM recipes')) ?? 0;
    final versions = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM recipe_versions')) ?? 0;
    final favorites = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM recipes WHERE is_favorite = 1')) ?? 0;
    final best = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM recipe_versions WHERE is_best = 1')) ?? 0;
    return {'recipes': recipes, 'versions': versions, 'favorites': favorites, 'best': best};
  }
  Future<void> clearAll() async { final rows = await db.query('finished_records', columns: ['image_path']); await db.transaction((tx) => tx.delete('recipes')); await _deleteImages(rows); }
}
