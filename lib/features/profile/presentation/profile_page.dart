import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/account_entry.dart';
import '../../../models/inventory_settings.dart';
import '../../accounting/presentation/account_categories_page.dart';
import '../../inventory/presentation/inventory_categories_page.dart';
import 'expiry_days_page.dart';
import 'recipe_categories_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({
    super.key,
    this.onInventoryCategorySelected,
    this.onRecipeCategorySelected,
    this.onAccountCategorySelected,
  });
  final ValueChanged<InventoryCategory>? onInventoryCategorySelected;
  final ValueChanged<String>? onRecipeCategorySelected;
  final ValueChanged<AccountCategory>? onAccountCategorySelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        Text(
          '个人设置',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppColors.primary,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          '我的',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 20),
        Card(
          elevation: 0,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.menu_book_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('菜谱分类设置'),
                subtitle: const Text('管理菜谱的分类'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final category = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RecipeCategoriesPage(),
                    ),
                  );
                  if (category != null && context.mounted) {
                    onRecipeCategorySelected?.call(category);
                  }
                },
              ),
              const Divider(
                height: 1,
                indent: 56,
                endIndent: 16,
                color: AppColors.border,
              ),
              ListTile(
                leading: const Icon(
                  Icons.category_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('万物分类设置'),
                subtitle: const Text('管理万物的物品分类'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final category = await Navigator.push<InventoryCategory>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const InventoryCategoriesPage(),
                    ),
                  );
                  if (category != null && context.mounted) {
                    onInventoryCategorySelected?.call(category);
                  }
                },
              ),
              const Divider(
                height: 1,
                indent: 56,
                endIndent: 16,
                color: AppColors.border,
              ),
              ListTile(
                leading: const Icon(
                  Icons.receipt_long_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('记账分类设置'),
                subtitle: const Text('管理支出和收入的分类及排序'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final category = await Navigator.push<AccountCategory>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AccountCategoriesPage(),
                    ),
                  );
                  if (category != null && context.mounted) {
                    onAccountCategorySelected?.call(category);
                  }
                },
              ),
              const Divider(
                height: 1,
                indent: 56,
                endIndent: 16,
                color: AppColors.border,
              ),
              ListTile(
                leading: const Icon(
                  Icons.event_available_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('过期天数设置'),
                subtitle: const Text('调整万物顶部的到期提醒区间'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ExpiryDaysPage()),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
