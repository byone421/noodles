import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/recipe.dart';
import '../../../providers/recipe_providers.dart';
import '../../profile/presentation/recipe_categories_page.dart';

class NewRecipePage extends ConsumerStatefulWidget {
  const NewRecipePage({
    super.key,
    this.recipe,
    this.recipeId,
    this.bundle,
    this.copyAsNew = false,
  }) : assert(recipe == null || recipeId == null);
  final Recipe? recipe;
  final String? recipeId;
  final VersionBundle? bundle;
  final bool copyAsNew;

  @override
  ConsumerState<NewRecipePage> createState() => _NewRecipePageState();
}

class _NewRecipePageState extends ConsumerState<NewRecipePage> {
  final formKey = GlobalKey<FormState>();
  late final title = TextEditingController(
    text: versionMode
        ? widget.copyAsNew
              ? '${widget.bundle?.version.title ?? '新版本'} 副本'
              : widget.bundle?.version.title ?? '新版本'
        : widget.recipe?.title,
  );
  late final description = TextEditingController(
    text: versionMode
        ? widget.bundle?.version.note
        : widget.recipe?.description,
  );
  late final ingredients = TextEditingController(
    text: widget.bundle?.ingredients.map(formatRecipeIngredient).join('\n'),
  );
  late final steps = TextEditingController(
    text: widget.bundle?.steps.map((step) => step.content).join('\n'),
  );
  late final rating = TextEditingController(
    text: widget.bundle?.version.rating?.toString() ?? '',
  );
  late final feedback = TextEditingController(
    text: widget.bundle?.finishedRecord?.note,
  );
  late final improvement = TextEditingController(
    text: widget.bundle?.finishedRecord?.nextImprovement,
  );
  late final imagePaths = [...?widget.bundle?.finishedRecord?.imagePaths];
  final pickedPaths = <String>{};
  late String category = widget.recipe?.category ?? '未分类';
  bool saving = false;
  bool picking = false;
  bool get editing => widget.recipe != null;
  bool get versionMode => widget.recipeId != null;

  String get pageTitle => versionMode
      ? widget.copyAsNew
            ? '复制为新版本'
            : widget.bundle == null
            ? '新建版本'
            : '编辑版本'
      : editing
      ? '编辑菜谱信息'
      : '新增菜谱';

