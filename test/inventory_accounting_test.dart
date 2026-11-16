import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noodles/core/database/accounting_repository.dart';
import 'package:noodles/core/database/inventory_repository.dart';
import 'package:noodles/core/theme/app_theme.dart';
import 'package:noodles/features/accounting/presentation/accounting_page.dart';
import 'package:noodles/features/inventory/presentation/inventory_add_item_page.dart';
import 'package:noodles/models/account_entry.dart';
import 'package:noodles/models/inventory_item.dart';
import 'package:noodles/models/inventory_settings.dart';
import 'package:noodles/providers/accounting_providers.dart';
import 'package:noodles/providers/inventory_providers.dart';

class _InventoryRepository implements InventoryRepository {
  final items = <InventoryItem>[];
  Completer<void>? pendingSave;
  bool fail = false;

  @override
  Future<void> saveItem(InventoryItem item) async {
    await pendingSave?.future;
    if (fail) throw StateError('save failed');
    items.add(item);
  }

  @override
  Future<List<InventoryItem>> listItems() async => items;

  @override
  Future<List<InventoryCategory>> listCategories() async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AccountingRepository implements AccountingRepository {
  final entries = <AccountEntry>[];
  int loads = 0;

  @override
  Future<List<AccountCategory>> listCategories(AccountType type) async => [
    AccountCategory(id: 1, name: '购物', type: type),
  ];

  @override
  Future<void> saveEntry(AccountEntry entry) async => entries.add(entry);

  @override
  Future<List<AccountEntry>> listEntries(DateTime start, DateTime end) async {
    loads++;
    return entries.toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _InventoryRepository inventory;
  late _AccountingRepository accounting;

  setUp(() {
    inventory = _InventoryRepository();
    accounting = _AccountingRepository();
  });

  Future<void> openForm(WidgetTester tester, {String amount = '12.50'}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inventoryRepositoryProvider.overrideWith((_) async => inventory),
          accountingRepositoryProvider.overrideWith((_) async => accounting),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Consumer(
            builder: (context, ref, _) {
              final entries = ref.watch(
                accountEntriesProvider((
                  start: DateTime(2026),
                  end: DateTime(2100),
                )),
              );
              return Scaffold(
                body: Column(
                  children: [
                    const Text('物品列表'),
                    Text('账单数量：${entries.valueOrNull?.length ?? 0}'),
                    FilledButton(
                      onPressed: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const InventoryAddItemPage(),
                        ),
                      ),
                      child: const Text('记录物品'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('记录物品'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, '名称 *'),
      '  牛奶  ',
    );
    await tester.ensureVisible(find.text('请选择到期日期'));
    await tester.tap(find.text('请选择到期日期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final amountField = find.widgetWithText(TextFormField, '物品金额');
    await tester.ensureVisible(amountField);
    await tester.enterText(amountField, amount);
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    expect(find.text('购买金额'), findsNothing);
  }

  Future<void> saveItem(WidgetTester tester) async {
    await tester.tap(find.text('保存物品'));
    // The saving indicator keeps animating behind the sync dialog.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('save item first, prefill accounting and refresh saved bills', (
    tester,
  ) async {
    await openForm(tester);
    inventory.pendingSave = Completer<void>();
    await tester.tap(find.text('保存物品'));
    await tester.pump();
    expect(inventory.items, isEmpty);
    expect(find.text('同步到记账？'), findsNothing);
    inventory.pendingSave!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(inventory.items.single.name, '牛奶');
    expect(inventory.items.single.purchasePrice, '12.50');
    expect(find.text('同步到记账？'), findsOneWidget);
    expect(accounting.entries, isEmpty);
    await tester.tap(find.text('去记账'));
    await tester.pumpAndSettle();
    expect(find.text('记一笔'), findsOneWidget);
    expect(find.byType(InventoryAddItemPage), findsNothing);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      '12.50',
    );
    final note = find.widgetWithText(TextField, '备注');
    expect(tester.widget<TextField>(note).controller!.text, '牛奶');
    expect(accounting.entries, isEmpty);
    await tester.enterText(find.byType(TextFormField), '25.80');
    await tester.enterText(note, '牛奶两瓶');
    final loadsBeforeSave = accounting.loads;
    await tester.ensureVisible(find.text('保存记录'));
    await tester.tap(find.text('保存记录'));
    await tester.pumpAndSettle();
    expect(accounting.entries.single.amountCents, 2580);
    expect(accounting.entries.single.note, '牛奶两瓶');
    expect(accounting.entries.single.type, AccountType.expense);
    expect(accounting.entries.single.id, isNull);
    expect(accounting.loads, greaterThan(loadsBeforeSave));
    expect(find.text('账单数量：1'), findsOneWidget);
    expect(find.text('物品列表'), findsOneWidget);
    expect(inventory.items, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel accounting keeps the saved item without a bill', (
    tester,
  ) async {
    await openForm(tester);
    await saveItem(tester);
    await tester.tap(find.text('去记账'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('物品列表'), findsOneWidget);
    expect(find.byType(InventoryAddItemPage), findsNothing);
    expect(find.byType(AccountEntryPage), findsNothing);
    expect(inventory.items, hasLength(1));
    expect(accounting.entries, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('decline sync keeps the saved item without opening accounting', (
    tester,
  ) async {
    await openForm(tester);
    await saveItem(tester);
    await tester.tap(find.text('暂不同步'));
    await tester.pumpAndSettle();
    expect(find.text('物品列表'), findsOneWidget);
    expect(find.byType(AccountEntryPage), findsNothing);
    expect(inventory.items, hasLength(1));
    expect(accounting.entries, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty amount saves directly without a sync prompt', (
    tester,
  ) async {
    await openForm(tester, amount: '');
    await saveItem(tester);
    expect(find.text('同步到记账？'), findsNothing);
    expect(find.text('物品列表'), findsOneWidget);
    expect(inventory.items.single.purchasePrice, '');
    expect(accounting.entries, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid amount prevents saving and syncing', (tester) async {
    await openForm(tester, amount: '1.2.3');
    await saveItem(tester);
    expect(find.text('请输入有效金额（最多两位小数）'), findsOneWidget);
    expect(find.text('同步到记账？'), findsNothing);
    expect(inventory.items, isEmpty);
    expect(accounting.entries, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed item save retains input and only prompts after retry', (
    tester,
  ) async {
    await openForm(tester);
    inventory.fail = true;
    await saveItem(tester);
    expect(find.text('保存失败，内容已保留，请重试'), findsOneWidget);
    expect(find.text('同步到记账？'), findsNothing);
    expect(inventory.items, isEmpty);
    expect(
      tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, '物品金额'))
          .controller!
          .text,
      '12.50',
    );
    inventory.fail = false;
    await saveItem(tester);
    expect(inventory.items, hasLength(1));
    expect(find.text('同步到记账？'), findsOneWidget);
    expect(accounting.entries, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
