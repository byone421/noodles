import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/meal_draw.dart';
import '../../../models/recipe.dart';
import '../../../providers/recipe_providers.dart';

class FanfouPage extends ConsumerStatefulWidget {
  const FanfouPage({
    super.key,
    required this.onOpenRecipe,
    required this.onAddRecipe,
  });

  final ValueChanged<String> onOpenRecipe;
  final VoidCallback onAddRecipe;

  @override
  ConsumerState<FanfouPage> createState() => _FanfouPageState();
}

class _FanfouPageState extends ConsumerState<FanfouPage> {
  final menuKey = GlobalKey();
  final categories = <String>{};
  final lockedIds = <String>{};
  List<String> resultIds = [];
  int count = 2;
  bool hasDrawn = false;

  void _resetResults() {
    resultIds = [];
    lockedIds.clear();
    hasDrawn = false;
  }

  @override
  Widget build(BuildContext context) {
    final recipes = ref.watch(recipesProvider);
    return Column(
      children: [
        Expanded(
          child: recipes.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => _message(
              '菜谱暂时没有端上来',
              '加载失败了，请重试一下。',
              action: OutlinedButton.icon(
                onPressed: () => ref.invalidate(recipesProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('重新加载'),
              ),
            ),
            data: _content,
          ),
        ),
        if (recipes.hasValue && !recipes.isLoading && !recipes.hasError)
          _drawButton(recipes.requireValue),
      ],
    );
  }

  List<Recipe> _candidates(List<Recipe> all) => all
      .where(
        (recipe) => categories.isEmpty || categories.contains(recipe.category),
      )
      .toList();

