import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/recipe.dart';
import '../../../providers/recipe_providers.dart';
import '../../profile/presentation/profile_page.dart';
import 'new_recipe_page.dart';
import 'recipe_detail_page.dart';

class RecipesHomePage extends ConsumerStatefulWidget {
  const RecipesHomePage({super.key});
  @override
  ConsumerState<RecipesHomePage> createState() => _RecipesHomePageState();
}

class _RecipesHomePageState extends ConsumerState<RecipesHomePage> {
  final search = TextEditingController();
  String category = '全部';
  int tab = 0;
  static const categories = ['全部', '家常菜', '快手菜', '面食', '汤羹', '烘焙'];

  @override
  void dispose() { search.dispose(); super.dispose(); }

  Future<void> _newRecipe() async {
    final id = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const NewRecipePage()));
    if (id != null && mounted) { ref.invalidate(recipesProvider); ref.invalidate(statsProvider); await Navigator.push(context, MaterialPageRoute(builder: (_) => RecipeDetailPage(recipeId: id))); ref.invalidate(recipesProvider); ref.invalidate(statsProvider); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: IndexedStack(index: tab, children: [_recipes(), const ProfilePage()])),
    bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (v) => setState(() => tab = v), backgroundColor: AppColors.background, indicatorColor: AppColors.soft, destinations: const [NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: '菜谱'), NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: '我的')]),
    floatingActionButton: tab == 0 ? FloatingActionButton(onPressed: _newRecipe, tooltip: '新建菜谱', child: const Icon(Icons.add)) : null,
  );

  Widget _recipes() => RefreshIndicator(
    onRefresh: () async => ref.invalidate(recipesProvider),
    child: ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 96), children: [
      Text('我的厨房日志', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.primary, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
      Text('食作簿', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 18),
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: AppColors.deep, borderRadius: BorderRadius.circular(18)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('把每次尝试，变成更好的答案', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)), const SizedBox(height: 6), const Text('记录材料、步骤和成品，找到真正适合你的版本。', style: TextStyle(color: Color(0xFFD9E8DF), height: 1.5)), const SizedBox(height: 16), FilledButton.icon(onPressed: _newRecipe, icon: const Icon(Icons.add), label: const Text('记录一道新菜'), style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF4D2A6), foregroundColor: AppColors.deep))])),
      const SizedBox(height: 16),
      TextField(controller: search, onChanged: (_) => setState(() {}), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: '搜索菜谱', hintText: '名称或简介')),
      const SizedBox(height: 10),
      SizedBox(height: 40, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: categories.length, separatorBuilder: (_, _) => const SizedBox(width: 8), itemBuilder: (_, i) { final item = categories[i]; return ChoiceChip(label: Text(item), selected: category == item, onSelected: (_) => setState(() => category = item), selectedColor: AppColors.soft); })),
      const SizedBox(height: 20),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('我的菜谱', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)), IconButton(onPressed: () => setState(() { search.clear(); category = '全部'; }), tooltip: '清除筛选', icon: const Icon(Icons.filter_alt_off_outlined))]),
      ref.watch(recipesProvider).when(
        loading: () => const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
        error: (error, _) => _message(Icons.error_outline, '菜谱加载失败', error.toString()),
        data: (all) { final keyword = search.text.trim().toLowerCase(); final items = all.where((r) => (category == '全部' || r.category == category) && (r.title.toLowerCase().contains(keyword) || r.description.toLowerCase().contains(keyword))).toList(); if (items.isEmpty) return _message(Icons.menu_book_outlined, all.isEmpty ? '还没有菜谱' : '没有找到匹配的菜谱', all.isEmpty ? '点击“记录一道新菜”开始你的厨房日志。' : '试试其他关键词或分类。'); return Column(children: items.map(_card).toList()); },
      ),
    ]),
  );

  Widget _message(IconData icon, String title, String detail) => Padding(padding: const EdgeInsets.symmetric(vertical: 42), child: Column(children: [Icon(icon, size: 44, color: AppColors.muted), const SizedBox(height: 12), Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text(detail, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted))]));

  Widget _card(Recipe recipe) => Card(margin: const EdgeInsets.only(bottom: 12), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: AppColors.border)), child: InkWell(borderRadius: BorderRadius.circular(15), onTap: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => RecipeDetailPage(recipeId: recipe.id))); ref.invalidate(recipesProvider); }, child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
    ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 76, height: 76, child: recipe.coverImagePath != null && File(recipe.coverImagePath!).existsSync() ? Image.file(File(recipe.coverImagePath!), fit: BoxFit.cover) : const ColoredBox(color: Color(0xFFD98253), child: Icon(Icons.restaurant, size: 34, color: Colors.white)))),
    const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(recipe.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text(recipe.category, style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700)), if (recipe.description.isNotEmpty) Text(recipe.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 12)), const SizedBox(height: 4), ref.watch(versionsProvider(recipe.id)).maybeWhen(data: (versions) { final ratings = versions.map((v) => v.rating).whereType<double>(); final best = ratings.isEmpty ? null : ratings.reduce((a, b) => a > b ? a : b); return Text('${versions.length} 个版本 · ${best == null ? '未评分' : '最佳 ${best.toStringAsFixed(1)} 分'} · ${DateFormat('MM-dd').format(recipe.updatedAt)}', style: const TextStyle(color: AppColors.muted, fontSize: 11)); }, orElse: () => Text(DateFormat('MM-dd HH:mm').format(recipe.updatedAt), style: const TextStyle(color: AppColors.muted, fontSize: 11)))])),
    IconButton(onPressed: () async { await (await ref.read(repositoryProvider.future)).toggleFavorite(recipe); ref.invalidate(recipesProvider); ref.invalidate(statsProvider); }, tooltip: recipe.isFavorite ? '取消收藏' : '收藏', icon: Icon(recipe.isFavorite ? Icons.favorite : Icons.favorite_border, color: AppColors.primary)),
  ]))));
}
