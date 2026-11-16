import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noodles/core/database/inventory_repository.dart';
import 'package:noodles/features/inventory/presentation/inventory_categories_page.dart';
import 'package:noodles/models/inventory_settings.dart';
import 'package:noodles/providers/inventory_providers.dart';

class CategoryRepository implements InventoryRepository {
  final categories = [
    const InventoryCategory(id: 1, name: '食品'),
    const InventoryCategory(id: 2, name: '日用品', sortOrder: 2),
  ];

  @override
  Future<List<InventoryCategory>> listCategories() async =>
      [...categories]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  @override
  Future<void> saveCategory(InventoryCategory category) async {
    categories[categories.indexWhere((c) => c.id == category.id)] = category;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('saving category order immediately reorders the settings list', (
    tester,
  ) async {
    final repository = CategoryRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inventoryRepositoryProvider.overrideWith((_) async => repository),
        ],
        child: const MaterialApp(home: InventoryCategoriesPage()),
      ),
    );
    await tester.pumpAndSettle();

    void expectOrder(String first, String second) => expect(
      tester.getTopLeft(find.text(first)).dy,
      lessThan(tester.getTopLeft(find.text(second)).dy),
    );

    expectOrder('食品', '日用品');
    await tester.tap(find.byTooltip('分类操作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑分类'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '排序'), '10');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(repository.categories.first.sortOrder, 10);
    expect(find.text('排序 10'), findsOneWidget);
    expect(find.text('0 件'), findsNWidgets(2));
    expectOrder('日用品', '食品');

    await tester.tap(find.byTooltip('分类操作').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑分类'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, '排序'))
          .controller!
          .text,
      '10',
    );
    expect(tester.takeException(), isNull);
  });
}
