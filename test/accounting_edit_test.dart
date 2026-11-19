import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noodles/core/database/accounting_repository.dart';
import 'package:noodles/core/theme/app_theme.dart';
import 'package:noodles/features/accounting/presentation/accounting_page.dart';
import 'package:noodles/models/account_entry.dart';
import 'package:noodles/providers/accounting_providers.dart';
import 'package:sqflite/sqflite.dart';

class EntryDatabase implements Database {
  final rows = <int, Map<String, Object?>>{};
  bool fail = false;

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    if (fail) throw StateError('save failed');
    final id = rows.length + 1;
    rows[id] = {...values, 'id': id};
    return id;
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    if (fail) throw StateError('save failed');
    expect(table, 'account_entries');
    expect(where, 'id = ?');
    final id = whereArgs!.single as int;
    if (!rows.containsKey(id)) return 0;
    rows[id] = {...rows[id]!, ...values};
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class EntryRepository extends AccountingRepository {
  EntryRepository(this.storage) : super(storage);
  final EntryDatabase storage;
  final categories = <AccountCategory>[
    const AccountCategory(id: 1, name: '餐饮', type: AccountType.expense),
    const AccountCategory(id: 2, name: '工资', type: AccountType.income),
  ];

  @override
  Future<List<AccountCategory>> listCategories(AccountType type) async =>
      categories.where((category) => category.type == type).toList();

  @override
  Future<List<AccountEntry>> listEntries(DateTime start, DateTime end) async =>
      storage.rows.values
          .map((row) {
            final category = categories
                .where((category) => category.id == row['category_id'])
                .firstOrNull;
            return AccountEntry.fromMap({...row, 'category': category?.name});
          })
          .where(
            (entry) => !entry.date.isBefore(start) && !entry.date.isAfter(end),
          )
          .toList();
}

void main() {
  late EntryDatabase database;
  late EntryRepository repository;
  late AccountEntry original;

  setUp(() async {
    database = EntryDatabase();
    repository = EntryRepository(database);
    final now = DateTime.now();
    original = AccountEntry(
      id: 1,
      type: AccountType.expense,
      amountCents: 1234,
      categoryId: 1,
      category: '餐饮',
      date: DateTime(now.year, now.month, 10),
      note: '午餐',
    );
    await repository.saveEntry(
      AccountEntry(
        type: original.type,
        amountCents: original.amountCents,
        categoryId: original.categoryId,
        category: original.category,
        date: original.date,
        note: original.note,
      ),
    );
  });

  Future<void> pump(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountingRepositoryProvider.overrideWith((_) async => repository),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: page),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('new expenses and incomes save the selected payment method', (
    tester,
  ) async {
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const AccountEntryPage()),
          ),
          child: const Text('新增账单'),
        ),
      ),
    );
    final paymentField = find.byType(DropdownButtonFormField<String>);
    for (final (type, label, method) in [
      (AccountType.expense, '支出', '微信'),
      (AccountType.income, '收入', '现金'),
    ]) {
      await tester.tap(find.text('新增账单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '12.50');
      await tester.tap(paymentField);
      await tester.pumpAndSettle();
      await tester.tap(find.text(method).last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('保存记录'));
      await tester.tap(find.text('保存记录'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountEntryPage), findsNothing);
      final saved = AccountEntry.fromMap(database.rows.values.last);
      expect(saved.type, type);
      expect(saved.paymentMethod, method);
    }
  });

  testWidgets(
    'tap entry, edit all fields and refresh totals without duplicates',
    (tester) async {
      await pump(tester, const AccountingPage());
      final entry = find.byType(Dismissible);
      await tester.ensureVisible(entry);
      expect(
        find.text('${database.rows[1]!['date']} · 午餐 · 餐饮'),
        findsOneWidget,
      );
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.text('编辑账单'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        '12.34',
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '备注'))
            .controller!
            .text,
        '午餐',
      );
      await tester.enterText(find.byType(TextFormField).first, '56.78');
      await tester.enterText(find.widgetWithText(TextField, '备注'), '报销到账');
      await tester.tap(find.text('收入'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('工资'));
      await tester.pumpAndSettle();
      expect(find.text('选择收入分类'), findsOneWidget);
      await tester.tap(find.text('工资'));
      await tester.pumpAndSettle();
      final newDate = DateTime(original.date.year, original.date.month, 11);
      await tester.tap(find.byIcon(Icons.calendar_today_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('11').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('支付宝').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('保存记录'));
      await tester.tap(find.text('保存记录'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountEntryPage), findsNothing);
      expect(database.rows.length, 1);
      final saved = database.rows[1]!;
      expect(saved['amount_cents'], 5678);
      expect(saved['type'], 'income');
      expect(saved['category_id'], 2);
      expect(saved['note'], '报销到账');
      expect(DateTime.parse(saved['date'] as String), newDate);
      expect(find.text('${saved['date']} · 报销到账 · 工资 · 支付宝'), findsOneWidget);
      expect(find.text('+¥56.78'), findsOneWidget);
      expect(find.text('¥0.00'), findsOneWidget);
      expect(find.text('¥56.78'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancel and failed save preserve original record and form', (
    tester,
  ) async {
    await pump(tester, const AccountingPage());
    await tester.ensureVisible(find.byType(Dismissible));
    await tester.tap(find.byType(Dismissible));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '98.76');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(database.rows[1]!['amount_cents'], 1234);
    await tester.ensureVisible(find.byType(Dismissible));
    await tester.tap(find.byType(Dismissible));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '98.76');
    database.fail = true;
    await tester.ensureVisible(find.text('保存记录'));
    await tester.tap(find.text('保存记录'));
    await tester.pumpAndSettle();
    expect(find.text('编辑账单'), findsOneWidget);
    expect(find.text('保存失败，请重试'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      '98.76',
    );
    expect(database.rows[1]!['amount_cents'], 1234);
    expect(database.rows.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing uncategorized entry preserves its category', (
    tester,
  ) async {
    final uncategorized = AccountEntry(
      id: 1,
      type: original.type,
      amountCents: original.amountCents,
      categoryId: null,
      category: '未分类',
      date: original.date,
      note: original.note,
    );
    await pump(tester, AccountEntryPage(entry: uncategorized));
    expect(find.text('未分类'), findsOneWidget);
    await tester.ensureVisible(find.text('保存记录'));
    await tester.tap(find.text('保存记录'));
    await tester.pumpAndSettle();
    expect(database.rows[1]!['category_id'], isNull);
    expect(database.rows.length, 1);
  });

  test(
    'updating a deleted entry fails without inserting a replacement',
    () async {
      database.rows.clear();
      await expectLater(repository.saveEntry(original), throwsStateError);
      expect(database.rows, isEmpty);
    },
  );
}
