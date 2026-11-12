import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/inventory_repository.dart';
import '../models/inventory_item.dart';
import '../models/inventory_settings.dart';
import 'recipe_providers.dart';

final inventoryRepositoryProvider = FutureProvider<InventoryRepository>(
  (ref) async =>
      InventoryRepository((await ref.watch(repositoryProvider.future)).db),
);
final inventoryItemsProvider = FutureProvider<List<InventoryItem>>(
  (ref) async =>
      (await ref.watch(inventoryRepositoryProvider.future)).listItems(),
);
final inventoryCategoriesProvider = FutureProvider<List<InventoryCategory>>(
  (ref) async =>
      (await ref.watch(inventoryRepositoryProvider.future)).listCategories(),
);
final expirySettingsProvider = FutureProvider<ExpirySettings>(
  (ref) async =>
      (await ref.watch(inventoryRepositoryProvider.future)).expirySettings(),
);

void refreshInventory(WidgetRef ref) {
  ref.invalidate(inventoryItemsProvider);
  ref.invalidate(inventoryCategoriesProvider);
}
