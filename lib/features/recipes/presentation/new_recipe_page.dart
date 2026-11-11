import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/recipe.dart';
import '../../../providers/recipe_providers.dart';
import '../../profile/presentation/recipe_categories_page.dart';

class NewRecipePage extends ConsumerStatefulWidget {
  const NewRecipePage({super.key, this.recipe});
  final Recipe? recipe;

  @override
  ConsumerState<NewRecipePage> createState() => _NewRecipePageState();
}

class _NewRecipePageState extends ConsumerState<NewRecipePage> {
  final formKey = GlobalKey<FormState>();
  late final title = TextEditingController(text: widget.recipe?.title);
  late final description = TextEditingController(
    text: widget.recipe?.description,
  );
  final ingredients = TextEditingController();
  final steps = TextEditingController();
  late String category = widget.recipe?.category ?? '未分类';
  bool saving = false;
  bool get editing => widget.recipe != null;

  Future<void> _manageCategories() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RecipeCategoriesPage()),
    );
    if (!mounted) return;
    try {
      final repo = await ref.read(repositoryProvider.future);
      final categories = await repo.listRecipeCategories();
      final current = editing ? await repo.getRecipe(widget.recipe!.id) : null;
      if (!mounted) return;
      setState(() {
        if (category != '未分类' && !categories.contains(category)) {
          category = current?.category ?? '未分类';
        }
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('分类同步失败，请重试')));
      }
    }
  }

  @override
  void dispose() {
    for (final controller in [title, description, ingredients, steps]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    final invalid = formKey.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      await Scrollable.ensureVisible(
        invalid.first.context,
        duration: const Duration(milliseconds: 250),
        alignment: 0.2,
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => saving = true);
    try {
      final repo = await ref.read(repositoryProvider.future);
      final String id;
      if (editing) {
        id = widget.recipe!.id;
        await repo.updateRecipe(
          id: id,
          title: title.text.trim(),
          category: category,
          description: description.text.trim(),
        );
      } else {
        id = await repo.createRecipe(
          title: title.text.trim(),
          category: category,
          description: description.text.trim(),
          ingredientsText: ingredients.text,
          stepsText: steps.text,
        );
      }
      if (!mounted) return;
      ref.invalidate(recipesProvider);
      ref.invalidate(recipeProvider(id));
      ref.invalidate(versionsProvider(id));
      ref.invalidate(statsProvider);
      Navigator.pop(context, id);
    } catch (_) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('保存失败，填写内容已保留，请重试')));
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Scaffold(
      appBar: AppBar(
        title: Text(editing ? '编辑菜谱信息' : '新增菜谱'),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: FilledButton.icon(
              onPressed: saving ? null : save,
              icon: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded, size: 20),
              label: Text(
                saving
                    ? '保存中…'
                    : editing
                    ? '保存修改'
                    : '创建菜谱',
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ),
      ),
      body: AbsorbPointer(
        absorbing: saving,
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 16),
                  child: Text(
                    editing ? '修改名称、分类和简介，保留所有烹饪版本。' : '先记下一道菜，再慢慢打磨成自己的拿手菜。',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                  ),
                ),
                _section('基本信息', '只有名称为必填项', [
                  TextFormField(
                    controller: title,
                    textInputAction: TextInputAction.next,
                    decoration: _decoration('菜谱名称 *', '例如：番茄牛腩'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? '请输入菜谱名称' : null,
                  ),
                  ref
                      .watch(recipeCategoriesProvider)
                      .when(
                        loading: () => const LinearProgressIndicator(),
                        error: (_, _) => TextButton.icon(
                          onPressed: () =>
                              ref.invalidate(recipeCategoriesProvider),
                          icon: const Icon(Icons.refresh),
                          label: const Text('分类加载失败，点击重试'),
                        ),
                        data: (categories) {
                          final selected = categories.contains(category)
                              ? category
                              : '未分类';
                          return DropdownButtonFormField<String>(
                            key: ValueKey(selected),
                            initialValue: selected,
                            isExpanded: true,
                            decoration: _decoration('菜谱分类', null),
                            items: ['未分类', ...categories]
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(
                                      value,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setState(() => category = value!),
                          );
                        },
                      ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _manageCategories,
                      icon: const Icon(Icons.tune_rounded, size: 16),
                      label: const Text('管理分类'),
                    ),
                  ),
                  TextFormField(
                    controller: description,
                    minLines: 2,
                    maxLines: 4,
                    decoration: _decoration('一句话简介', '记下风味、口感，或这道菜的特别之处'),
                  ),
                ]),
                if (!editing) ...[
                  const SizedBox(height: 16),
                  _section('准备食材', '选填 · 每行一种食材，名称和用量用空格分开', [
                    TextFormField(
                      controller: ingredients,
                      minLines: 4,
                      maxLines: 10,
                      decoration: _decoration(
                        '食材与用量',
                        '牛腩 500 克\n番茄 2 个\n盐 适量',
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  _section('制作步骤', '选填 · 每行一个步骤，按制作顺序填写', [
                    TextFormField(
                      controller: steps,
                      minLines: 5,
                      maxLines: 14,
                      decoration: _decoration(
                        '做法',
                        '牛腩切块，焯水后洗净\n炒香番茄，加入牛腩翻炒\n加水炖煮至软烂，调味收汁',
                      ),
                    ),
                  ]),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 16, 4, 0),
                    child: Text(
                      '创建后可继续编辑第一个版本，添加成品照片、评分和复盘，也可以复制版本尝试新做法。',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _section(String heading, String detail, List<Widget> fields) => Card(
    elevation: 0,
    color: Colors.white,
    surfaceTintColor: Colors.transparent,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: AppColors.border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            heading,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          for (final field in fields) ...[const SizedBox(height: 14), field],
        ],
      ),
    ),
  );

  InputDecoration _decoration(String label, String? hint) => InputDecoration(
    labelText: label,
    hintText: hint,
    alignLabelWithHint: true,
    floatingLabelBehavior: FloatingLabelBehavior.always,
    labelStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
    hintStyle: const TextStyle(
      color: AppColors.muted,
      fontSize: 14,
      height: 1.6,
    ),
    filled: true,
    fillColor: const Color(0xFFF5F7F4),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );
}
