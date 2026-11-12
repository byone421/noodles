import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:noodles/models/inventory_transfer.dart';

String csv(List<List<String>> rows) => rows
    .map(
      (row) => row.map((cell) => '"${cell.replaceAll('"', '""')}"').join(','),
    )
    .join('\r\n');

const itemHeader = [
  'ID',
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
  '备注',
  '图片',
];

void main() {
  test('OpenCSV legacy export preserves all fields, BOM, comma, quotes and multiline remarks', () {
    final text =
        '\uFEFF${csv([
          itemHeader,
          ['99', '牛奶', '2026-11-01', '1', '月', '2026-11-30', '18', '冷藏', '12.50', '', '冰箱', '2 瓶', '含逗号, "开封"\n尽快喝完', '/data/old/a.jpg;/data/old/b.png'],
        ])}';
    final result = InventoryTransferData.decode(text);
    final item = result.items.single;
    expect(result.legacy, isTrue);
    expect(item.id, 99);
    expect(item.categoryId, 18);
    expect(item.remark, '含逗号, "开封"\n尽快喝完');
    expect(item.imagePaths, ['/data/old/a.jpg', '/data/old/b.png']);
    expect(item.expiryDate, DateTime(2026, 11, 30));
    expect(item.purchaseDate, isNull);
    expect(item.purchasePrice, '12.50');
  });

  test('old category variants accept optional description and home-display columns', () {
    final result = InventoryTransferData.decode(
      csv([
        ['ID', '名称', '排序', '创建时间', '首页展示', '说明'],
        ['4', '食品', '3', '1794380000000', 'false', '厨房, 冰箱'],
      ]),
    );
    expect(result.categories.single.id, 4);
    expect(result.categories.single.sortOrder, 3);
    expect(result.categories.single.description, '厨房, 冰箱');
    expect(result.warnings, isNotEmpty);
    final older = InventoryTransferData.decode('ID,名称,排序,创建时间\n1,食品,0,123');
    expect(older.categories.single.name, '食品');
  });

  test('invalid row rejects whole source, dates never silently normalize', () {
    expect(() => readCsv('"unclosed'), throwsFormatException);
    expect(() => readCsv('"closed"oops'), throwsFormatException);
    expect(
      () => InventoryTransferData.decode('任意,文件\n1,2'),
      throwsFormatException,
    );
    expect(() => transferDate('2026-02-30', '到期日期'), throwsFormatException);
    expect(() => transferDate('2026-13-01', '到期日期'), throwsFormatException);
    expect(() => transferDate('', '到期日期'), throwsFormatException);
    expect(
      transferDate('2026-11-11T00:00:00.000', '到期日期'),
      DateTime(2026, 11, 11),
    );
    expect(
      () => InventoryTransferData.decode(
        csv([
          itemHeader,
          ['1', '牛奶'],
        ]),
      ),
      throwsFormatException,
    );
  });

  test(
    'portable JSON validates photo references and survives a model roundtrip',
    () {
      final item = InventoryTransferData.decode(
        csv([
          itemHeader,
          [
            '9',
            '牛奶',
            '',
            '',
            '天',
            '2026-11-30',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            'photo.jpg',
          ],
        ]),
      ).items.single;
      final backup = {
        'format': 'noodles.inventory',
        'version': 1,
        'categories': [],
        'items': [item.toMap()],
        'images': {
          'photo.jpg': base64Encode([1, 2, 3]),
        },
      };
      final decoded = InventoryTransferData.decode(jsonEncode(backup));
      expect(decoded.legacy, isFalse);
      expect(decoded.items.single.toMap(), item.toMap());
      expect(decoded.images['photo.jpg'], [1, 2, 3]);
      backup['images'] = <String, String>{};
      expect(
        () => InventoryTransferData.decode(jsonEncode(backup)),
        throwsFormatException,
      );
      backup['version'] = 2;
      expect(
        () => InventoryTransferData.decode(jsonEncode(backup)),
        throwsFormatException,
      );
    },
  );
}
