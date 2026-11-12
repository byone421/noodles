import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/inventory_settings.dart';
import '../../inventory/presentation/inventory_categories_page.dart';
import 'expiry_days_page.dart';
import 'recipe_categories_page.dart';
import 'data_transfer_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({
    super.key,
    this.onInventoryCategorySelected,
    this.onRecipeCategorySelected,
  });
  final ValueChanged<InventoryCategory>? onInventoryCategorySelected;
  final ValueChanged<String>? onRecipeCategorySelected;

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
          style: Theme.of(context).textTheme.headlineLarge
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
              const Divider(
                height: 1,
                indent: 56,
                endIndent: 16,
                color: AppColors.border,
              ),
              ListTile(
                leading: const Icon(
                  Icons.upload_file_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('导出菜谱数据'),
                subtitle: const Text('备份菜谱、分类、全部版本和图片'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const DataTransferPage(importing: false, recipes: true),
                  ),
                ),
              ),
              const Divider(
                height: 1,
                indent: 56,
                endIndent: 16,
                color: AppColors.border,
              ),
              ListTile(
                leading: const Icon(
                  Icons.download_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('导入菜谱数据'),
                subtitle: const Text('从 JSON 恢复菜谱、版本和图片'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const DataTransferPage(importing: true, recipes: true),
                  ),
                ),
              ),
              const Divider(
                height: 1,
                indent: 56,
                endIndent: 16,
                color: AppColors.border,
              ),
              ListTile(
                leading: const Icon(
                  Icons.upload_file_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('导出万物数据'),
                subtitle: const Text('备份物品、分类和图片'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DataTransferPage(importing: false),
                  ),
                ),
              ),
              const Divider(
                height: 1,
                indent: 56,
                endIndent: 16,
                color: AppColors.border,
              ),
              ListTile(
                leading: const Icon(
                  Icons.download_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('导入万物数据'),
                subtitle: const Text('兼容老项目 CSV 和万物备份'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DataTransferPage(importing: true),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
