import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/recipe.dart';
import '../../../models/recipe_filter.dart';
import '../../../providers/recipe_providers.dart';
import '../../inventory/presentation/inventory_add_item_page.dart';
import '../../inventory/presentation/inventory_home_page.dart';
import '../../profile/presentation/profile_page.dart';
import '../../profile/presentation/recipe_categories_page.dart';
import 'new_recipe_page.dart';
import 'recipe_detail_page.dart';

class RecipesHomePage extends ConsumerStatefulWidget {
  const RecipesHomePage({super.key});
  @override
  ConsumerState<RecipesHomePage> createState() => _RecipesHomePageState();
}

class _RecipesHomePageState extends ConsumerState<RecipesHomePage> {
  final search = TextEditingController();
  int tab = 0;
  String? selectedCategory;
  bool favoritesOnly = false;
  RecipeSort sort = RecipeSort.updated;
  final favoriteBusy = <String>{};

  void _clearFilters() => setState(() {
    search.clear();
    selectedCategory = null;
    favoritesOnly = false;
  });

  Future<void> _refreshRecipes() async {
    ref.invalidate(recipesProvider);
    ref.invalidate(versionsProvider);
    ref.invalidate(statsProvider);
    await ref.read(recipesProvider.future);
  }

  Future<void> _openRecipe(String id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RecipeDetailPage(recipeId: id)),
    );
    if (!mounted) return;
    ref.invalidate(recipesProvider);
    ref.invalidate(versionsProvider(id));
    ref.invalidate(statsProvider);
  }

  Future<void> _favorite(Recipe recipe) async {
    if (favoriteBusy.contains(recipe.id)) return;
    setState(() => favoriteBusy.add(recipe.id));
    try {
      await (await ref.read(repositoryProvider.future)).toggleFavorite(recipe);
      if (!mounted) return;
      ref.invalidate(recipesProvider);
      ref.invalidate(recipeProvider(recipe.id));
      ref.invalidate(statsProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('收藏更新失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => favoriteBusy.remove(recipe.id));
    }
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _newRecipe() async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const NewRecipePage()),
    );
    if (id != null && mounted) {
      await _openRecipe(id);
    }
  }

  Future<void> _newInventoryItem() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const InventoryAddItemPage()),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: IndexedStack(
        index: tab,
        children: [_recipes(), const InventoryHomePage(), const ProfilePage()],
      ),
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            _TabButton(
              label: '菜谱',
              icon: Icons.menu_book_outlined,
              selectedIcon: Icons.menu_book,
              selected: tab == 0,
              onTap: () => setState(() => tab = 0),
            ),
            _TabButton(
              label: '万物',
              icon: Icons.category_outlined,
              selectedIcon: Icons.category,
              selected: tab == 1,
              onTap: () => setState(() => tab = 1),
            ),
            _TabButton(
              label: '我的',
              icon: Icons.person_outline,
              selectedIcon: Icons.person,
              selected: tab == 2,
              onTap: () => setState(() => tab = 2),
            ),
          ],
        ),
      ),
    ),
    floatingActionButton: tab == 0
        ? FloatingActionButton(
            onPressed: _newRecipe,
            tooltip: '新建菜谱',
            child: const Icon(Icons.add),
          )
        : tab == 1
        ? FloatingActionButton(
            onPressed: _newInventoryItem,
            tooltip: '记录物品',
            child: const Icon(Icons.add),
          )
        : null,
  );

  Widget _recipes() {
    final recipes = ref.watch(recipesProvider);
    final all = recipes.valueOrNull ?? const <Recipe>[];
    final categories = <String>{
      ...?ref.watch(recipeCategoriesProvider).valueOrNull,
      ...all.map((recipe) => recipe.category),
      '未分类',
    };
    final category = categories.contains(selectedCategory)
        ? selectedCategory
        : null;
    final filtered =
        search.text.trim().isNotEmpty || category != null || favoritesOnly;
    return RefreshIndicator(
      onRefresh: () async {
        try {
          await _refreshRecipes();
        } catch (_) {
          /* The list shows the retry state. */
        }
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 96),
        children: [
          Text(
            '我的厨房日志',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.primary,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            '食作簿',
            style: Theme.of(context).textTheme.headlineLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              labelText: '搜索菜谱',
              hintText: '名称、简介或分类',
              suffixIcon: search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清除搜索',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => search.clear()),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: Text('仅看收藏 · ${all.where((r) => r.isFavorite).length}'),
                avatar: const Icon(Icons.favorite_border, size: 17),
                selected: favoritesOnly,
                onSelected: (value) => setState(() => favoritesOnly = value),
              ),
              ActionChip(
                avatar: const Icon(Icons.tune, size: 17),
                label: const Text('管理分类'),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RecipeCategoriesPage(),
                    ),
                  );
                  if (mounted) setState(() => selectedCategory = null);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: Text('全部 ${all.length}'),
                  selected: category == null,
                  onSelected: (_) => setState(() => selectedCategory = null),
                ),
                for (final name in categories)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      label: Text(
                        '$name ${all.where((r) => r.category == name).length}',
                      ),
                      selected: category == name,
                      onSelected: (_) =>
                          setState(() => selectedCategory = name),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                filtered ? '筛选结果' : '我的菜谱',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              if (filtered)
                IconButton(
                  onPressed: _clearFilters,
                  tooltip: '清除筛选',
                  icon: const Icon(Icons.filter_alt_off_outlined),
                ),
              PopupMenuButton<RecipeSort>(
                tooltip: '菜谱排序',
                initialValue: sort,
                onSelected: (value) => setState(() => sort = value),
                itemBuilder: (_) => RecipeSort.values
                    .map(
                      (value) => CheckedPopupMenuItem(
                        value: value,
                        checked: sort == value,
                        child: Text(value.label),
                      ),
                    )
                    .toList(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        sort.label,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                      const Icon(
                        Icons.expand_more,
                        size: 18,
                        color: AppColors.muted,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          recipes.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Column(
              children: [
                _message(Icons.error_outline, '菜谱加载失败', '请稍后重试，已有记录不会丢失。'),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(recipesProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新加载'),
                ),
              ],
            ),
            data: (all) {
              final items = filterRecipes(
                all,
                keyword: search.text,
                category: category,
                favoritesOnly: favoritesOnly,
                sort: sort,
              );
              if (items.isEmpty) {
                return Column(
                  children: [
                    _message(
                      Icons.menu_book_outlined,
                      all.isEmpty ? '还没有菜谱' : '没有找到匹配的菜谱',
                      all.isEmpty ? '把喜欢的味道，记成自己的菜谱。' : '试试其他关键词或调整筛选条件。',
                    ),
                    if (all.isEmpty)
                      FilledButton.icon(
                        onPressed: _newRecipe,
                        icon: const Icon(Icons.add),
                        label: const Text('记录第一道菜'),
                      )
                    else
                      TextButton(
                        onPressed: _clearFilters,
                        child: const Text('清除筛选'),
                      ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '共 ${items.length} 道菜谱',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  ...items.map(_card),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _message(IconData icon, String title, String detail) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 42),
    child: Column(
      children: [
        Icon(icon, size: 44, color: AppColors.muted),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted),
        ),
      ],
    ),
  );

  Widget _card(Recipe recipe) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    elevation: 0,
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(15),
      side: const BorderSide(color: AppColors.border),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: () => _openRecipe(recipe.id),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 76,
                height: 76,
                child:
                    recipe.coverImagePath != null &&
                        File(recipe.coverImagePath!).existsSync()
                    ? Image.file(
                        File(recipe.coverImagePath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const ColoredBox(
                          color: AppColors.soft,
                          child: Icon(
                            Icons.restaurant,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    : const ColoredBox(
                        color: Color(0xFFD98253),
                        child: Icon(
                          Icons.restaurant,
                          size: 34,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipe.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    recipe.category,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                    ),
                  ),
                  if (recipe.description.isNotEmpty)
                    Text(
                      recipe.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  const SizedBox(height: 4),
                  ref
                      .watch(versionsProvider(recipe.id))
                      .maybeWhen(
                        data: (versions) {
                          final ratings = versions
                              .map((v) => v.rating)
                              .whereType<double>();
                          final best = ratings.isEmpty
                              ? null
                              : ratings.reduce((a, b) => a > b ? a : b);
                          return Text(
                            '${versions.length} 个版本 · ${best == null ? '未评分' : '最佳 ${best.toStringAsFixed(1)} 分'} · ${DateFormat('MM-dd').format(recipe.updatedAt)}',
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                            ),
                          );
                        },
                        orElse: () => Text(
                          DateFormat('MM-dd HH:mm').format(recipe.updatedAt),
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                ],
              ),
            ),
            IconButton(
              onPressed: favoriteBusy.contains(recipe.id)
                  ? null
                  : () => _favorite(recipe),
              tooltip: recipe.isFavorite ? '取消收藏' : '收藏',
              icon: Icon(
                recipe.isFavorite ? Icons.favorite : Icons.favorite_border,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final VoidCallback onTap;

  static const selectedColor = AppColors.primary;
  static const idleColor = AppColors.muted;

  @override
  Widget build(BuildContext context) {
    final color = selected ? selectedColor : idleColor;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(selected ? selectedIcon : icon, color: color, size: 24),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
