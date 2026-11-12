import 'dart:convert';
import 'dart:typed_data';

import 'inventory_item.dart';
import 'inventory_settings.dart';

/// Old CSV IDs are used only to resolve relationships, never as local IDs.
class InventoryTransferData {
  InventoryTransferData({
    this.categories = const [],
    this.items = const [],
    this.images = const {},
    this.warnings = const [],
    this.legacy = false,
  });
  final bool legacy;
  final List<InventoryCategory> categories;
  final List<InventoryItem> items;
  final Map<String, Uint8List> images;
  final List<String> warnings;

  static InventoryTransferData decode(String text) {
    text = text.replaceFirst(RegExp(r'^\uFEFF'), '');
    if (text.trimLeft().startsWith('{')) return _backup(text);
    final rows = readCsv(text);
    if (rows.isEmpty) throw const FormatException('文件为空');
    final header = rows.first.map((s) => s.trim()).toList();
    if (header.toSet().length != header.length) {
      throw const FormatException('CSV 存在重复列名');
    }
    final isItem = header.contains('到期日期');
    final required = isItem
        ? [
            '名称',
            '生产日期',
            '保质期',
            '保质单位',
            '到期日期',
            '分类ID',
            '分类名称',
            '价格',
            '购买日期',
            '存放位置',
            '存放数量',
          ]
        : ['ID', '名称', '排序', '创建时间'];
    if (!required.every(header.contains)) {
      throw const FormatException('不是老项目导出的物品或分类 CSV，请勿修改表头');
    }
    final categories = <InventoryCategory>[];
    final items = <InventoryItem>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.every((value) => value.trim().isEmpty)) continue;
      if (row.length != header.length) {
        throw FormatException('第 ${i + 1} 条记录列数不正确');
      }
      String field(String key) =>
          header.contains(key) ? row[header.indexOf(key)] : '';
      final name = field('名称').trim();
      if (name.isEmpty) throw FormatException('第 ${i + 1} 条记录缺少名称');
      if (!isItem) {
        final sort = int.tryParse(field('排序'));
        if (sort == null) throw FormatException('第 ${i + 1} 条记录排序不是整数');
        categories.add(
          InventoryCategory(
            id: int.tryParse(field('ID')),
            name: name,
            description: field('说明'),
            sortOrder: sort,
          ),
        );
      } else {
        final unit = field('保质单位').trim();
        if (unit.isNotEmpty && !['天', '周', '月', '年'].contains(unit)) {
          throw FormatException('第 ${i + 1} 条记录保质单位无效');
        }
        items.add(
          InventoryItem(
            id: int.tryParse(field('ID')),
            name: name,
            expiryDate: transferDate(field('到期日期'), '第 ${i + 1} 条记录到期日期')!,
            productionDate: transferDate(
              field('生产日期'),
              '第 ${i + 1} 条记录生产日期',
              optional: true,
            ),
            purchaseDate: transferDate(
              field('购买日期'),
              '第 ${i + 1} 条记录购买日期',
              optional: true,
            ),
            storageDuration: field('保质期'),
            storageUnit: unit.isEmpty ? '天' : unit,
            categoryId: int.tryParse(field('分类ID')),
            category: field('分类名称').trim(),
            purchasePrice: field('价格'),
            location: field('存放位置'),
            quantity: field('存放数量'),
            remark: field('备注'),
            imagePaths: field('图片')
                .split(';')
                .where((p) => p.trim().isNotEmpty)
                .toList(),
          ),
        );
      }
    }
    return InventoryTransferData(
      categories: categories,
      items: items,
      legacy: true,
      warnings: !isItem && categories.isNotEmpty
          ? ['旧分类的创建时间、首页展示选项在新项目中不使用；名称、说明和排序会迁移。']
          : [],
    );
  }

  static InventoryTransferData _backup(String text) {
    try {
      final data = jsonDecode(text) as Map<String, dynamic>;
      if (data['format'] != 'noodles.inventory' || data['version'] != 1) {
        throw const FormatException('不支持的备份格式或版本');
      }
      final categories = (data['categories'] as List).map((value) {
        final row = Map<String, Object?>.from(value as Map);
        final category = InventoryCategory.fromMap(row);
        if (category.name.trim().isEmpty) throw const FormatException('分类名称为空');
        return category;
      }).toList();
      final images = <String, Uint8List>{};
      for (final entry in (data['images'] as Map<String, dynamic>).entries) {
        final bytes = base64Decode(entry.value as String);
        if (bytes.length > 20 * 1024 * 1024) {
          throw const FormatException('单张图片超过 20 MB');
        }
        images[entry.key] = bytes;
      }
      final items = (data['items'] as List).map((value) {
        final row = Map<String, Object?>.from(value as Map);
        final item = InventoryItem.fromMap(row);
        if (item.name.trim().isEmpty ||
            !['天', '周', '月', '年'].contains(item.storageUnit)) {
          throw const FormatException('物品名称或保质单位无效');
        }
        for (final key in ['expiry_date', 'production_date', 'purchase_date']) {
          transferDate(
            row[key] as String? ?? '',
            key,
            optional: key != 'expiry_date',
          );
        }
        if (item.imagePaths.any((path) => !images.containsKey(path))) {
          throw const FormatException('备份缺少图片数据，请使用完整备份文件');
        }
        return item;
      }).toList();
      return InventoryTransferData(
        categories: categories,
        items: items,
        images: images,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('备份内容损坏或字段不完整');
    }
  }
}

DateTime? transferDate(String value, String label, {bool optional = false}) {
  value = value.trim();
  if (optional && value.isEmpty) return null;
  final match = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:T00:00:00(?:\.000)?)?$')
      .firstMatch(value);
  if (match == null) throw FormatException('$label 格式应为 yyyy-MM-dd');
  final year = int.parse(match[1]!),
      month = int.parse(match[2]!),
      day = int.parse(match[3]!);
  final date = DateTime(year, month, day);
  if (year < 2000 ||
      year > 2100 ||
      date.year != year ||
      date.month != month ||
      date.day != day) {
    throw FormatException('$label 无效或超出 2000–2100 年');
  }
  return date;
}

/// RFC 4180, including OpenCSV's quoted commas, quotes and multiline remarks.
List<List<String>> readCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var quoted = false, closed = false;
  void finishField() {
    row.add(field.toString());
    field = StringBuffer();
    closed = false;
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
          closed = true;
        }
      } else {
        field.write(c);
      }
    } else if (c == ',') {
      finishField();
    } else if (c == '\r' || c == '\n') {
      finishField();
      rows.add(row);
      row = [];
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
    } else if (c == '"' && field.isEmpty && !closed) {
      quoted = true;
    } else if (closed || c == '"') {
      throw const FormatException('CSV 引号格式不正确');
    } else {
      field.write(c);
    }
  }
  if (quoted) throw const FormatException('CSV 引号未闭合');
  if (field.isNotEmpty || row.isNotEmpty || closed) {
    finishField();
    rows.add(row);
  }
  return rows;
}
