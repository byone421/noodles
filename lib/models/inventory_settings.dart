class InventoryCategory {
  const InventoryCategory({
    this.id,
    required this.name,
    this.description = '',
    this.sortOrder = 0,
    this.itemCount = 0,
  });
  final int? id;
  final String name, description;
  final int sortOrder, itemCount;
  factory InventoryCategory.fromMap(Map<String, Object?> row) =>
      InventoryCategory(
        id: row['id'] as int,
        name: row['name'] as String,
        description: row['description'] as String,
        sortOrder: row['sort_order'] as int,
        itemCount: row['item_count'] as int? ?? 0,
      );
}

class ExpirySettings {
  const ExpirySettings({this.near = 7, this.middle = 15, this.far = 30});
  final int near, middle, far;
  List<int> get days => [near, middle, far];
  bool get isValid => near > 0 && near < middle && middle < far && far <= 36500;
}
