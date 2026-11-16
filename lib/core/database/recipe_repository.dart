import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/recipe.dart';
import 'accounting_repository.dart';
import 'inventory_repository.dart';

class RecipeRepository {
  RecipeRepository(this.db);
  final Database db;

  static Future<RecipeRepository> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final database = await openDatabase(
      p.join(dir.path, 'food_log.db'),
      version: 8,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) await InventoryRepository.createTables(db);
        if (oldVersion < 3) await _createRecipeCategories(db);
        if (oldVersion == 3) {
          await db.execute(
            'ALTER TABLE recipe_categories ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion >= 2 && oldVersion < 5) {
          await db.execute(
            'ALTER TABLE inventory_items ADD COLUMN updated_at TEXT',
          );
        }
        if (oldVersion < 6) {
          await db.execute(
            "ALTER TABLE finished_records ADD COLUMN image_paths TEXT NOT NULL DEFAULT '[]'",
          );
        }
        if (oldVersion < 7) await AccountingRepository.createTables(db);
        if (oldVersion >= 7 && oldVersion < 8) {
          await db.execute(
            'ALTER TABLE account_categories ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0',
          );
        }
      },
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE recipes (id TEXT PRIMARY KEY, title TEXT NOT NULL, category TEXT NOT NULL, description TEXT NOT NULL, cover_image_path TEXT, is_favorite INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE recipe_versions (id TEXT PRIMARY KEY, recipe_id TEXT NOT NULL, version_number INTEGER NOT NULL, title TEXT NOT NULL, note TEXT NOT NULL, rating REAL, is_best INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, FOREIGN KEY(recipe_id) REFERENCES recipes(id) ON DELETE CASCADE)',
        );
        await db.execute(
          'CREATE TABLE ingredients (id TEXT PRIMARY KEY, version_id TEXT NOT NULL, name TEXT NOT NULL, amount TEXT NOT NULL, unit TEXT NOT NULL, sort_order INTEGER NOT NULL, FOREIGN KEY(version_id) REFERENCES recipe_versions(id) ON DELETE CASCADE)',
        );
        await db.execute(
          'CREATE TABLE cooking_steps (id TEXT PRIMARY KEY, version_id TEXT NOT NULL, content TEXT NOT NULL, sort_order INTEGER NOT NULL, FOREIGN KEY(version_id) REFERENCES recipe_versions(id) ON DELETE CASCADE)',
        );
        await db.execute(
          "CREATE TABLE finished_records (id TEXT PRIMARY KEY, version_id TEXT NOT NULL, image_path TEXT, image_paths TEXT NOT NULL DEFAULT '[]', rating REAL, note TEXT NOT NULL, next_improvement TEXT NOT NULL, created_at TEXT NOT NULL, FOREIGN KEY(version_id) REFERENCES recipe_versions(id) ON DELETE CASCADE)",
        );
        await InventoryRepository.createTables(db);
        await AccountingRepository.createTables(db);
        await _createRecipeCategories(db);
      },
    );
    return RecipeRepository(database);
  }

  static Future<void> _createRecipeCategories(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE recipe_categories (name TEXT PRIMARY KEY COLLATE NOCASE NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0)',
    );
    for (final name in ['家常菜', '快手菜', '面食', '汤羹', '烘焙']) {
      await db.insert('recipe_categories', {'name': name});
    }
    await db.execute(
      "INSERT OR IGNORE INTO recipe_categories(name) SELECT DISTINCT TRIM(category) FROM recipes WHERE TRIM(category) != '' AND TRIM(category) != '未分类'",
    );
    await db.execute(
      "UPDATE recipes SET category = (SELECT c.name FROM recipe_categories c WHERE lower(trim(recipes.category)) = lower(c.name) LIMIT 1) WHERE EXISTS (SELECT 1 FROM recipe_categories c WHERE lower(trim(recipes.category)) = lower(c.name))",
    );
    await db.execute(
      "UPDATE recipes SET category = '未分类' WHERE trim(category) IN ('', '未分类')",
    );
  }

  Future<Map<String, int>> listRecipeCategoryOrders() async => {
    for (final row in await db.query(
      'recipe_categories',
      orderBy: 'sort_order, rowid',
    ))
      row['name'] as String: row['sort_order'] as int,
  };

  Future<List<String>> listRecipeCategories() async =>
      (await listRecipeCategoryOrders()).keys.toList();

  Future<void> saveRecipeCategory(
    String name, {
    String? previous,
    int? sortOrder,
  }) async {
    final value = name.trim();
    if (value.isEmpty || value == '未分类')
      throw ArgumentError('请输入分类名称，“未分类”为保留名称');
    if (sortOrder != null && (sortOrder < 0 || sortOrder > 999999999)) {
      throw ArgumentError('排序须为 0–999999999 的整数');
    }
    await db.transaction((tx) async {
      final duplicates = await tx.query(
        'recipe_categories',
        where: 'name = ? AND name != ?',
        whereArgs: [value, previous ?? ''],
      );
      if (duplicates.isNotEmpty) throw ArgumentError('该分类已存在');
      if (previous == null) {
        await tx.insert('recipe_categories', {
          'name': value,
          'sort_order': sortOrder ?? 0,
        });
      } else {
        await tx.update(
          'recipe_categories',
          {'name': value, if (sortOrder != null) 'sort_order': sortOrder},
          where: 'name = ?',
          whereArgs: [previous],
        );
        await tx.update(
          'recipes',
          {'category': value},
          where: 'category = ?',
          whereArgs: [previous],
        );
      }
    });
  }

  Future<void> deleteRecipeCategory(String name) async {
    await db.transaction((tx) async {
      await tx.update(
        'recipes',
        {'category': '未分类'},
        where: 'category = ?',
        whereArgs: [name],
      );
      await tx.delete(
        'recipe_categories',
        where: 'name = ?',
        whereArgs: [name],
      );
    });
  }

  Future<List<Recipe>> listRecipes() async => (await db.query(
    'recipes',
    orderBy: 'updated_at DESC',
  )).map(Recipe.fromMap).toList();
  Future<Recipe?> getRecipe(String id) async {
    final rows = await db.query(
      'recipes',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Recipe.fromMap(rows.first);
  }

  Future<List<RecipeVersion>> versions(String recipeId) async =>
      (await db.query(
        'recipe_versions',
        where: 'recipe_id = ?',
        whereArgs: [recipeId],
        orderBy: 'version_number DESC',
      )).map(RecipeVersion.fromMap).toList();
  Future<VersionBundle?> bundle(String versionId) async {
    final v = await db.query(
      'recipe_versions',
      where: 'id = ?',
      whereArgs: [versionId],
      limit: 1,
    );
    if (v.isEmpty) return null;
    final ingredients = (await db.query(
      'ingredients',
      where: 'version_id = ?',
      whereArgs: [versionId],
      orderBy: 'sort_order',
    )).map(Ingredient.fromMap).toList();
    final steps = (await db.query(
      'cooking_steps',
      where: 'version_id = ?',
      whereArgs: [versionId],
      orderBy: 'sort_order',
    )).map(CookingStep.fromMap).toList();
    final records = await db.query(
      'finished_records',
      where: 'version_id = ?',
      whereArgs: [versionId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    return VersionBundle(
      version: RecipeVersion.fromMap(v.first),
      ingredients: ingredients,
      steps: steps,
      finishedRecord: records.isEmpty
          ? null
          : FinishedRecord.fromMap(records.first),
    );
  }

  Future<String> createRecipe({
    required String title,
    required String category,
    String description = '',
    String ingredientsText = '',
    String stepsText = '',
    List<String> imagePaths = const [],
    double? rating,
    String feedback = '',
    String improvement = '',
  }) async {
    _validateImages(imagePaths);
    final categories = await listRecipeCategories();
    if (!categories.contains(category)) category = '未分类';
    final now = DateTime.now();
    final recipeId = now.microsecondsSinceEpoch.toString();
    final versionId = '${recipeId}_v1';
    await db.transaction((tx) async {
      await tx.insert(
        'recipes',
        Recipe(
          id: recipeId,
          title: title,
          category: category,
          description: description,
          coverImagePath: imagePaths.firstOrNull,
          createdAt: now,
          updatedAt: now,
        ).toMap(),
      );
      await tx.insert(
        'recipe_versions',
        RecipeVersion(
          id: versionId,
          recipeId: recipeId,
          versionNumber: 1,
          title: '版本 1',
          note: '',
          rating: rating,
          createdAt: now,
          updatedAt: now,
        ).toMap(),
      );
      await _replaceLists(tx, versionId, ingredientsText, stepsText);
      await tx.insert(
        'finished_records',
        FinishedRecord(
          id: '${versionId}_record',
          versionId: versionId,
          imagePaths: imagePaths,
          rating: rating,
          note: feedback,
          nextImprovement: improvement,
          createdAt: now,
        ).toMap(),
      );
    });
    return recipeId;
  }

  Future<void> updateRecipe({
    required String id,
    required String title,
    required String category,
    required String description,
  }) async {
    if (title.trim().isEmpty) throw ArgumentError('请输入菜谱名称');
    final categories = await listRecipeCategories();
    final changed = await db.update(
      'recipes',
      {
        'title': title.trim(),
        'category': categories.contains(category) ? category : '未分类',
        'description': description.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (changed == 0) throw StateError('菜谱不存在');
  }

  Future<String> saveVersion({
    required String recipeId,
    String? versionId,
    required String title,
    required String note,
    double? rating,
    required List<IngredientInput> ingredients,
    required List<String> steps,
    String? imagePath,
    List<String>? imagePaths,
    String feedback = '',
    String improvement = '',
  }) async {
    final photos = imagePaths ?? [?imagePath];
    _validateImages(photos);
    final now = DateTime.now();
    final id = versionId ?? '${now.microsecondsSinceEpoch}_v';
    final existing = await versions(recipeId);
    final previous = existing
        .where((version) => version.id == versionId)
        .firstOrNull;
    final number =
        previous?.versionNumber ??
        (existing.isEmpty ? 1 : existing.first.versionNumber + 1);
    final oldImages = await db.query(
      'finished_records',
      where: 'version_id = ?',
      whereArgs: [id],
    );
    await db.transaction((tx) async {
      final version = RecipeVersion(
        id: id,
        recipeId: recipeId,
        versionNumber: number,
        title: title,
        note: note,
        rating: rating,
        isBest: previous?.isBest ?? false,
        createdAt: previous?.createdAt ?? now,
        updatedAt: now,
      );
      if (previous == null) {
        await tx.insert('recipe_versions', version.toMap());
      } else {
        await tx.update(
          'recipe_versions',
          version.toMap(),
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      await tx.delete('ingredients', where: 'version_id = ?', whereArgs: [id]);
      await tx.delete(
        'cooking_steps',
        where: 'version_id = ?',
        whereArgs: [id],
      );
      await tx.delete(
        'finished_records',
        where: 'version_id = ?',
        whereArgs: [id],
      );
      for (var i = 0; i < ingredients.length; i++) {
        final item = ingredients[i];
        await tx.insert(
          'ingredients',
          Ingredient(
            id: '${id}_i$i',
            versionId: id,
            name: item.name,
            amount: item.amount,
            unit: item.unit,
            sortOrder: i,
          ).toMap(),
        );
      }
      for (var i = 0; i < steps.length; i++) {
        await tx.insert(
          'cooking_steps',
          CookingStep(
            id: '${id}_s$i',
            versionId: id,
            content: steps[i],
            sortOrder: i,
          ).toMap(),
        );
      }
      await tx.insert(
        'finished_records',
        FinishedRecord(
          id: '${id}_record_${now.microsecondsSinceEpoch}',
          versionId: id,
          imagePaths: photos,
          rating: rating,
          note: feedback,
          nextImprovement: improvement,
          createdAt: now,
        ).toMap(),
      );
      await tx.update(
        'recipes',
        {'updated_at': now.toIso8601String()},
        where: 'id = ?',
        whereArgs: [recipeId],
      );
      await _refreshCover(recipeId, executor: tx);
    });
    await _deleteImages(oldImages);
    return id;
  }

  void _validateImages(List<String> paths) {
    if (paths.length > maxRecipeImages ||
        paths.any((path) => path.trim().isEmpty)) {
      throw ArgumentError('最多保留 $maxRecipeImages 张图片，图片路径不能为空');
    }
  }

  Future<void> _replaceLists(
    DatabaseExecutor tx,
    String versionId,
    String ingredientsText,
    String stepsText,
  ) async {
    final ingredients = parseRecipeIngredients(ingredientsText);
    for (var i = 0; i < ingredients.length; i++) {
      final item = ingredients[i];
      await tx.insert(
        'ingredients',
        Ingredient(
          id: '${versionId}_i$i',
          versionId: versionId,
          name: item.name,
          amount: item.amount,
          unit: item.unit,
          sortOrder: i,
        ).toMap(),
      );
    }
    final steps = parseRecipeSteps(stepsText);
    for (var i = 0; i < steps.length; i++) {
      await tx.insert(
        'cooking_steps',
        CookingStep(
          id: '${versionId}_s$i',
          versionId: versionId,
          content: steps[i],
          sortOrder: i,
        ).toMap(),
      );
    }
  }

  Future<void> toggleFavorite(Recipe recipe) => db
      .update(
        'recipes',
        {
          'is_favorite': recipe.isFavorite ? 0 : 1,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [recipe.id],
      )
      .then((_) {});
  Future<void> markBest(String versionId, String recipeId) async {
    await db.transaction((tx) async {
      await tx.update(
        'recipe_versions',
        {'is_best': 0},
        where: 'recipe_id = ?',
        whereArgs: [recipeId],
      );
      await tx.update(
        'recipe_versions',
        {'is_best': 1},
        where: 'id = ?',
        whereArgs: [versionId],
      );
    });
  }

  Future<void> deleteVersion(String id) async {
    final rows = await db.query(
      'finished_records',
      where: 'version_id = ?',
      whereArgs: [id],
    );
    final version = await db.query(
      'recipe_versions',
      columns: ['recipe_id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    await db.delete('recipe_versions', where: 'id = ?', whereArgs: [id]);
    await _deleteImages(rows);
    if (version.isNotEmpty) {
      await _refreshCover(version.first['recipe_id']! as String);
    }
  }

  Future<void> deleteRecipe(String id) async {
    final rows = await db.rawQuery(
      'SELECT f.image_path, f.image_paths FROM finished_records f JOIN recipe_versions v ON v.id = f.version_id WHERE v.recipe_id = ?',
      [id],
    );
    await db.delete('recipes', where: 'id = ?', whereArgs: [id]);
    await _deleteImages(rows);
  }

  Future<String> copyRecipe(String id) async {
    final recipe = await getRecipe(id);
    if (recipe == null) throw StateError('菜谱不存在');
    final sourceVersions = await versions(id);
    final sourceData = [
      for (final version in sourceVersions)
        (
          version: version,
          ingredients: await db.query(
            'ingredients',
            where: 'version_id = ?',
            whereArgs: [version.id],
            orderBy: 'sort_order',
          ),
          steps: await db.query(
            'cooking_steps',
            where: 'version_id = ?',
            whereArgs: [version.id],
            orderBy: 'sort_order',
          ),
          records: await db.query(
            'finished_records',
            where: 'version_id = ?',
            whereArgs: [version.id],
          ),
        ),
    ];
    final now = DateTime.now();
    final newId = '${now.microsecondsSinceEpoch}_copy';
    await db.transaction((tx) async {
      final recipeValues = recipe.toMap()
        ..['id'] = newId
        ..['title'] = '${recipe.title} 副本'
        ..['created_at'] = now.toIso8601String()
        ..['updated_at'] = now.toIso8601String();
      await tx.insert(
        'recipes',
        recipeValues,
      );
      for (final data in sourceData) {
        final source = data.version;
        final newVersionId = '${newId}_v${source.versionNumber}';
        await tx.insert(
          'recipe_versions',
          source.toMap()
            ..['id'] = newVersionId
            ..['recipe_id'] = newId
            ..['created_at'] = now.toIso8601String()
            ..['updated_at'] = now.toIso8601String(),
        );
        for (final ingredient in data.ingredients) {
          await tx.insert(
            'ingredients',
            Map<String, Object?>.from(ingredient)
              ..['id'] = '${newVersionId}_i${ingredient['sort_order']}'
              ..['version_id'] = newVersionId,
          );
        }
        for (final step in data.steps) {
          await tx.insert(
            'cooking_steps',
            Map<String, Object?>.from(step)
              ..['id'] = '${newVersionId}_s${step['sort_order']}'
              ..['version_id'] = newVersionId,
          );
        }
        for (var index = 0; index < data.records.length; index++) {
          await tx.insert(
            'finished_records',
            Map<String, Object?>.from(data.records[index])
              ..['id'] = '${newVersionId}_record_$index'
              ..['version_id'] = newVersionId,
          );
        }
      }
    });
    return newId;
  }

  Future<void> _deleteImages(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return;
    // Copies share photos. Cleanup must not fail an already committed save.
    try {
      final used = (await db.query('finished_records'))
          .expand(FinishedRecord.readImagePaths)
          .toSet();
      for (final path in rows.expand(FinishedRecord.readImagePaths).toSet()) {
        if (!used.contains(path) && p.basename(p.dirname(path)) == 'photos') {
          final file = File(path);
          if (await file.exists()) await file.delete();
        }
      }
    } catch (_) {
      /* Keep saved data even if an old photo cannot be removed. */
    }
  }

  Future<void> _refreshCover(
    String recipeId, {
    DatabaseExecutor? executor,
  }) async {
    final target = executor ?? db;
    final rows = await target.rawQuery(
      'SELECT f.image_path FROM finished_records f JOIN recipe_versions v ON v.id = f.version_id WHERE v.recipe_id = ? AND f.image_path IS NOT NULL ORDER BY f.created_at DESC LIMIT 1',
      [recipeId],
    );
    await target.update(
      'recipes',
      {'cover_image_path': rows.isEmpty ? null : rows.first['image_path']},
      where: 'id = ?',
      whereArgs: [recipeId],
    );
  }

  Future<Map<String, int>> stats() async {
    final recipes =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM recipes'),
        ) ??
        0;
    final versions =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM recipe_versions'),
        ) ??
        0;
    final favorites =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM recipes WHERE is_favorite = 1',
          ),
        ) ??
        0;
    final best =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM recipe_versions WHERE is_best = 1',
          ),
        ) ??
        0;
    return {
      'recipes': recipes,
      'versions': versions,
      'favorites': favorites,
      'best': best,
    };
  }

  Future<void> clearAll() async {
    final rows = await db.query('finished_records');
    await db.transaction((tx) => tx.delete('recipes'));
    await _deleteImages(rows);
  }
}
