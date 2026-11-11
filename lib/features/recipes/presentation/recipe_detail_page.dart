import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/recipe.dart';
import '../../../providers/recipe_providers.dart';
import '../../comparison/presentation/version_compare_page.dart';
import '../../versions/presentation/edit_version_page.dart';
import 'new_recipe_page.dart';

class RecipeDetailPage extends ConsumerStatefulWidget {
  const RecipeDetailPage({super.key, required this.recipeId});
  final String recipeId;
  @override
  ConsumerState<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

class _RecipeDetailPageState extends ConsumerState<RecipeDetailPage> {
  String? selectedId;
  bool busy = false;
  void refresh() {
    ref.invalidate(recipeProvider(widget.recipeId));
    ref.invalidate(versionsProvider(widget.recipeId));
    ref.invalidate(statsProvider);
    ref.invalidate(recipesProvider);
    if (selectedId != null) ref.invalidate(bundleProvider(selectedId!));
  }

  Future<void> edit(VersionBundle? bundle, {bool copy = false}) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditVersionPage(
          recipeId: widget.recipeId,
          bundle: bundle,
          copyAsNew: copy,
        ),
      ),
    );
    if (changed == true && mounted) {
      if (copy || bundle == null) selectedId = null;
      refresh();
    }
  }

  Future<void> _editInfo(Recipe recipe) async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => NewRecipePage(recipe: recipe)),
    );
    if (id != null && mounted) refresh();
  }

  Future<void> _compare(List<RecipeVersion> versions) async {
    try {
      final repo = await ref.read(repositoryProvider.future);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              VersionComparePage(repository: repo, versions: versions),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('对比加载失败，请重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final recipeAsync = ref.watch(recipeProvider(widget.recipeId));
    final versionsAsync = ref.watch(versionsProvider(widget.recipeId));
    return PopScope(
      canPop: !busy,
      child: AbsorbPointer(
        absorbing: busy,
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            systemOverlayStyle: SystemUiOverlayStyle.light,
            title: const Text('菜谱详情'),
            actions: [
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                ),
              if (recipeAsync.valueOrNull != null)
                IconButton(
                  tooltip: '编辑菜谱信息',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _editInfo(recipeAsync.valueOrNull!),
                ),
              IconButton(
                onPressed: () => _deleteRecipe(),
                tooltip: '删除菜谱',
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          body: recipeAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _loadError('菜谱加载失败', refresh),
            data: (recipe) {
              if (recipe == null) return const Center(child: Text('菜谱不存在'));
              return versionsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => _loadError('版本加载失败', refresh),
                data: (versions) {
                  if (versions.isNotEmpty &&
                      !versions.any((v) => v.id == selectedId)) {
                    selectedId = versions.first.id;
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  recipe.category,
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  recipe.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                if (recipe.description.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      recipe.description,
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => _perform(
                              () async =>
                                  (await ref.read(repositoryProvider.future))
                                      .toggleFavorite(recipe),
                            ),
                            tooltip: recipe.isFavorite ? '取消收藏' : '收藏',
                            icon: Icon(
                              recipe.isFavorite
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${versions.length} 个版本',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => edit(null),
                            tooltip: '新建版本',
                            icon: const Icon(Icons.add),
                          ),
                          if (versions.length > 1)
                            IconButton(
                              onPressed: () => _compare(versions),
                              tooltip: '版本对比',
                              icon: const Icon(Icons.compare_arrows),
                            ),
                        ],
                      ),
                      if (versions.isEmpty)
                        const Text('暂无版本')
                      else ...[
                        SizedBox(
                          height: 82,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: versions.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (_, i) {
                              final v = versions[i];
                              return ChoiceChip(
                                label: SizedBox(
                                  width: 100,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('版本 ${v.versionNumber}'),
                                      Text(
                                        v.isBest
                                            ? '最佳版本'
                                            : (v.rating == null
                                                  ? '未评分'
                                                  : '${v.rating} 分'),
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                                selected: v.id == selectedId,
                                onSelected: (_) =>
                                    setState(() => selectedId = v.id),
                                selectedColor: AppColors.soft,
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (selectedId != null)
                          ref
                              .watch(bundleProvider(selectedId!))
                              .when(
                                loading: () => const Center(
                                  child: CircularProgressIndicator(),
                                ),
                                error: (e, _) => _loadError(
                                  '详情加载失败',
                                  () => ref.invalidate(
                                    bundleProvider(selectedId!),
                                  ),
                                ),
                                data: (bundle) => bundle == null
                                    ? const Text('版本不存在')
                                    : _bundle(recipe, versions, bundle),
                              ),
                      ],
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _bundle(
    Recipe recipe,
    List<RecipeVersion> versions,
    VersionBundle b,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  b.version.title,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (b.version.note.isNotEmpty)
                  Text(
                    b.version.note,
                    style: const TextStyle(color: AppColors.muted),
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => _action(v, b, versions.length),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('编辑当前版本')),
              const PopupMenuItem(value: 'copy', child: Text('复制为新版本')),
              if (!b.version.isBest)
                const PopupMenuItem(value: 'best', child: Text('标记为最佳版本')),
              if (versions.length > 1)
                const PopupMenuItem(value: 'delete', child: Text('删除版本')),
            ],
          ),
        ],
      ),
      if (b.version.rating != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              const Icon(Icons.star, color: AppColors.accent),
              Text(
                ' ${b.version.rating!.toStringAsFixed(1)}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      _section(
        '材料',
        b.ingredients.isEmpty
            ? [const Text('暂无材料记录', style: TextStyle(color: AppColors.muted))]
            : b.ingredients
                  .map(
                    (i) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(i.name),
                      trailing: Text(
                        '${i.amount}${i.unit}',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ),
                  )
                  .toList(),
      ),
      _section(
        '制作步骤',
        b.steps.isEmpty
            ? [const Text('暂无步骤记录', style: TextStyle(color: AppColors.muted))]
            : b.steps
                  .asMap()
                  .entries
                  .map(
                    (e) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 15,
                        backgroundColor: AppColors.soft,
                        child: Text(
                          '${e.key + 1}',
                          style: const TextStyle(
                            color: AppColors.deep,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      title: Text(e.value.content),
                    ),
                  )
                  .toList(),
      ),
      _section('成品照片', [
        if (b.finishedRecord?.imagePath != null &&
            File(b.finishedRecord!.imagePath!).existsSync())
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(b.finishedRecord!.imagePath!),
              fit: BoxFit.contain,
            ),
          )
        else
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.photo_outlined),
            title: Text('暂无成品照片'),
            subtitle: Text('编辑当前版本即可添加本地照片'),
          ),
      ]),
      _section('成品复盘', [
        Text(
          b.finishedRecord?.note.isNotEmpty == true
              ? b.finishedRecord!.note
              : '暂无复盘记录',
          style: const TextStyle(height: 1.5),
        ),
      ]),
      _section('下次改进方向', [
        Text(
          b.finishedRecord?.nextImprovement.isNotEmpty == true
              ? b.finishedRecord!.nextImprovement
              : '暂无改进记录',
          style: const TextStyle(height: 1.5),
        ),
      ]),
      FilledButton.icon(
        onPressed: () => edit(b),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('编辑这个版本'),
      ),
    ],
  );

  Widget _section(String title, List<Widget> children) => Card(
    elevation: 0,
    margin: const EdgeInsets.only(top: 12),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );
  Future<void> _action(String action, VersionBundle b, int count) async {
    if (action == 'edit') return edit(b);
    if (action == 'copy') return edit(b, copy: true);
    if (action == 'best') {
      await _perform(() async {
        final repo = await ref.read(repositoryProvider.future);
        final versions = await repo.versions(widget.recipeId);
        await repo.markBest(b.version.id, widget.recipeId);
        if (!mounted) return;
        for (final version in versions) {
          ref.invalidate(bundleProvider(version.id));
        }
      });
      return;
    }
    if (action == 'delete' &&
        count > 1 &&
        await _confirm('删除这个版本？', '材料、步骤和成品记录也会一起删除。')) {
      if (!mounted) return;
      await _perform(() async {
        await (await ref.read(repositoryProvider.future))
            .deleteVersion(b.version.id);
        if (mounted) selectedId = null;
      });
    }
  }

  Future<void> _deleteRecipe() async {
    if (!await _confirm('删除这道菜谱？', '所有版本和相关记录都会永久删除。')) return;
    if (!mounted) return;
    await _perform(
      () async =>
          (await ref.read(repositoryProvider.future))
              .deleteRecipe(widget.recipeId),
      close: true,
    );
  }

  Future<void> _perform(
    Future<void> Function() operation, {
    bool close = false,
  }) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await operation();
      if (!mounted) return;
      refresh();
      if (close) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('操作失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _loadError(String message, VoidCallback retry) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
            label: const Text('重新加载'),
          ),
        ],
      ),
    ),
  );

  Future<bool> _confirm(String title, String content) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(content),
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
      ) ??
      false;
}
