enum AccountType { expense, income }

class AccountCategory {
  const AccountCategory({
    this.id,
    required this.name,
    required this.type,
    this.sortOrder = 0,
  });

  final int? id;
  final String name;
  final AccountType type;
  final int sortOrder;

  factory AccountCategory.fromMap(Map<String, Object?> map) => AccountCategory(
    id: map['id'] as int?,
    name: map['name'] as String,
    type: map['type'] == 'income' ? AccountType.income : AccountType.expense,
    sortOrder: map['sort_order'] as int? ?? 0,
  );
}

class AccountEntry {
  const AccountEntry({
    this.id,
    required this.type,
    required this.amountCents,
    required this.categoryId,
    required this.category,
    required this.date,
    required this.note,
  });

  final int? id;
  final AccountType type;
  final int amountCents;
  final int? categoryId;
  final String category;
  final DateTime date;
  final String note;

  factory AccountEntry.fromMap(Map<String, Object?> map) => AccountEntry(
    id: map['id'] as int,
    type: map['type'] == 'income' ? AccountType.income : AccountType.expense,
    amountCents: map['amount_cents'] as int,
    categoryId: map['category_id'] as int?,
    category: map['category'] as String? ?? '未分类',
    date: DateTime.parse(map['date'] as String),
    note: map['note'] as String,
  );
}