  Future<void> _pickImages(ImageSource source) async {
    if (picking || imagePaths.length >= maxRecipeImages) return;
    setState(() => picking = true);
    try {
      final picker = ImagePicker();
      final available = maxRecipeImages - imagePaths.length;
      final List<XFile> images;
      if (source == ImageSource.camera || available == 1) {
        final image = await picker.pickImage(source: source, imageQuality: 85);
        images = [?image];
      } else {
        images = await picker.pickMultiImage(
          imageQuality: 85,
          limit: available,
        );
      }
      if (!mounted) return;
      setState(() {
        for (final image in images.take(available)) {
          imagePaths.add(image.path);
          pickedPaths.add(image.path);
        }
      });
      if (images.length > available) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('最多保留 5 张图片')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              source == ImageSource.camera ? '无法拍照，请检查相机权限' : '无法选择图片，请检查相册权限',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> _chooseCategory() async {
    FocusScope.of(context).unfocus();
    final selected = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const RecipeCategoriesPage(selectMode: true),
      ),
    );
    if (!mounted) return;
    if (selected != null) {
      setState(() => category = selected);
      return;
    }
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
    for (final controller in [
      title,
      description,
      ingredients,
      steps,
      rating,
      feedback,
      improvement,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (saving || picking) return;
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
    final copied = <String>[];
    var committed = false;
    try {
      final repo = await ref.read(repositoryProvider.future);
      final savedImages = <String>[];
      for (final path in imagePaths) {
        if (!pickedPaths.contains(path)) {
          savedImages.add(path);
          continue;
        }
        final dir = await getApplicationDocumentsDirectory();
        final photos = Directory(p.join(dir.path, 'photos'));
        await photos.create(recursive: true);
        final destination = p.join(
          photos.path,
          '${DateTime.now().microsecondsSinceEpoch}_${savedImages.length}${p.extension(path)}',
        );
        await File(path).copy(destination);
        copied.add(destination);
        savedImages.add(destination);
      }
      final String id;
      if (versionMode) {
        id = widget.recipeId!;
        await repo.saveVersion(
          recipeId: id,
          versionId: widget.copyAsNew ? null : widget.bundle?.version.id,
          title: title.text.trim(),
          note: description.text.trim(),
          ingredients: parseRecipeIngredients(
            ingredients.text,
            existing: widget.bundle?.ingredients ?? const [],
          ),
          steps: parseRecipeSteps(
            steps.text,
            existing:
                widget.bundle?.steps.map((step) => step.content).toList() ??
                const [],
          ),
          imagePaths: savedImages,
          rating: double.tryParse(rating.text.trim()),
          feedback: feedback.text.trim(),
          improvement: improvement.text.trim(),
        );
      } else if (editing) {
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
          imagePaths: savedImages,
          rating: double.tryParse(rating.text.trim()),
          feedback: feedback.text.trim(),
          improvement: improvement.text.trim(),
        );
      }
      committed = true;
      if (!mounted) return;
      ref.invalidate(recipesProvider);
      ref.invalidate(recipeProvider(id));
      ref.invalidate(versionsProvider(id));
      ref.invalidate(statsProvider);
      if (widget.bundle != null) {
        ref.invalidate(bundleProvider(widget.bundle!.version.id));
      }
      Navigator.pop(context, versionMode ? true : id);
    } catch (_) {
      if (!committed) {
        for (final path in copied) {
          try {
            await File(path).delete();
          } catch (_) {}
        }
      }
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
        title: Text(pageTitle),
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
              onPressed: saving || picking ? null : save,
              icon: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded, size: 20),
              label: Text(
                saving
                    ? '保存中…'
                    : versionMode
                    ? '保存版本'
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
                    versionMode
                        ? '记下这次的做法、成品和心得。'
                        : editing
                        ? '修改名称、分类和简介，保留所有烹饪版本。'
                        : '先记下一道菜，再慢慢打磨成自己的拿手菜。',
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
                    decoration: _decoration(
                      versionMode ? '版本名称' : '菜谱名称 *',
                      versionMode ? '例如：少盐改良版' : '例如：番茄牛腩',
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? versionMode
                              ? '请输入版本名称'
                              : '请输入菜谱名称'
                        : null,
                  ),
                  if (!versionMode) ...[
                    ref
                        .watch(recipeCategoriesProvider)
                        .when(
                          loading: () => const LinearProgressIndicator(),
                          error: (_, _) => TextButton.icon(
                            onPressed: () =>
                                ref.invalidate(recipeCategoryOrdersProvider),
                            icon: const Icon(Icons.refresh),
                            label: const Text('分类加载失败，点击重试'),
                          ),
                          data: (categories) {
                            final selected = categories.contains(category)
                                ? category
                                : '未分类';
                            return TextFormField(
                              key: ValueKey(selected),
                              initialValue: selected,
                              readOnly: true,
                              onTap: _chooseCategory,
                              decoration: _decoration('菜谱分类', '未分类 · 点击选择')
                                  .copyWith(
                                    suffixIcon: const Icon(Icons.chevron_right),
                                  ),
                            );
                          },
                        ),
                  ],
                  TextFormField(
                    controller: description,
                    minLines: 2,
                    maxLines: 4,
                    decoration: _decoration(
                      versionMode ? '版本说明' : '一句话简介',
                      versionMode ? '记下这次做法的调整' : '记下风味、口感，或这道菜的特别之处',
                    ),
                  ),
                ]),
                if (!editing) ...[
                  const SizedBox(height: 16),
                  _section(
                    '准备食材',
                    '选填 · 每行一种，最后一个空格后的文字作为用量',
                    [
                      TextFormField(
                        controller: ingredients,
                        minLines: 4,
                        maxLines: 10,
                        decoration: _decoration(
                          '食材与用量',
                          '牛腩 500克\n番茄 2个\n盐 随便写',
                        ),
                      ),
                    ],
                  ),
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
                  const SizedBox(height: 16),
                  _section(
                    '成品照片',
                    '${imagePaths.length}/$maxRecipeImages · 选填，第一张用作封面',
                    [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (var i = 0; i < imagePaths.length; i++)
                            Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(
                                    File(imagePaths[i]),
                                    width: 88,
                                    height: 88,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        const SizedBox.square(
                                          dimension: 88,
                                          child: Icon(
                                            Icons.broken_image_outlined,
                                          ),
                                        ),
                                  ),
                                ),
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: IconButton.filledTonal(
                                    tooltip: '移除第 ${i + 1} 张图片',
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.close, size: 16),
                                    onPressed: picking
                                        ? null
                                        : () => setState(
                                            () => imagePaths.removeAt(i),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed:
                                picking || imagePaths.length >= maxRecipeImages
                                ? null
                                : () => _pickImages(ImageSource.camera),
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: const Text('拍照'),
                          ),
                          OutlinedButton.icon(
                            onPressed:
                                picking || imagePaths.length >= maxRecipeImages
                                ? null
                                : () => _pickImages(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('选择图片'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _section('烹饪复盘', '选填 · 记录这次的味道与下次的期待', [
                    TextFormField(
                      controller: rating,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: _decoration('评分（0-5）', '例如：4.5'),
                      validator: (text) {
                        if (text == null || text.trim().isEmpty) return null;
                        final value = double.tryParse(text.trim());
                        return value == null ||
                                !value.isFinite ||
                                value < 0 ||
                                value > 5
                            ? '请输入 0 到 5 之间的评分'
                            : null;
                      },
                    ),
                    TextFormField(
                      controller: feedback,
                      minLines: 3,
                      maxLines: 6,
                      decoration: _decoration('成品反馈', '这次的口感、风味如何？'),
                    ),
                    TextFormField(
                      controller: improvement,
                      minLines: 3,
                      maxLines: 6,
                      decoration: _decoration('下次改进方向', '下次想尝试什么调整？'),
                    ),
                  ]),
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
