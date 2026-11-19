import 'package:sqflite/sqflite.dart';

import '../../models/account_entry.dart';

class AccountingRepository {
  AccountingRepository(this.db);
  final Database db;

  static Future<void> createTables(DatabaseExecutor db) async {
    await db.execute(
      "CREATE TABLE account_categories (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL COLLATE NOCASE, type TEXT NOT NULL CHECK(type IN ('expense', 'income')), sort_order INTEGER NOT NULL DEFAULT 0, UNIQUE(name, type))",
    );
    await db.execute(
      "CREATE TABLE account_entries (id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT NOT NULL CHECK(type IN ('expense', 'income')), amount_cents INTEGER NOT NULL CHECK(amount_cents > 0), category_id INTEGER, date TEXT NOT NULL, note TEXT NOT NULL, payment_method TEXT, FOREIGN KEY(category_id) REFERENCES account_categories(id) ON DELETE SET NULL)",
    );
    await db.execute(
      'CREATE INDEX account_entries_date ON account_entries(date)',
    );
    for (final category in {
      'expense': ['餐饮', '交通', '购物', '居家', '娱乐', '医疗', '其他'],
      'income': ['工资', '奖金', '理财', '兼职', '其他'],
    }.entries) {
      for (var index = 0; index < category.value.length; index++) {
        await db.insert('account_categories', {
          'name': category.value[index],
          'type': category.key,
          'sort_order': index,
        });
      }
    }
  }

  Future<List<AccountCategory>> listCategories(AccountType type) async =>
      (await db.query(
        'account_categories',
        where: 'type = ?',
        whereArgs: [type.name],
        orderBy: 'sort_order, id',
      )).map(AccountCategory.fromMap).toList();

  Future<void> saveCategory(AccountCategory category) async {
    final value = category.name.trim();
    if (value.isEmpty) throw ArgumentError('请输入分类名称');
    if (category.sortOrder < 0 || category.sortOrder > 999999999) {
      throw ArgumentError('排序须为 0–999999999 的整数');
    }
    try {
      final values = {
        'name': value,
        'type': category.type.name,
        'sort_order': category.sortOrder,
      };
      if (category.id == null) {
        await db.insert('account_categories', values);
      } else {
        await db.update(
          'account_categories',
          values,
          where: 'id = ?',
          whereArgs: [category.id],
        );
      }
    } on DatabaseException {
      throw ArgumentError('该分类已存在');
    }
  }

  Future<void> deleteCategory(int id) async =>
      db.delete('account_categories', where: 'id = ?', whereArgs: [id]);

  Future<List<AccountEntry>> listEntries(DateTime start, DateTime end) async =>
      (await db.rawQuery(
        "SELECT e.*, c.name AS category FROM account_entries e LEFT JOIN account_categories c ON c.id = e.category_id WHERE e.date >= ? AND e.date <= ? ORDER BY e.date DESC, e.id DESC",
        [_day(start), _day(end)],
      )).map(AccountEntry.fromMap).toList();

  Future<void> saveEntry(AccountEntry entry) async {
    if (entry.amountCents <= 0) throw ArgumentError('金额必须大于 0');
    final values = {
      'type': entry.type.name,
      'amount_cents': entry.amountCents,
      'category_id': entry.categoryId,
      'date': _day(entry.date),
      'note': entry.note.trim(),
      'payment_method': entry.paymentMethod,
    };
    if (entry.id == null) {
      await db.insert('account_entries', values);
    } else {
      final changed = await db.update(
        'account_entries',
        values,
        where: 'id = ?',
        whereArgs: [entry.id],
      );
      if (changed == 0) throw StateError('记录不存在，请刷新后重试');
    }
  }

  Future<void> deleteEntry(int id) async =>
      db.delete('account_entries', where: 'id = ?', whereArgs: [id]);

  static String _day(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
