import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noodles/core/theme/app_theme.dart';
import 'package:noodles/core/widgets/active_filter_bar.dart';
import 'package:noodles/features/recipes/presentation/recipes_home_page.dart';
import 'package:noodles/models/inventory_item.dart';
import 'package:noodles/models/inventory_settings.dart';
import 'package:noodles/providers/accounting_providers.dart';
import 'package:noodles/providers/inventory_providers.dart';
import 'package:noodles/providers/recipe_providers.dart';

import 'recipes_test.dart' show RecipeStore;

Future<void> pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  final store = RecipeStore()..categories.add('空分类');
  final now = DateTime.now();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWith((_) async => store),
        inventoryItemsProvider.overrideWith(
          (_) async => [
            InventoryItem(
              id: 1,
              name: '番茄',
              categoryId: 1,
              category: '食品',
              expiryDate: DateTime(now.year, now.month, now.day + 1),
            ),
            InventoryItem(
              id: 2,
              name: '番茄种子',
              expiryDate: DateTime(now.year, now.month, now.day + 60),
            ),
          ],
        ),
        inventoryCategoriesProvider.overrideWith(
          (_) async => const [
            InventoryCategory(id: 1, name: '食品', itemCount: 1),
            InventoryCategory(id: 2, name: '空分类'),
          ],
        ),
        expirySettingsProvider.overrideWith(
          (_) async => const ExpirySettings(),
        ),
        accountEntriesProvider.overrideWith((_, range) async => []),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const RecipesHomePage()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> selectCategory(
  WidgetTester tester,
  String settings,
  String category,
) async {
  await tester.tap(find.text('我的'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(settings));
  await tester.pumpAndSettle();
  await tester.tap(find.text(category));
  await tester.pumpAndSettle();
}

void main() {
  for (final isRecipe in [true, false]) {
    final settings = isRecipe ? '菜谱分类设置' : '万物分类设置';
    final category = isRecipe ? '面食' : '食品';
    testWidgets('$settings shows removable filters and clears them together', (
      tester,
    ) async {
      await pumpHome(tester);
      await selectCategory(tester, settings, category);
      final bar = find.byType(ActiveFilterBar);
      expect(bar, findsOneWidget);
      expect(find.text('分类：$category'), findsOneWidget);
      expect(find.text('清除筛选'), findsOneWidget);
      expect(find.text(isRecipe ? '筛选结果（2）' : '筛选结果（1）'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '番茄');
      await tester.pumpAndSettle();
      expect(find.text('搜索：番茄'), findsOneWidget);
      if (!isRecipe) {
        await tester.tap(find.text('7 天内到期'));
        await tester.pumpAndSettle();
        expect(find.text('到期：7 天内到期'), findsOneWidget);
      }

      await tester.tap(find.byTooltip('清除分类筛选'));
      await tester.pumpAndSettle();
      expect(find.text('分类：$category'), findsNothing);
      expect(find.text('搜索：番茄'), findsOneWidget);
      if (!isRecipe) {
        expect(find.text('到期：7 天内到期'), findsOneWidget);
        await tester.tap(find.byTooltip('清除到期筛选'));
        await tester.pumpAndSettle();
        expect(find.text('到期：7 天内到期'), findsNothing);
        expect(find.text('筛选结果（2）'), findsOneWidget);
      }
      final clearSearch = find.descendant(
        of: bar,
        matching: find.byTooltip('清除搜索'),
      );
      await tester.tap(clearSearch);
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsNothing);
      expect(find.text('清除筛选'), findsNothing);
      expect(find.text(isRecipe ? '我的菜谱（3）' : '全部物品（2）'), findsOneWidget);

      await selectCategory(tester, settings, category);
      await tester.enterText(find.byType(TextField).first, '不存在');
      await tester.pumpAndSettle();
      if (!isRecipe) {
        await tester.tap(find.text('7 天内到期'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('清除筛选'));
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsNothing);
      expect(find.text('清除筛选'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
      expect(find.text(isRecipe ? '我的菜谱（3）' : '全部物品（2）'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$settings keeps an empty category visible and clearable', (
      tester,
    ) async {
      await pumpHome(tester);
      await selectCategory(tester, settings, '空分类');
      expect(find.text('分类：空分类'), findsOneWidget);
      expect(find.text('清除筛选'), findsOneWidget);
      expect(find.text(isRecipe ? '没有找到匹配的菜谱' : '没有找到匹配的物品'), findsOneWidget);
      expect(find.text('筛选结果（0）'), findsOneWidget);
      await tester.tap(find.byTooltip('清除分类筛选'));
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsNothing);
      expect(find.text(isRecipe ? '我的菜谱（3）' : '全部物品（2）'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
