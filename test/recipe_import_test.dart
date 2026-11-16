import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noodles/core/database/recipe_export_service.dart';
import 'package:noodles/core/database/recipe_import_service.dart';
import 'package:noodles/core/database/recipe_repository.dart';
import 'package:noodles/features/profile/presentation/data_transfer_page.dart';
import 'package:noodles/models/recipe_transfer.dart';
import 'package:noodles/providers/recipe_providers.dart';
import 'package:sqflite/sqflite.dart';

import 'recipe_export_test.dart' show SnapshotDatabase, SnapshotTransaction;
import 'recipe_transfer_check.dart' show recipeBackupFixture;

class ImportDatabase extends SnapshotDatabase {
  ImportDatabase(super.tables);
  bool failInsert = false;
  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) async {
    final working = {
      for (final entry in tables.entries)
        entry.key: [
          for (final row in entry.value) Map<String, Object?>.of(row),
        ],
    };
    final result = await action(ImportTransaction(working, failInsert));
    tables
      ..clear()
      ..addAll(working);
    return result;
  }
}

class ImportTransaction extends SnapshotTransaction {
  ImportTransaction(super.tables, this.failInsert);
  final bool failInsert;
  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    if (failInsert && table == 'finished_records') {
      throw StateError('Simulated write failure');
    }
    final rows = tables.putIfAbsent(table, () => []);
    final key = table == 'recipe_categories' ? 'name' : 'id';
    if (rows.any((row) => row[key] == values[key])) {
      throw StateError('Duplicate ID');
    }
    rows.add(Map.of(values));
    return rows.length;
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    final row = tables[table]!.singleWhere(
      (row) => row['name'] == whereArgs!.single,
    );
    row.addAll(values);
    return 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  const picker = MethodChannel('noodles/data_transfer');
  late Directory dir;
  late ImportDatabase db;
  late RecipeTransferData data;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('recipe_import_test_');
    messenger.setMockMethodCallHandler(paths, (_) async => dir.path);
    db = ImportDatabase({});
    data = RecipeTransferData.decode(jsonEncode(recipeBackupFixture()));
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(paths, null);
    messenger.setMockMethodCallHandler(picker, null);
    await dir.delete(recursive: true);
  });

  test('restores all recipe data and shared image bytes, re-export remains portable', () async {
    final result = await RecipeImportService(db).importData(data);
    expect(result.added, 1);
    expect(result.photos, 1);
    final exported = RecipeTransferData.decode(
      jsonEncode(await RecipeExportService(db).createBackup()),
    );
    expect(
      exported.tables['recipes'],
      data.tables['recipes']!
          .map((row) => {...row, 'cover_image_path': 'photo_0.jpg'})
          .toList(),
    );
    expect(exported.versionCount, 2);
    expect(exported.tables['ingredients'], data.tables['ingredients']);
    expect(exported.tables['cooking_steps'], data.tables['cooking_steps']);
    expect(exported.images.values.single, [1, 2, 3, 4]);
    final path = db.tables['recipes']!.single['cover_image_path'] as String;
    expect(await File(path).readAsBytes(), [1, 2, 3, 4]);
    expect(
      db.tables['finished_records']!.every((row) => row['image_path'] == path),
      isTrue,
    );
    db.tables['recipes']!.single['title'] = '本地修改';
    final again = await RecipeImportService(db).importData(data);
    expect(again.added, 0);
    expect(again.skipped, 1);
    expect(again.photos, 0);
    expect(db.tables['recipes']!.single['title'], '本地修改');
    expect(db.tables['recipe_versions']!.length, 2);
  });

  test('merges category names and remaps conflicting child IDs without overwriting', () async {
    db.tables.addAll({
      'recipe_categories': [
        {'name': '面食', 'sort_order': 99},
      ],
      'recipes': [
        {'id': 'local', 'title': '保留'},
      ],
      'recipe_versions': [
        {'id': 'v1', 'recipe_id': 'local'},
      ],
      'ingredients': [
        {'id': 'i1', 'version_id': 'v1', 'name': '保留食材'},
      ],
    });
    await RecipeImportService(db).importData(data);
    expect(db.tables['recipe_categories']!.single['sort_order'], 8);
    expect(db.tables['recipes']!.first['title'], '保留');
    final imported = db.tables['recipe_versions']!.singleWhere(
      (row) => row['recipe_id'] == 'r1' && row['version_number'] == 1,
    );
    expect(imported['id'], isNot('v1'));
    expect(db.tables['ingredients']!.last['version_id'], imported['id']);
    expect(db.tables['ingredients']!.first['name'], '保留食材');
  });

  test(
    'database failure rolls back rows and cleans newly restored images',
    () async {
      db.failInsert = true;
      await expectLater(
        RecipeImportService(db).importData(data),
        throwsStateError,
      );
      expect(db.tables, isEmpty);
      expect(await Directory('${dir.path}/photos').list().toList(), isEmpty);
    },
  );

  test('category merging follows SQLite ASCII-only NOCASE rules', () async {
    db.tables['recipe_categories'] = [
      {'name': 'Ä', 'sort_order': 99},
      {'name': 'SOUP', 'sort_order': 99},
    ];
    final root = recipeBackupFixture();
    root['categories'] = [
      {'name': 'ä', 'sort_order': 2},
      {'name': 'soup', 'sort_order': 3},
    ];
    await RecipeImportService(db)
        .importData(RecipeTransferData.decode(jsonEncode(root)));
    final categories = db.tables['recipe_categories']!;
    expect(
      categories.singleWhere((row) => row['name'] == 'Ä')['sort_order'],
      99,
    );
    expect(
      categories.singleWhere((row) => row['name'] == 'ä')['sort_order'],
      2,
    );
    expect(
      categories.singleWhere((row) => row['name'] == 'SOUP')['sort_order'],
      3,
    );
    expect(categories.where((row) => row['name'] == 'soup'), isEmpty);
  });

  testWidgets(
    'profile import previews JSON, cancels confirmation, imports and rejects wrong backup',
    (tester) async {
      Future<void> performAndWait(
        Future<void> Function() action,
        String expected,
      ) async {
        await tester.runAsync(() async {
          await action();
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          while (DateTime.now().isBefore(deadline)) {
            await tester.pump();
            if (find.textContaining(expected).evaluate().isNotEmpty) return;
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          fail('Timed out waiting for $expected');
        });
        await tester.pumpAndSettle();
      }

      final file = File('${dir.path}/backup.json');
      await tester.runAsync(
        () => file.writeAsString(jsonEncode(recipeBackupFixture())),
      );
      messenger.setMockMethodCallHandler(
        picker,
        (_) async => {'path': file.path, 'name': '菜谱备份.json'},
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWith((_) async => RecipeRepository(db)),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: DataTransferPage(importing: true, recipes: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await performAndWait(
        () => tester.tap(find.text('选择菜谱备份 JSON')),
        '1 道菜谱 · 2 个版本',
      );
      expect(find.textContaining('1 道菜谱 · 2 个版本'), findsOneWidget);
      await tester.tap(find.text('合并导入'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(db.tables, isEmpty);
      await tester.tap(find.text('合并导入'));
      await tester.pumpAndSettle();
      await performAndWait(
        () => tester.tap(find.widgetWithText(FilledButton, '合并导入').last),
        '新增 1 道菜谱',
      );
      expect(find.textContaining('新增 1 道菜谱'), findsOneWidget);
      await tester.runAsync(
        () => file.writeAsString('{"format":"noodles.inventory","version":1}'),
      );
      await performAndWait(
        () => tester.tap(find.text('选择菜谱备份 JSON')),
        '请选择此应用导出的菜谱备份 JSON',
      );
      expect(find.textContaining('请选择此应用导出的菜谱备份 JSON'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '合并导入'))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    },
  );
}
