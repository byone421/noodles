import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/active_filter_bar.dart';
import '../../accounting/presentation/accounting_page.dart';
import '../../../models/account_entry.dart';
import '../../../models/inventory_settings.dart';
import '../../../models/recipe.dart';
import '../../../models/recipe_filter.dart';
import '../../../providers/accounting_providers.dart';
import '../../../providers/recipe_providers.dart';
import '../../fanfou/presentation/fanfou_page.dart';
import '../../inventory/presentation/inventory_add_item_page.dart';
import '../../inventory/presentation/inventory_home_page.dart';
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
  int tab = 0;
  int? inventoryCategoryId;
  Key inventoryKey = UniqueKey();
  AccountCategory? accountCategory;
  Key accountingKey = UniqueKey();
  String? selectedCategory;
  RecipeSort sort = RecipeSort.updated;

  void _clearFilters() => setState(() {
    search.clear();
    selectedCategory = null;
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

  Future<void> _editRecipe(Recipe recipe) async {
    final saved = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => NewRecipePage(recipe: recipe)),
    );
    if (saved != null && mounted) {
      ref.invalidate(recipesProvider);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('菜谱已更新')));
    }
  }

  Future<void> _copyRecipe(Recipe recipe) async {
    try {
      await (await ref.read(repositoryProvider.future)).copyRecipe(recipe.id);
      if (!mounted) return;
      ref.invalidate(recipesProvider);
      ref.invalidate(statsProvider);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('菜谱已复制')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('复制失败，请重试')));
      }
    }
  }

  Future<void> _deleteRecipe(Recipe recipe) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除这道菜谱？'),
        content: const Text('所有版本和相关记录都会永久删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await (await ref.read(repositoryProvider.future)).deleteRecipe(recipe.id);
      if (!mounted) return;
      ref.invalidate(recipesProvider);
      ref.invalidate(statsProvider);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('菜谱已删除')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('删除失败，请重试')));
      }
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
      _clearFilters();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('菜谱已创建')));
    }
  }

  Future<void> _newInventoryItem() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const InventoryAddItemPage()),
    );
  }

  Future<void> _newAccountEntry() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AccountEntryPage()),
    );
    if (saved == true && mounted) ref.invalidate(accountEntriesProvider);
  }

  void _showInventoryCategory(InventoryCategory category) => setState(() {
    inventoryCategoryId = category.id;
    inventoryKey = UniqueKey();
    tab = 2;
  });

  void _showRecipeCategory(String category) => setState(() {
    search.clear();
    selectedCategory = category;
    tab = 0;
  });

  void _showAccountCategory(AccountCategory category) => setState(() {
    accountCategory = category;
    accountingKey = UniqueKey();
    tab = 3;
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: IndexedStack(
        index: tab,
        children: [
          _recipes(),
          FanfouPage(onOpenRecipe: _openRecipe, onAddRecipe: _newRecipe),
          InventoryHomePage(
            key: inventoryKey,
            initialCategoryId: inventoryCategoryId,
          ),
          AccountingPage(key: accountingKey, initialCategory: accountCategory),
          ProfilePage(
            onInventoryCategorySelected: _showInventoryCategory,
            onRecipeCategorySelected: _showRecipeCategory,
            onAccountCategorySelected: _showAccountCategory,
          ),
        ],
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
              label: '饭否',
              icon: Icons.rice_bowl_outlined,
              selectedIcon: Icons.rice_bowl,
              selected: tab == 1,
              onTap: () => setState(() => tab = 1),
            ),
            _TabButton(
              label: '万物',
              icon: Icons.category_outlined,
              selectedIcon: Icons.category,
              selected: tab == 2,
              onTap: () => setState(() => tab = 2),
            ),
            _TabButton(
              label: '记账',
              icon: Icons.receipt_long_outlined,
              selectedIcon: Icons.receipt_long,
              selected: tab == 3,
              onTap: () => setState(() => tab = 3),
            ),
            _TabButton(
              label: '我的',
              icon: Icons.person_outline,
              selectedIcon: Icons.person,
              selected: tab == 4,
              onTap: () => setState(() => tab = 4),
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
        : tab == 2
        ? FloatingActionButton(
            onPressed: _newInventoryItem,
            tooltip: '记录物品',
            child: const Icon(Icons.add),
          )
        : tab == 3
        ? FloatingActionButton(
            onPressed: _newAccountEntry,
            tooltip: '记一笔',
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
    final filtered = search.text.trim().isNotEmpty || category != null;
    final items = filterRecipes(
      all,
      keyword: search.text,
      category: category,
      sort: sort,
    );
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
            '掌勺人',
            style: Theme.of(context).textTheme.headlineSmall
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
          const SizedBox(height: 16),
          ActiveFilterBar(
            filters: [
              if (category != null)
                (
                  label: '分类：$category',
                  clearTooltip: '清除分类筛选',
                  onClear: () => setState(() => selectedCategory = null),
                ),
              if (search.text.trim().isNotEmpty)
                (
                  label: '搜索：${search.text.trim()}',
                  clearTooltip: '清除搜索',
                  onClear: () => setState(() => search.clear()),
                ),
            ],
            onClear: _clearFilters,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${filtered ? '筛选结果' : '我的菜谱'}（${items.length}）',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
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
          const SizedBox(height: 8),
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
                      ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [...items.map(_card)],
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

  Widget _recipeInitial(String title) => ColoredBox(
    color: AppColors.soft,
    child: Center(
      child: Text(
        title.isEmpty ? '?' : title.characters.first,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 28,
          fontWeight: FontWeight.w800,
        ),
      ),
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
                child: recipe.coverImagePath != null
                    ? Image.file(
                        File(recipe.coverImagePath!),
                        cacheWidth:
                            (76 * MediaQuery.devicePixelRatioOf(context))
                                .round(),
                        cacheHeight:
                            (76 * MediaQuery.devicePixelRatioOf(context))
                                .round(),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _recipeInitial(recipe.title),
                      )
                    : _recipeInitial(recipe.title),
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
            PopupMenuButton<String>(
              tooltip: '菜谱操作',
              padding: EdgeInsets.zero,
              onSelected: (value) {
                if (value == 'edit') {
                  _editRecipe(recipe);
                } else if (value == 'copy') {
                  _copyRecipe(recipe);
                } else {
                  _deleteRecipe(recipe);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('编辑菜谱信息')),
                PopupMenuItem(value: 'copy', child: Text('复制菜谱')),
                PopupMenuItem(value: 'delete', child: Text('删除菜谱')),
              ],
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
