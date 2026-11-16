import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noodles/core/database/inventory_repository.dart';
import 'package:noodles/core/theme/app_theme.dart';
import 'package:noodles/features/inventory/presentation/inventory_add_item_page.dart';
import 'package:noodles/features/inventory/presentation/inventory_categories_page.dart';
import 'package:noodles/features/inventory/presentation/inventory_home_page.dart';
import 'package:noodles/features/profile/presentation/expiry_days_page.dart';
import 'package:noodles/models/inventory_item.dart';
import 'package:noodles/models/inventory_settings.dart';
import 'package:noodles/providers/inventory_providers.dart';

class RecordingRepository implements InventoryRepository {
  InventoryItem? saved;
  ExpirySettings settings = const ExpirySettings();
  @override
  Future<void> saveItem(InventoryItem item) async {
    saved = item;
  }

  @override
  Future<List<InventoryCategory>> listCategories() async => const [
    InventoryCategory(id: 1, name: '厨房', itemCount: 2),
  ];
  @override
  Future<ExpirySettings> expirySettings() async => settings;
  @override
  Future<void> saveExpirySettings(ExpirySettings value) async {
    settings = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('expiry calculations include production day and clamp calendar months/years', () {
    expect(
      calculateInventoryExpiry(DateTime(2026, 11, 11), 1, '天'),
      DateTime(2026, 11, 11),
    );
    expect(
      calculateInventoryExpiry(DateTime(2026, 11, 11), 2, '周'),
      DateTime(2026, 11, 24),
    );
    expect(
      calculateInventoryExpiry(DateTime(2024, 1, 31), 1, '月'),
      DateTime(2024, 2, 28),
    );
    expect(
      calculateInventoryExpiry(DateTime(2024, 2, 29), 1, '年'),
      DateTime(2025, 2, 27),
    );
    expect(
      () => calculateInventoryExpiry(DateTime(2026), 0, '天'),
      throwsArgumentError,
    );
  });
  test(
    'expiry ranges include today and boundary, exclude expired and later dates',
    () {
      final now = DateTime(2026, 11, 11, 23, 59);
      InventoryItem item(int day) =>
          InventoryItem(name: '物品', expiryDate: DateTime(2026, 11, 11 + day));
      expect(item(-1).matchesRange(-1, now: now), isTrue);
      expect(item(0).matchesRange(-1, now: now), isFalse);
      expect(item(-1).matchesRange(7, now: now), isFalse);
      expect(item(0).matchesRange(7, now: now), isTrue);
      expect(item(7).matchesRange(7, now: now), isTrue);
      expect(item(8).matchesRange(7, now: now), isFalse);
      expect(item(8).matchesRange(null, now: now), isTrue);
    },
  );
  test('all item fields survive storage round trip', () {
    final item = InventoryItem(
      id: 9,
      name: '牛奶',
      categoryId: 1,
      category: '厨房',
      expiryDate: DateTime(2026, 12, 1),
      updatedAt: DateTime.utc(2026, 11, 12, 8, 30),
      productionDate: DateTime(2026, 11, 1),
      storageDuration: '1',
      storageUnit: '月',
      purchaseDate: DateTime(2026, 11, 2),
      purchasePrice: '12.50',
      quantity: '2 瓶',
      location: '冰箱',
      remark: '开封后冷藏',
      imagePaths: const ['a.jpg', 'b.jpg'],
    );
    final restored = InventoryItem.fromMap({
      ...item.toMap(),
      'category_name': '厨房',
    });
    expect(restored.toMap(), item.toMap());
    expect(restored.category, '厨房');
    expect(const ExpirySettings(near: 0).isValid, isFalse);
    expect(const ExpirySettings(near: 15, middle: 7).isValid, isFalse);
    expect(const ExpirySettings(far: 36501).isValid, isFalse);
  });

  final now = DateTime.now();
  InventoryItem item(String name, int day, {int? category}) => InventoryItem(
    id: day + 10,
    name: name,
    expiryDate: DateTime(now.year, now.month, now.day + day),
    categoryId: category,
    category: category == null ? '' : '厨房',
    location: '储物柜',
  );
  final items = [
    item('已过期牛奶', -1, category: 1),
    item('今天到期', 0),
    item('七天边界', 7, category: 1),
    item('八天物品', 8),
    item('长期物品', 60),
  ];
  final boundary = GlobalKey();
  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget page, {
    RecordingRepository? repository,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        inventoryItemsProvider.overrideWith((_) async => items),
        inventoryCategoriesProvider.overrideWith(
          (_) async => const [
            InventoryCategory(
              id: 1,
              name: '厨房',
              description: '烹饪与储藏',
              itemCount: 2,
            ),
            InventoryCategory(id: 2, name: '日常用品', itemCount: 0),
          ],
        ),
        inventoryRepositoryProvider.overrideWith(
          (_) async => repository ?? RecordingRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(body: page),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      final image = await (tester.renderObject(
        find.byKey(boundary),
      ) as RenderRepaintBoundary).toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/inventory_qa/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('list filters and selected reminder follow changed settings', (
    tester,
  ) async {
    final repository = RecordingRepository();
    final container = await pump(
      tester,
      const InventoryHomePage(),
      repository: repository,
    );
    await screenshot(tester, 'inventory');
    await tester.tap(find.text('7 天内到期'));
    await tester.pumpAndSettle();
    expect(find.text('筛选结果（2）'), findsOneWidget);
    repository.settings = const ExpirySettings(near: 10);
    container.invalidate(expirySettingsProvider);
    await tester.pumpAndSettle();
    expect(find.text('10 天内到期'), findsOneWidget);
    expect(find.text('筛选结果（3）'), findsOneWidget);
    await tester.tap(find.text('清除筛选'));
    await tester.pumpAndSettle();
    expect(find.text('全部物品（5）'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '储物柜');
    await tester.pumpAndSettle();
    expect(find.text('筛选结果（5）'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '不存在');
    await tester.pumpAndSettle();
    expect(find.text('没有找到匹配的物品'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('category page shows counts and searches descriptions', (
    tester,
  ) async {
    await pump(tester, const InventoryCategoriesPage());
    await screenshot(tester, 'categories');
    expect(find.text('2 件'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '储藏');
    await tester.pumpAndSettle();
    expect(find.text('厨房'), findsOneWidget);
    expect(find.text('日常用品'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'reminder editor rejects invalid ranges and persists valid days',
    (tester) async {
      final repository = RecordingRepository();
      await pump(tester, const ExpiryDaysPage(), repository: repository);
      await screenshot(tester, 'expiry_settings');
      await tester.tap(find.text('近期提醒'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '20');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('请输入 1–36500 的整数，且近期 < 中期 < 长期'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '3');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(repository.settings.near, 3);
      expect(find.text('3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'out-of-range automatic expiry clears the old date and prevents save',
    (tester) async {
      final repository = RecordingRepository();
      await pump(
        tester,
        InventoryAddItemPage(
          item: InventoryItem(
            id: 42,
            name: '测试物品',
            productionDate: DateTime(2026, 1, 1),
            expiryDate: DateTime(2027, 1, 1),
            storageDuration: '1',
            storageUnit: '年',
          ),
        ),
        repository: repository,
      );
      await tester.ensureVisible(find.widgetWithText(TextFormField, '保存时长'));
      await tester.enterText(find.widgetWithText(TextFormField, '保存时长'), '80');
      await tester.pumpAndSettle();
      expect(find.text('计算结果超过 2100 年，请调整保存时长或手动选择到期日期'), findsOneWidget);
      expect(find.text('请选择到期日期'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('保存物品'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('保存物品'));
      await tester.pumpAndSettle();
      expect(repository.saved, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'item form keeps a green toolbar and save action while scrolling',
    (tester) async {
      await pump(tester, const InventoryAddItemPage());
      Color? toolbarColor() => tester
          .widget<Material>(
            find
                .descendant(
                  of: find.byType(AppBar),
                  matching: find.byType(Material),
                )
                .first,
          )
          .color;
      expect(toolbarColor(), AppColors.primary);
      expect(find.text('保存物品').hitTestable(), findsOneWidget);
      await screenshot(tester, 'item_form_empty');
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();
      expect(toolbarColor(), AppColors.primary);
      expect(find.text('保存物品').hitTestable(), findsOneWidget);
      await screenshot(tester, 'item_form_details');

      // A fixed save action must still validate fields above the visible area.
      await tester.tap(find.text('保存物品'));
      await tester.pumpAndSettle();
      expect(find.text('请输入名称').hitTestable(), findsOneWidget);

      tester.view.physicalSize = const Size(320, 740);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('自动计算'));
      await tester.pumpAndSettle();
      await screenshot(tester, 'item_form_narrow');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('editing and copying retain fields and use correct identity', (
    tester,
  ) async {
    final repository = RecordingRepository();
    final original = InventoryItem(
      id: 42,
      name: '冰片糖',
      expiryDate: DateTime(2027, 1, 1),
      categoryId: 1,
      category: '厨房',
      productionDate: DateTime(2026, 1, 1),
      storageDuration: '1',
      storageUnit: '年',
      remark: '密封保存',
    );
    await pump(
      tester,
      InventoryAddItemPage(item: original),
      repository: repository,
    );
    await screenshot(tester, 'item_form');
    await tester.scrollUntilVisible(
      find.text('保存物品'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('保存物品'));
    await tester.pumpAndSettle();
    expect(repository.saved?.id, 42);
    expect(repository.saved?.categoryId, 1);
    expect(repository.saved?.storageUnit, '年');
    expect(repository.saved?.remark, '密封保存');
    await pump(
      tester,
      InventoryAddItemPage(item: original, copy: true),
      repository: repository,
    );
    await tester.scrollUntilVisible(
      find.text('保存物品'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('保存物品'));
    await tester.pumpAndSettle();
    expect(repository.saved?.id, isNull);
    expect(repository.saved?.name, '冰片糖');
    expect(tester.takeException(), isNull);
  });
}
