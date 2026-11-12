import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
    final versions = versionsAsync.valueOrNull;
    if (versions != null) {
      if (versions.isEmpty) {
        selectedId = null;
      } else if (!versions.any((v) => v.id == selectedId)) {
        selectedId = versions.first.id;
      }
    }
    final bundleAsync = selectedId == null
        ? null
        : ref.watch(bundleProvider(selectedId!));
    final bundle = bundleAsync?.valueOrNull;
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
            centerTitle: true,
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
                PopupMenuButton<String>(
                  tooltip: '菜谱管理',
                  onSelected: (action) {
                    if (action == 'edit') {
                      _editInfo(recipeAsync.valueOrNull!);
                    } else {
                      _deleteRecipe();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('编辑菜谱信息')),
                    PopupMenuItem(value: 'delete', child: Text('删除菜谱')),
                  ],
                ),
            ],
          ),
          bottomNavigationBar:
              recipeAsync.valueOrNull != null &&
                  !versionsAsync.isLoading &&
                  !versionsAsync.hasError &&
                  (bundle != null || versions?.isEmpty == true)
              ? Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Row(
                        children: [
                          if (bundle != null) ...[
                            OutlinedButton(
                              onPressed: () => edit(bundle, copy: true),
                              child: const Text('复制版本'),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => edit(bundle),
                              icon: Icon(
                                bundle == null
                                    ? Icons.add_rounded
                                    : Icons.edit_outlined,
                                size: 19,
                              ),
                              label: Text(
                                bundle == null ? '创建第一个版本' : '编辑当前版本',
                              ),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : null,
          body: recipeAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => _loadError('菜谱加载失败', refresh),
            data: (recipe) {
              if (recipe == null) return const Center(child: Text('菜谱不存在'));
              return versionsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => _loadError('版本加载失败', refresh),
                data: (versions) => ListView(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                  children: [
                    _overview(recipe, versions.length),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '烹饪版本',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (versions.length > 1)
                          TextButton(
                            onPressed: () => _compare(versions),
                            child: const Text('版本对比'),
                          ),
                        TextButton.icon(
                          onPressed: () => edit(null),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('新建版本'),
                        ),
                      ],
                    ),
                    if (versions.isEmpty)
                      _section('还没有烹饪版本', [
                        const Text(
                          '创建第一个版本，记下用料和做法。',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ])
                    else ...[
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            for (final version in versions)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  showCheckmark: false,
                                  labelPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 7,
                                  ),
                                  label: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '版本 ${version.versionNumber}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${version.isBest ? '最佳 · ' : ''}${version.rating == null ? '未评分' : '${version.rating!.toStringAsFixed(1)} 分'}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                  selected: version.id == selectedId,
                                  onSelected: (_) =>
                                      setState(() => selectedId = version.id),
                                  backgroundColor: Colors.white,
                                  selectedColor: AppColors.soft,
                                  side: BorderSide(
                                    color: version.id == selectedId
                                        ? AppColors.primary
                                        : AppColors.border,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (bundleAsync != null)
                        bundleAsync.when(
                          loading: () => const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                          error: (_, _) => _loadError(
                            '详情加载失败',
                            () => ref.invalidate(bundleProvider(selectedId!)),
                          ),
                          data: (b) => b == null
                              ? const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text('版本不存在'),
                                )
                              : _bundle(versions, b),
                        ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _overview(Recipe recipe, int count) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.soft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    recipe.category,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
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
                recipe.isFavorite ? Icons.favorite : Icons.favorite_border,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          recipe.title,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1.25,
          ),
        ),
        if (recipe.description.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            recipe.description,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 14,
              height: 1.6,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          '$count 个版本 · 更新于 ${DateFormat('yyyy.MM.dd').format(recipe.updatedAt)}',
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ],
    ),
  );

  Widget _bundle(List<RecipeVersion> versions, VersionBundle b) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _section('当前版本', [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                b.version.title.isEmpty
                    ? '版本 ${b.version.versionNumber}'
                    : b.version.title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                ),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: '版本管理',
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
        if (b.version.note.isNotEmpty)
          Text(
            b.version.note,
            style: const TextStyle(color: AppColors.muted, height: 1.6),
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            Text(
              b.version.rating == null
                  ? '尚未评分'
                  : '评分 ${b.version.rating!.toStringAsFixed(1)} 分',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (b.version.isBest)
              const Text(
                '最佳版本',
                style: TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ]),
      _section('准备食材', [
        if (b.ingredients.isEmpty)
          _empty('还没有用料记录，编辑当前版本即可补充。')
        else
          for (var index = 0; index < b.ingredients.length; index++) ...[
            if (index > 0) const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      b.ingredients[index].name,
                      style: const TextStyle(fontSize: 15, height: 1.5),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Flexible(
                    child: Text(
                      '${b.ingredients[index].amount}${b.ingredients[index].unit}'
                              .trim()
                              .isEmpty
                          ? '用量未填写'
                          : '${b.ingredients[index].amount}${b.ingredients[index].unit}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: AppColors.muted,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
      ], trailing: '${b.ingredients.length} 种'),
      _section('制作步骤', [
        if (b.steps.isEmpty)
          _empty('还没有步骤记录，记下你的制作顺序吧。')
        else
          for (var index = 0; index < b.steps.length; index++)
            Padding(
              padding: EdgeInsets.only(top: index == 0 ? 4 : 20, bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.soft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      b.steps[index].content,
                      style: const TextStyle(fontSize: 15, height: 1.8),
                    ),
                  ),
                ],
              ),
            ),
      ], trailing: '${b.steps.length} 步'),
      _section('成品照片', [
        if (b.finishedRecord?.imagePaths.isNotEmpty == true)
          for (final path in b.finishedRecord!.imagePaths)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(path),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => _photoPlaceholder(b, failed: true),
                ),
              ),
            )
        else
          _photoPlaceholder(b),
      ]),
      _section('烹饪复盘', [
        _note('这次做得怎么样', b.finishedRecord?.note, '还没有复盘，记下这次的口感与心得。'),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Divider(height: 1, color: AppColors.border),
        ),
        _note(
          '下次改进方向',
          b.finishedRecord?.nextImprovement,
          '下次想尝试什么？在编辑版本时记下来。',
        ),
      ]),
    ],
  );

  Widget _empty(String text) => Text(
    text,
    style: const TextStyle(color: AppColors.muted, fontSize: 14, height: 1.6),
  );

  Widget _note(String title, String? text, String placeholder) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Text(
        text?.isNotEmpty == true ? text! : placeholder,
        style: TextStyle(
          color: text?.isNotEmpty == true ? AppColors.text : AppColors.muted,
          height: 1.7,
        ),
      ),
    ],
  );

  Widget _photoPlaceholder(VersionBundle bundle, {bool failed = false}) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.soft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.add_photo_alternate_outlined,
              color: AppColors.primary,
              size: 30,
            ),
            const SizedBox(height: 8),
            _empty(failed ? '照片暂时无法显示，可以重新添加。' : '拍下成品，留下这次的好味道。'),
            TextButton(
              onPressed: () => edit(bundle),
              child: const Text('添加成品照片'),
            ),
          ],
        ),
      );

  Widget _section(String title, List<Widget> children, {String? trailing}) =>
      Card(
        elevation: 0,
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.only(top: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (trailing != null)
                    Text(
                      trailing,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
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
