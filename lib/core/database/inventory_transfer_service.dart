import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/inventory_transfer.dart';

class ImportSummary {
  int added = 0,
      skipped = 0,
      photosAdded = 0,
      categories = 0,
      missingPhotos = 0;
  @override
  String toString() =>
      '新增 $added 件物品，跳过 $skipped 件相同记录，合并 $categories 个分类，迁移 $photosAdded 张图片'
      '${missingPhotos == 0 ? '' : '；$missingPhotos 张旧图片未找到'}';
}

class InventoryTransferService {
  InventoryTransferService(this.db);
  final Database db;
  static const channel = MethodChannel('noodles/data_transfer');

  static Future<Map<String, String>?> pickFile() async =>
      (await channel.invokeMapMethod<String, String>('pickFile'));
  static Future<Map<String, String>?> pickImageFolder() async =>
      (await channel.invokeMapMethod<String, String>('pickImageFolder'));

  static Future<InventoryTransferData> read(String path) async {
    final file = File(path);
    if (await file.length() > 100 * 1024 * 1024) {
      throw const FormatException('文件超过 100 MB');
    }
    return InventoryTransferData.decode(await file.readAsString());
  }

  Future<ImportSummary> importData(
    InventoryTransferData data, {
    Map<String, String> photos = const {},
  }) async {
    final summary = ImportSummary();
    final created = <File>[];
    final dir = Directory(
      p.join(
        (await getApplicationDocumentsDirectory()).path,
        'inventory_photos',
      ),
    );
    await dir.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final originalNames = <String, Set<String>>{};
    for (final item in data.items) {
      for (final path in item.imagePaths) {
        final name = p.posix.basename(path.replaceAll('\\', '/'));
        originalNames.putIfAbsent(name, () => {}).add(path);
      }
    }
    final usedNames = <String>{};
    var sequence = 0;
    String exportImageName(String path) {
      final name = p.posix.basename(path.replaceAll('\\', '/'));
      final extension = p.extension(name);
      final base = p.basenameWithoutExtension(name);
      var result = name, index = 1;
      while (!usedNames.add(result)) {
        result = '${base}_${index++}$extension';
      }
      return result;
    }

    try {
      await db.transaction((tx) async {
        await tx.execute(
          'CREATE TABLE IF NOT EXISTS inventory_legacy_categories '
          '(old_id INTEGER PRIMARY KEY, local_id INTEGER REFERENCES inventory_categories(id) ON DELETE SET NULL)',
        );
        final localCategories = await tx.query('inventory_categories');
        final byName = {
          for (final row in localCategories)
            (row['name'] as String).toLowerCase(): row['id'] as int,
        };
        Future<int?> category(String name) async {
          name = name.trim();
          if (name.isEmpty) return null;
          final key = name.toLowerCase();
          return byName[key] ??= await tx.insert('inventory_categories', {
            'name': name,
            'description': '',
            'sort_order': 0,
          });
        }

        final sourceCategories = <int, int?>{};
        for (final value in data.categories) {
          final id = await category(value.name);
          if (value.id != null) {
            sourceCategories[value.id!] = id;
            if (data.legacy) {
              await tx.insert('inventory_legacy_categories', {
                'old_id': value.id,
                'local_id': id,
              }, conflictAlgorithm: ConflictAlgorithm.replace);
            }
          }
          if (id != null) {
            await tx.update(
              'inventory_categories',
              {'description': value.description, 'sort_order': value.sortOrder},
              where: 'id = ?',
              whereArgs: [id],
            );
            summary.categories++;
          }
        }
        final legacyCategories = {
          for (final row in await tx.query('inventory_legacy_categories'))
            row['old_id'] as int: row['local_id'] as int?,
        };
        final existing = await tx.query('inventory_items');
        String identity(Map<String, Object?> row) => jsonEncode([
          for (final key in [
            'name',
            'expiry_date',
            'category_id',
            'location',
            'quantity',
            'production_date',
            'storage_duration',
            'storage_unit',
            'purchase_date',
            'purchase_price',
            'remark',
          ])
            row[key],
        ]);
        // Match each existing record once, preserving legitimate identical copies.
        final known = <String, List<Map<String, Object?>>>{};
        for (final row in existing) {
          known.putIfAbsent(identity(row), () => []).add(row);
        }
        for (final item in data.items) {
          final values = item.toMap()..remove('id');
          final mappedCategory =
              sourceCategories[item.categoryId] ??
              (data.legacy ? legacyCategories[item.categoryId] : null);
          values['category_id'] =
              mappedCategory ??
              (item.categoryId == null && item.category == '未分类'
                  ? null
                  : await category(item.category));
          if ((item.categoryId ?? 0) > 0 && mappedCategory == null) {
            throw const FormatException('物品含有尚未识别的旧分类 ID，请先导入老项目的分类 CSV');
          }
          final key = identity(values);
          final matches = known[key];
          final duplicate = matches == null || matches.isEmpty
              ? null
              : matches.removeAt(0);
          final savedPhotos = <String>[];
          final previousPaths = duplicate == null
              ? <String>[]
              : (jsonDecode(duplicate['image_paths'] as String) as List)
                    .cast<String>();
          final previousBytes = <Uint8List>[];
          for (final path in previousPaths) {
            final file = File(path);
            if (await file.exists()) {
              previousBytes.add(await file.readAsBytes());
            }
          }
          for (final path in item.imagePaths) {
            final exportedName = data.legacy ? exportImageName(path) : path;
            var bytes = data.images[path];
            // Without a manifest, different old paths with the same basename
            // cannot be resolved safely if the old exporter skipped missing files.
            final originalName = p.posix.basename(path.replaceAll('\\', '/'));
            final ambiguous =
                data.legacy && (originalNames[originalName]?.length ?? 0) > 1;
            final source =
                photos[path] ?? (ambiguous ? null : photos[exportedName]);
            if (bytes == null && source == null) {
              summary.missingPhotos++;
              continue;
            }
            bytes ??= await File(source!).readAsBytes();
            if (previousBytes.any((previous) => listEquals(previous, bytes))) {
              continue;
            }
            final ext = p.extension(exportedName).toLowerCase();
            final target = File(
              p.join(
                dir.path,
                '${stamp}_${sequence++}${RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(ext) ? ext : '.jpg'}',
              ),
            );
            created.add(target);
            await target.writeAsBytes(bytes, flush: true);
            savedPhotos.add(target.path);
            summary.photosAdded++;
          }
          if (duplicate != null) {
            if (savedPhotos.isNotEmpty) {
              await tx.update(
                'inventory_items',
                {
                  'image_paths': jsonEncode([...previousPaths, ...savedPhotos]),
                  'updated_at': DateTime.now().toUtc().toIso8601String(),
                },
                where: 'id = ?',
                whereArgs: [duplicate['id']],
              );
            }
            summary.skipped++;
            continue;
          }
          values['image_paths'] = jsonEncode(savedPhotos);
          values['updated_at'] ??= DateTime.now().toUtc().toIso8601String();
          await tx.insert('inventory_items', values);
          summary.added++;
        }
      });
      return summary;
    } catch (_) {
      for (final file in created) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {
          /* Preserve original error. */
        }
      }
      rethrow;
    }
  }

  /// Export a portable inventory backup, with photo bytes rather than app-private paths.
  Future<bool> exportData() async {
    final snapshot = await db.transaction(
      (tx) async => {
        'categories': await tx.query('inventory_categories'),
        'items': await tx.rawQuery(
          'SELECT i.*, c.name AS category_name FROM inventory_items i '
          'LEFT JOIN inventory_categories c ON c.id = i.category_id ORDER BY i.id DESC',
        ),
      },
    );
    final images = <String, String>{};
    final references = <String, String>{};
    final items = <Map<String, Object?>>[];
    var total = 0;
    for (final row in snapshot['items']!) {
      final paths = (jsonDecode(row['image_paths'] as String) as List)
          .cast<String>();
      final exported = <String>[];
      for (final path in paths) {
        if (!references.containsKey(path)) {
          final file = File(path);
          if (!await file.exists()) {
            throw const FileSystemException('物品图片缺失，备份未保存；请先移除失效图片');
          }
          final size = await file.length();
          total += size;
          if (size > 20 * 1024 * 1024 || total > 65 * 1024 * 1024) {
            throw const FormatException('图片过大，暂支持单张 20 MB、总计 65 MB 的备份');
          }
          final key = 'photo_${images.length}${p.extension(path)}';
          references[path] = key;
          images[key] = base64Encode(await file.readAsBytes());
        }
        exported.add(references[path]!);
      }
      items.add({...row, 'image_paths': jsonEncode(exported)});
    }
    final content = jsonEncode({
      'format': 'noodles.inventory',
      'version': 1,
      'categories': snapshot['categories'],
      'items': items,
      'images': images,
    });
    if (utf8.encode(content).length > 100 * 1024 * 1024) {
      throw const FormatException('备份超过 100 MB');
    }
    final dir = await getTemporaryDirectory();
    final file = File(
      p.join(
        dir.path,
        'inventory_backup_${DateTime.now().microsecondsSinceEpoch}.json',
      ),
    );
    try {
      await file.writeAsString(content, flush: true);
      return await channel.invokeMethod<bool>('exportFile', {
            'path': file.path,
            'name':
                '万物备份_${DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '-')}.json',
          }) ??
          false;
    } finally {
      if (await file.exists()) await file.delete();
    }
  }

  static Future<void> cleanStaged(Iterable<String> paths) async {
    final root = (await getTemporaryDirectory()).absolute.path;
    for (final path in paths.toSet()) {
      final file = File(path).absolute;
      if (p.isWithin(root, file.path) &&
          p.basename(file.parent.path).startsWith('transfer_')) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {
          /* Cache cleanup is best effort. */
        }
      }
    }
  }
}
