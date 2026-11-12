import 'dart:convert';

class InventoryItem {
  const InventoryItem({
    this.id,
    required this.name,
    required this.expiryDate,
    this.updatedAt,
    this.categoryId,
    this.category = '',
    this.location = '',
    this.quantity = '',
    this.productionDate,
    this.storageDuration = '',
    this.storageUnit = '天',
    this.purchaseDate,
    this.purchasePrice = '',
    this.remark = '',
    this.imagePaths = const [],
  });
  final int? id, categoryId;
  final String name, category, location, quantity;
  final DateTime expiryDate;
  final DateTime? productionDate, purchaseDate, updatedAt;
  final String storageDuration, storageUnit, purchasePrice, remark;
  final List<String> imagePaths;

  int remainingDaysAt(DateTime now) => DateTime.utc(
    expiryDate.year,
    expiryDate.month,
    expiryDate.day,
  ).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
  int get remainingDays => remainingDaysAt(DateTime.now());
  bool matchesRange(int? days, {DateTime? now}) {
    final remaining = remainingDaysAt(now ?? DateTime.now());
    return days == null ||
        (days < 0 ? remaining < 0 : remaining >= 0 && remaining <= days);
  }

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'expiry_date': expiryDate.toIso8601String(),
    'updated_at': updatedAt?.toUtc().toIso8601String(),
    'category_id': categoryId,
    'location': location,
    'quantity': quantity,
    'production_date': productionDate?.toIso8601String(),
    'storage_duration': storageDuration,
    'storage_unit': storageUnit,
    'purchase_date': purchaseDate?.toIso8601String(),
    'purchase_price': purchasePrice,
    'remark': remark,
    'image_paths': jsonEncode(imagePaths),
  };
  factory InventoryItem.fromMap(Map<String, Object?> map) => InventoryItem(
    id: map['id'] as int,
    name: map['name'] as String,
    expiryDate: DateTime.parse(map['expiry_date'] as String),
    updatedAt: map['updated_at'] == null
        ? null
        : DateTime.parse(map['updated_at'] as String),
    categoryId: map['category_id'] as int?,
    category: map['category_name'] as String? ?? '',
    location: map['location'] as String,
    quantity: map['quantity'] as String,
    productionDate: DateTime.tryParse(map['production_date'] as String? ?? ''),
    storageDuration: map['storage_duration'] as String,
    storageUnit: map['storage_unit'] as String,
    purchaseDate: DateTime.tryParse(map['purchase_date'] as String? ?? ''),
    purchasePrice: map['purchase_price'] as String,
    remark: map['remark'] as String,
    imagePaths: (jsonDecode(map['image_paths'] as String) as List)
        .cast<String>(),
  );
}

// Match the old app: calendar months/years, including the production day.
DateTime calculateInventoryExpiry(
  DateTime production,
  int duration,
  String unit,
) {
  if (duration <= 0 || duration > 36500) throw ArgumentError('保存时长须为 1–36500');
  final start = DateTime(production.year, production.month, production.day);
  DateTime end;
  switch (unit) {
    case '天':
      end = DateTime(start.year, start.month, start.day + duration);
    case '周':
      end = DateTime(start.year, start.month, start.day + duration * 7);
    case '月':
    case '年':
      final month = DateTime(
        start.year + (unit == '年' ? duration : 0),
        start.month + (unit == '月' ? duration : 0),
      );
      final lastDay = DateTime(month.year, month.month + 1, 0).day;
      end = DateTime(
        month.year,
        month.month,
        start.day > lastDay ? lastDay : start.day,
      );
    default:
      throw ArgumentError('不支持的时间单位');
  }
  return DateTime(end.year, end.month, end.day - 1);
}
