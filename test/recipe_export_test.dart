import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noodles/core/database/recipe_export_service.dart';
import 'package:noodles/features/profile/presentation/profile_page.dart';
import 'package:sqflite/sqflite.dart';

class SnapshotDatabase extends Fake implements Database {
  SnapshotDatabase(this.tables);
  final Map<String, List<Map<String, Object?>>> tables;

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) => action(SnapshotTransaction(tables));
}

class SnapshotTransaction extends Fake implements Transaction {
  SnapshotTransaction(this.tables);
  final Map<String, List<Map<String, Object?>>> tables;

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async => tables[table] ?? [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const transfer = MethodChannel('noodles/data_transfer');
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory dir;
  late Map<String, List<Map<String, Object?>>> tables;
  late RecipeExportService service;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('recipe_export_test_');
    final photo = File('${dir.path}/成品.jpg');
    await photo.writeAsBytes([1, 2, 3, 4]);
    tables = {
      'recipe_categories': [
        {'name': '面食', 'sort_order': 7},
      ],
      'recipes': [
        {
          'id': 'r1',
          'title': '番茄面',
          'category': '面食',
          'is_favorite': 1,
          'cover_image_path': photo.path,
        },
      ],
      'recipe_versions': [
        {'id': 'v1', 'recipe_id': 'r1', 'version_number': 1, 'is_best': 1},
        {'id': 'v2', 'recipe_id': 'r1', 'version_number': 2, 'rating': 4.5},
      ],
      'ingredients': [
        {'id': 'i1', 'version_id': 'v1', 'name': '面条', 'sort_order': 0},
      ],
      'cooking_steps': [
        {'id': 's1', 'version_id': 'v2', 'content': '煮面', 'sort_order': 0},
      ],
      'finished_records': [
        {
          'id': 'f1',
          'version_id': 'v1',
          'image_path': photo.path,
          'image_paths': '[]',
          'note': '好吃',
          'next_improvement': '少盐',
        },
        {
          'id': 'f2',
          'version_id': 'v2',
          'image_path': photo.path,
          'image_paths': jsonEncode([photo.path, photo.path]),
          'rating': 4.5,
        },
      ],
    };
    service = RecipeExportService(SnapshotDatabase(tables));
    messenger.setMockMethodCallHandler(pathProvider, (_) async => dir.path);
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(transfer, null);
    messenger.setMockMethodCallHandler(pathProvider, null);
    await dir.delete(recursive: true);
  });

  test(
    'exports every recipe table with portable, deduplicated photo bytes',
    () async {
      final backup = await service.createBackup();
      expect(backup['format'], 'noodles.recipes');
      expect(backup['version'], 1);
      for (final table in ['recipe_versions', 'ingredients', 'cooking_steps']) {
        expect(backup[table], tables[table]);
      }
      expect(backup['categories'], tables['recipe_categories']);
      final recipes = backup['recipes'] as List;
      expect(recipes.single, {
        ...tables['recipes']!.single,
        'cover_image_path': 'photo_0.jpg',
      });
      final records = backup['finished_records'] as List;
      expect(records.first, {
        ...tables['finished_records']!.first,
        'image_path': 'photo_0.jpg',
        'image_paths': '["photo_0.jpg"]',
      });
      expect(jsonDecode(records.last['image_paths'] as String), [
        'photo_0.jpg',
        'photo_0.jpg',
      ]);
      expect(backup['images'], {
        'photo_0.jpg': base64Encode([1, 2, 3, 4]),
      });
      expect(
        jsonEncode(backup),
        isNot(contains(dir.path.replaceAll('\\', '\\\\'))),
      );
    },
  );

  test(
    'missing and oversized images stop export before opening save picker',
    () async {
      messenger.setMockMethodCallHandler(
        transfer,
        (_) async => fail('Unexpected picker'),
      );
      final path = tables['recipes']!.single['cover_image_path'] as String;
      await File(path).delete();
      await expectLater(
        service.exportData(),
        throwsA(isA<FileSystemException>()),
      );
      final oversized = await File(path).open(mode: FileMode.write);
      await oversized.truncate(20 * 1024 * 1024 + 1);
      await oversized.close();
      await expectLater(service.exportData(), throwsFormatException);
    },
  );

  test(
    'save succeeds, cancels or fails without leaving temporary JSON files',
    () async {
      for (final outcome in ['success', 'cancel', 'failure']) {
        late File staged;
        messenger.setMockMethodCallHandler(transfer, (call) async {
          expect(call.method, 'exportFile');
          expect(call.arguments['name'], startsWith('菜谱备份_'));
          staged = File(call.arguments['path'] as String);
          final backup = jsonDecode(await staged.readAsString()) as Map;
          expect(backup['format'], 'noodles.recipes');
          expect(backup['images'], isNotEmpty);
          if (outcome == 'failure') throw PlatformException(code: 'write');
          return outcome == 'success' ? true : null;
        });
        if (outcome == 'failure') {
          await expectLater(
            service.exportData(),
            throwsA(isA<PlatformException>()),
          );
        } else {
          expect(await service.exportData(), outcome == 'success');
        }
        expect(await staged.exists(), isFalse);
      }
    },
  );

  test(
    'empty recipe library still exports its categories and valid JSON',
    () async {
      tables.removeWhere((table, _) => table != 'recipe_categories');
      final backup =
          jsonDecode(jsonEncode(await service.createBackup())) as Map;
      expect(backup['categories'], isNotEmpty);
      expect(backup['recipes'], isEmpty);
      expect(backup['images'], isEmpty);
    },
  );

  testWidgets('profile opens a separate recipe export page', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: ProfilePage())),
      ),
    );
    await tester.ensureVisible(find.text('导出菜谱数据'));
    await tester.tap(find.text('导出菜谱数据'));
    await tester.pumpAndSettle();
    expect(find.text('备份菜谱数据'), findsOneWidget);
    expect(find.text('导出并选择保存位置'), findsOneWidget);
    expect(find.textContaining('可通过“导入菜谱数据”恢复'), findsOneWidget);
    expect(find.text('选择 CSV 或万物备份 JSON'), findsNothing);
  });
}