  Future<void> _chooseCategories(List<String> availableCategories) async {
    final selected = await Navigator.push<Set<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => _FanfouCategoryPicker(
          categories: availableCategories.toList(),
          selected: categories,
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      categories
        ..clear()
        ..addAll(selected);
      _resetResults();
    });
  }

  Widget _content(List<Recipe> all) {
    final availableCategories = <String>{
      ...?ref.watch(recipeCategoriesProvider).valueOrNull,
      ...all.map((recipe) => recipe.category),
      ...categories,
    };
    final candidates = _candidates(all);
    final byId = {for (final recipe in candidates) recipe.id: recipe};
    final results = resultIds
        .where(byId.containsKey)
        .map((id) => byId[id]!)
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      children: [
        const Text(
          '饭否',
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '今天吃点什么？',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        const Text('从拿手菜里，找一点新鲜感。', style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 22),
        if (all.isEmpty)
          _message(
            '先存下喜欢的味道',
            '录入几道菜谱，下次纠结吃什么，就交给饭否。',
            action: FilledButton.icon(
              onPressed: widget.onAddRecipe,
              icon: const Icon(Icons.add),
              label: const Text('去录入菜谱'),
            ),
          )
        else ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _heading('想吃哪一类', '可多选'),
                const SizedBox(height: 10),
                OutlinedButton(
                  key: const ValueKey('choose-fanfou-categories'),
                  onPressed: () =>
                      _chooseCategories(availableCategories.toList()),
                  child: Row(
                    children: [
                      const Icon(Icons.category_outlined),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          categories.isEmpty
                              ? '都可以'
                              : '已选 ${categories.length} 个分类',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Text('选择'),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, color: AppColors.border),
                ),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '这顿做几道',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '少一道',
                      onPressed: count > 1
                          ? () => setState(() {
                              count--;
                              _resetResults();
                            })
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text(
                      '$count 道',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    IconButton(
                      tooltip: '多一道',
                      onPressed: count < (all.length < 4 ? 4 : all.length)
                          ? () => setState(() {
                              count++;
                              _resetResults();
                            })
                          : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                Text(
                  candidates.isEmpty
                      ? '这个分类还没有菜谱，换一类试试。'
                      : candidates.length < count
                      ? '只有 ${candidates.length} 道可选，会全部端上桌。'
                      : '从 ${candidates.length} 道菜谱中随机选出，不重复。',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            key: menuKey,
            child: _heading(
              hasDrawn ? '这顿就吃这些' : '今日菜单',
              hasDrawn ? '${results.length} 道菜' : '等你开席',
            ),
          ),
          const SizedBox(height: 10),
          if (!hasDrawn)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 20),
              decoration: BoxDecoration(
                color: AppColors.soft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.rice_bowl_outlined,
                    size: 36,
                    color: AppColors.primary,
                  ),
                  SizedBox(height: 10),
                  Text(
                    '把选择交给一点随机',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '选好分类和数量，看看今天的菜单。',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
            )
          else if (results.isEmpty)
            const Text(
              '菜单里的菜谱已移除或更换分类，再抽一次吧。',
              style: TextStyle(color: AppColors.muted),
            )
          else ...[
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                '点菜谱看做法，锁定想留下的菜。',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
            for (final recipe in results) _recipeCard(recipe),
            if (results.length == candidates.length)
              const Text(
                '已经是全部候选菜谱啦，换个分类可以试试新搭配。',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
          ],
        ],
      ],
    );
  }

  Widget _heading(String title, String detail) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      Text(
        detail,
        style: const TextStyle(color: AppColors.muted, fontSize: 12),
      ),
    ],
  );

  Widget _drawButton(List<Recipe> all) {
    if (all.isEmpty) return const SizedBox.shrink();
    final candidates = _candidates(all);
    final currentIds = resultIds
        .where((id) => candidates.any((r) => r.id == id))
        .toList();
    final allLocked =
        currentIds.isNotEmpty &&
        currentIds.every(lockedIds.contains) &&
        currentIds.length >=
            (count < candidates.length ? count : candidates.length);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
      child: Column(
        children: [
          if (allLocked)
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                '都锁定好啦，解锁一道再换换口味。',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
          Center(
            child: FilledButton.tonalIcon(
              key: const ValueKey('draw-meal'),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: candidates.isEmpty || allLocked
                  ? null
                  : () => setState(() {
                      final drawn = drawMeal(
                        candidates,
                        count: count,
                        previousIds: currentIds,
                        lockedIds: lockedIds,
                      );
                      resultIds = drawn.map((recipe) => recipe.id).toList();
                      lockedIds.retainAll(resultIds);
                      hasDrawn = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        final menuContext = menuKey.currentContext;
                        if (mounted && menuContext != null) {
                          Scrollable.ensureVisible(
                            menuContext,
                            duration: const Duration(milliseconds: 250),
                          );
                        }
                      });
                    }),
              icon: Icon(hasDrawn ? Icons.refresh : Icons.shuffle),
              label: Text(
                hasDrawn
                    ? lockedIds.isEmpty
                          ? '不合口味？换一桌'
                          : '换一桌 · 保留已锁定'
                    : '帮我选 $count 道菜',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recipeCard(Recipe recipe) {
    final locked = lockedIds.contains(recipe.id);
    final initial = ColoredBox(
      color: AppColors.soft,
      child: Center(
        child: Text(
          recipe.title.isEmpty ? '菜' : recipe.title.characters.first,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: AppColors.primary,
          ),
        ),
      ),
    );
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: locked ? AppColors.primary : AppColors.border),
      ),
      child: InkWell(
        onTap: () => widget.onOpenRecipe(recipe.id),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: recipe.coverImagePath == null
                      ? initial
                      : Image.file(
                          File(recipe.coverImagePath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => initial,
                        ),
                ),
              ),
              const SizedBox(width: 12),
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
                    const SizedBox(height: 4),
                    Text(
                      recipe.category,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      locked ? '已锁定 · 换一桌时保留' : '查看做法 →',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: locked ? '解锁${recipe.title}' : '锁定${recipe.title}',
                isSelected: locked,
                color: AppColors.primary,
                onPressed: () => setState(() {
                  locked
                      ? lockedIds.remove(recipe.id)
                      : lockedIds.add(recipe.id);
                }),
                icon: Icon(locked ? Icons.lock : Icons.lock_open_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _message(String title, String detail, {Widget? action}) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.rice_bowl_outlined,
            size: 48,
            color: AppColors.primary,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
          if (action != null) ...[const SizedBox(height: 20), action],
        ],
      ),
    ),
  );
}

class _FanfouCategoryPicker extends StatefulWidget {
  const _FanfouCategoryPicker({
    required this.categories,
    required this.selected,
  });

  final List<String> categories;
  final Set<String> selected;

  @override
  State<_FanfouCategoryPicker> createState() => _FanfouCategoryPickerState();
}

class _FanfouCategoryPickerState extends State<_FanfouCategoryPicker> {
  final search = TextEditingController();
  late final selected = {...widget.selected};

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = search.text.trim().toLowerCase();
    final filtered = widget.categories
        .where((name) => name.toLowerCase().contains(query))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择分类'),
        actions: [
          TextButton(
            onPressed: () => setState(selected.clear),
            child: const Text('清空'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索分类',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '已选 ${selected.length} 个分类',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      query.isEmpty ? '还没有分类' : '没有找到匹配的分类',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final name = filtered[index];
                      return CheckboxListTile(
                        value: selected.contains(name),
                        title: Text(name),
                        controlAffinity: ListTileControlAffinity.trailing,
                        onChanged: (value) => setState(() {
                          value == true
                              ? selected.add(name)
                              : selected.remove(name);
                        }),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, selected),
                  child: const Text('完成选择'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
