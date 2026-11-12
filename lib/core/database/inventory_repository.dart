import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../models/inventory_item.dart';
import '../../models/inventory_settings.dart';

class InventoryRepository {
  InventoryRepository(this.db);
  final Database db;
  static Future<void> createTables(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE inventory_categories (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE COLLATE NOCASE, description TEXT NOT NULL, sort_order INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE inventory_items (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, expiry_date TEXT NOT NULL, updated_at TEXT, category_id INTEGER, location TEXT NOT NULL, quantity TEXT NOT NULL, production_date TEXT, storage_duration TEXT NOT NULL, storage_unit TEXT NOT NULL, purchase_date TEXT, purchase_price TEXT NOT NULL, remark TEXT NOT NULL, image_paths TEXT NOT NULL, FOREIGN KEY(category_id) REFERENCES inventory_categories(id) ON DELETE SET NULL)',
    );
    await db.execute(
      'CREATE INDEX inventory_items_category ON inventory_items(category_id)',
    );
    await db.execute(
      'CREATE TABLE inventory_settings (id INTEGER PRIMARY KEY CHECK(id = 1), near_days INTEGER NOT NULL, middle_days INTEGER NOT NULL, far_days INTEGER NOT NULL, CHECK(near_days > 0 AND near_days < middle_days AND middle_days < far_days AND far_days <= 36500))',
    );
    await db.insert('inventory_settings', {
      'id': 1,
      'near_days': 7,
      'middle_days': 15,
      'far_days': 30,
    });
  }

  Future<List<InventoryItem>> listItems() async => (await db.rawQuery(
    'SELECT i.*, c.name AS category_name FROM inventory_items i LEFT JOIN inventory_categories c ON c.id = i.category_id ORDER BY i.id DESC',
  )).map(InventoryItem.fromMap).toList();
  Future<void> saveItem(InventoryItem item) async {
    if (item.name.trim().isEmpty) throw ArgumentError('请输入名称');
    final old = item.id == null
        ? <Map<String, Object?>>[]
        : await db.query(
            'inventory_items',
            columns: ['image_paths'],
            where: 'id = ?',
            whereArgs: [item.id],
          );
    final values = item.toMap()
      ..['updated_at'] = DateTime.now().toUtc().toIso8601String();
    if (item.id == null) {
      await db.insert('inventory_items', values);
    } else {
      await db.update(
        'inventory_items',
        values,
        where: 'id = ?',
        whereArgs: [item.id],
      );
    }
    await _deleteUnusedImages(old);
  }

  Future<void> deleteItem(int id) async {
    final old = await db.query(
      'inventory_items',
      columns: ['image_paths'],
      where: 'id = ?',
      whereArgs: [id],
    );
    await db.delete('inventory_items', where: 'id = ?', whereArgs: [id]);
    await _deleteUnusedImages(old);
  }

  Future<void> _deleteUnusedImages(List<Map<String, Object?>> old) async {
    if (old.isEmpty) return;
    // Copies can share photos. Cleanup must never turn a committed save into a failure.
    try {
      final rows = await db.query('inventory_items', columns: ['image_paths']);
      final used = rows
          .expand(
            (row) => (jsonDecode(row['image_paths'] as String) as List)
                .cast<String>(),
          )
          .toSet();
      for (final row in old) {
        for (final path in (jsonDecode(
          row['image_paths'] as String,
        ) as List).cast<String>()) {
          if (!used.contains(path) &&
              p.basename(p.dirname(path)) == 'inventory_photos') {
            final file = File(path);
            if (await file.exists()) await file.delete();
          }
        }
      }
    } catch (_) {
      /* Photo cleanup must not affect saved data. */
    }
  }

  Future<List<InventoryCategory>> listCategories() async => (await db.rawQuery(
    'SELECT c.*, COUNT(i.id) AS item_count FROM inventory_categories c LEFT JOIN inventory_items i ON i.category_id = c.id GROUP BY c.id ORDER BY c.sort_order, c.id DESC',
  )).map(InventoryCategory.fromMap).toList();
  Future<void> saveCategory(InventoryCategory category) async {
    final name = category.name.trim();
    if (name.isEmpty) throw ArgumentError('请输入分类名称');
    final duplicate = await db.query(
      'inventory_categories',
      columns: ['id'],
      where: 'name = ? AND id != ?',
      whereArgs: [name, category.id ?? -1],
    );
    if (duplicate.isNotEmpty) throw ArgumentError('该分类已存在');
    final values = {
      'name': name,
      'description': category.description.trim(),
      'sort_order': category.sortOrder,
    };
    if (category.id == null) {
      await db.insert('inventory_categories', values);
    } else {
      await db.update(
        'inventory_categories',
        values,
        where: 'id = ?',
        whereArgs: [category.id],
      );
    }
  }

  Future<void> deleteCategory(int id) async {
    await db.delete('inventory_categories', where: 'id = ?', whereArgs: [id]);
  }

  Future<ExpirySettings> expirySettings() async {
    final row = (await db.query('inventory_settings', where: 'id = 1')).single;
    return ExpirySettings(
      near: row['near_days'] as int,
      middle: row['middle_days'] as int,
      far: row['far_days'] as int,
    );
  }

  Future<void> saveExpirySettings(ExpirySettings settings) async {
    if (!settings.isValid) {
      throw ArgumentError('提醒天数须为正整数，且近期 < 中期 < 长期（最多 36500 天）');
    }
    await db.update('inventory_settings', {
      'near_days': settings.near,
      'middle_days': settings.middle,
      'far_days': settings.far,
    }, where: 'id = 1');
  }
}
