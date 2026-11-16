import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noodles/core/theme/app_theme.dart';
import 'package:noodles/features/accounting/presentation/account_categories_page.dart';
import 'package:noodles/features/accounting/presentation/accounting_page.dart';
import 'package:noodles/features/recipes/presentation/recipes_home_page.dart';
import 'package:noodles/models/account_entry.dart';
import 'package:noodles/models/inventory_settings.dart';
import 'package:noodles/providers/accounting_providers.dart';
import 'package:noodles/providers/inventory_providers.dart';
import 'package:noodles/providers/recipe_providers.dart';

const categories = [
  AccountCategory(id: 1, name: '其他', type: AccountType.expense),
  AccountCategory(id: 2, name: '其他', type: AccountType.income),
  AccountCategory(id: 3, name: '交通', type: AccountType.expense),
];

Future<void> pumpPage(
  WidgetTester tester,
  Widget page,
  List<AccountEntry> entries,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        recipesProvider.overrideWith((_) async => []),
        recipeCategoriesProvider.overrideWith((_) async => []),
        inventoryItemsProvider.overrideWith((_) async => []),
        inventoryCategoriesProvider.overrideWith((_) async => []),
        expirySettingsProvider.overrideWith(
          (_) async => const ExpirySettings(),
        ),
        accountCategoriesProvider.overrideWith(
          (_, type) async =>
              categories.where((category) => category.type == type).toList(),
        ),
        accountEntriesProvider.overrideWith(
          (_, range) async => entries
              .where(
                (entry) =>
                    !entry.date.isBefore(range.start) &&
                    !entry.date.isAfter(range.end),
              )
              .toList(),
        ),
      ],
      child: MaterialApp(theme: AppTheme.light, home: page),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final type in AccountType.values) {
    testWidgets('settings opens and filters accounting by ${type.name}', (
      tester,
    ) async {
      final now = DateTime.now();
      final entries = [
        for (final (index, category) in categories.indexed)
          AccountEntry(
            id: index + 1,
            type: category.type,
            amountCents: (index + 1) * 100,
            categoryId: category.id,
            category: category.name,
            date: DateTime(now.year, now.month, 1),
            note: '',
          ),
        AccountEntry(
          id: 4,
          type: AccountType.expense,
          amountCents: 400,
          categoryId: null,
          category: '未分类',
          date: DateTime(now.year, now.month, 1),
          note: '',
        ),
      ];
      await pumpPage(tester, const RecipesHomePage(), entries);

      Future<void> selectCategory(AccountType selectedType) async {
        await tester.tap(find.text('我的'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('记账分类设置'));
        await tester.pumpAndSettle();
        if (selectedType == AccountType.income) {
          await tester.tap(find.text('收入分类'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('其他'));
        await tester.pumpAndSettle();
      }

      await selectCategory(type);
      final isExpense = type == AccountType.expense;
      expect(find.byType(AccountCategoriesPage), findsNothing);
      expect(find.byTooltip('记一笔'), findsOneWidget);
      expect(find.text('分类：${isExpense ? '支出' : '收入'} · 其他'), findsOneWidget);
      expect(find.text('收支明细（1）'), findsOneWidget);
      expect(find.byType(Dismissible), findsOneWidget);
      expect(find.byKey(ValueKey(isExpense ? 1 : 2)), findsOneWidget);
      expect(find.text(isExpense ? '¥1.00' : '¥2.00'), findsNWidgets(2));
      expect(find.text('¥0.00'), findsOneWidget);

      await tester.tap(find.byTooltip(isExpense ? '清除分类筛选' : '清除筛选'));
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsNothing);
      expect(find.text('收支明细（4）'), findsOneWidget);
      expect(find.text('¥8.00'), findsOneWidget);

      await selectCategory(type);
      expect(find.text('收支明细（1）'), findsOneWidget);
      expect(find.byKey(ValueKey(isExpense ? 1 : 2)), findsOneWidget);

      await selectCategory(
        isExpense ? AccountType.income : AccountType.expense,
      );
      expect(find.text('收支明细（1）'), findsOneWidget);
      expect(find.byKey(ValueKey(isExpense ? 2 : 1)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty category filter is visible and can be cleared', (
    tester,
  ) async {
    await pumpPage(
      tester,
      Scaffold(body: AccountingPage(initialCategory: categories.first)),
      [],
    );
    expect(find.text('分类：支出 · 其他'), findsOneWidget);
    expect(find.text('收支明细（0）'), findsOneWidget);
    expect(find.text('所选分类在此日期内还没有记录'), findsOneWidget);
    await tester.tap(find.byTooltip('清除分类筛选'));
    await tester.pumpAndSettle();
    expect(find.text('还没有收支记录'), findsOneWidget);
    expect(find.byType(InputChip), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
