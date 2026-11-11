import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/recipe_providers.dart';
import '../../inventory/presentation/inventory_categories_page.dart';
import 'expiry_days_page.dart';
import 'recipe_categories_page.dart';
import 'data_transfer_page.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        Text(
          '个人厨房',
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
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RecipeCategoriesPage(),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.category_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('万物分类设置'),
                subtitle: const Text('管理万物的物品分类'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const InventoryCategoriesPage(),
                  ),
                ),
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
              ListTile(
                leading: const Icon(
                  Icons.delete_sweep_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('清空全部数据'),
                subtitle: const Text('永久删除本机上的所有菜谱'),
                onTap: () => _clear(context, ref),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Card(
          elevation: 0,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('记录习惯', style: TextStyle(fontWeight: FontWeight.w800)),
                SizedBox(height: 6),
                Text(
                  '每次完成后补充评分、成品照片和下次改进方向，更容易判断哪个版本真正适合你。',
                  style: TextStyle(color: AppColors.muted, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final first =
        await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('清空全部数据？'),
            content: const Text('所有菜谱、版本、材料、步骤和成品记录都会被删除。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('继续'),
              ),
            ],
          ),
        ) ??
        false;
    if (!first || !context.mounted) return;
    final second =
        await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('再次确认'),
            content: const Text('此操作无法撤销，确定永久清空吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('保留数据'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认清空'),
              ),
            ],
          ),
        ) ??
        false;
    if (!second) return;
    await (await ref.read(repositoryProvider.future)).clearAll();
    ref.invalidate(recipesProvider);
    ref.invalidate(statsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('本地数据已清空')));
    }
  }
}
