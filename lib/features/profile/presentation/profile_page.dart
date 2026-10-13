import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/recipe.dart';
import '../../../providers/recipe_providers.dart';
import '../../recipes/presentation/recipe_detail_page.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipes = ref.watch(recipesProvider).valueOrNull ?? const <Recipe>[];
    return ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 24), children: [
      Text('个人厨房', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.primary, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
      Text('我的', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 20),
      const Card(elevation: 0, child: ListTile(leading: CircleAvatar(backgroundColor: AppColors.deep, child: Text('食', style: TextStyle(color: Color(0xFFF4D2A6)))), title: Text('我的厨房日志', style: TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('把每次尝试，积累成自己的味道。'))),
      const SizedBox(height: 12),
      ref.watch(statsProvider).when(loading: () => const LinearProgressIndicator(), error: (_, _) => const Text('统计加载失败'), data: (stats) => GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2, childAspectRatio: 2.1, children: [_Stat('${stats['recipes']}', '菜谱总数'), _Stat('${stats['versions']}', '版本总数'), _Stat('${stats['favorites']}', '收藏数量'), _Stat('${stats['best']}', '最佳版本')])),
      const SizedBox(height: 18),
      _recipeSection(context, ref, '我的收藏', recipes.where((r) => r.isFavorite).toList()),
      const SizedBox(height: 12),
      _recipeSection(context, ref, '最近编辑', recipes.take(3).toList()),
      const SizedBox(height: 12),
      Card(elevation: 0, child: Column(children: [
        _item(context, Icons.upload_file_outlined, '导出本地数据', '即将支持'),
        _item(context, Icons.download_outlined, '导入本地数据', '即将支持'),
        ListTile(leading: const Icon(Icons.delete_sweep_outlined, color: AppColors.primary), title: const Text('清空全部数据'), subtitle: const Text('永久删除本机上的所有菜谱'), onTap: () => _clear(context, ref)),
      ])),
      const SizedBox(height: 16),
      const Card(elevation: 0, child: Padding(padding: EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('记录习惯', style: TextStyle(fontWeight: FontWeight.w800)), SizedBox(height: 6), Text('每次完成后补充评分、成品照片和下次改进方向，更容易判断哪个版本真正适合你。', style: TextStyle(color: AppColors.muted, height: 1.5))]))),
    ]);
  }

  Widget _recipeSection(BuildContext context, WidgetRef ref, String title, List<Recipe> recipes) => Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 6), if (recipes.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('暂无记录', style: TextStyle(color: AppColors.muted))) else ...recipes.map((r) => ListTile(contentPadding: EdgeInsets.zero, dense: true, leading: const Icon(Icons.menu_book_outlined, color: AppColors.primary), title: Text(r.title), subtitle: Text(r.category), trailing: const Icon(Icons.chevron_right), onTap: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => RecipeDetailPage(recipeId: r.id))); ref.invalidate(recipesProvider); ref.invalidate(statsProvider); }))])));
  Widget _item(BuildContext context, IconData icon, String title, String subtitle) => ListTile(leading: Icon(icon, color: AppColors.primary), title: Text(title), subtitle: Text(subtitle), onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('该本地功能即将支持'))));

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final first = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('清空全部数据？'), content: const Text('所有菜谱、版本、材料、步骤和成品记录都会被删除。'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('继续'))])) ?? false;
    if (!first || !context.mounted) return;
    final second = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('再次确认'), content: const Text('此操作无法撤销，确定永久清空吗？'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('保留数据')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确认清空'))])) ?? false;
    if (!second) return;
    await (await ref.read(repositoryProvider.future)).clearAll();
    ref.invalidate(recipesProvider); ref.invalidate(statsProvider);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('本地数据已清空')));
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value, label;
  @override Widget build(BuildContext context) => Card(elevation: 0, child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(value, style: const TextStyle(color: AppColors.primary, fontSize: 22, fontWeight: FontWeight.w800)), Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12))])));
}
