import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../models/recipe.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/recipe_providers.dart';

class EditVersionPage extends ConsumerStatefulWidget {
  const EditVersionPage({
    super.key,
    required this.recipeId,
    this.bundle,
    this.copyAsNew = false,
  });
  final String recipeId;
  final VersionBundle? bundle;
  final bool copyAsNew;
  @override
  ConsumerState<EditVersionPage> createState() => _EditVersionPageState();
}

class _EditVersionPageState extends ConsumerState<EditVersionPage> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController title, note, rating, feedback, improvement;
  late final List<_IngredientDraft> ingredients;
  late final List<TextEditingController> steps;
  String? imagePath, pickedImagePath;
  bool removePhoto = false;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final b = widget.bundle;
    title = TextEditingController(
      text: widget.copyAsNew
          ? '${b?.version.title ?? '新版本'} 副本'
          : b?.version.title ?? '新版本',
    );
    note = TextEditingController(text: b?.version.note);
    rating = TextEditingController(text: b?.version.rating?.toString() ?? '');
    feedback = TextEditingController(text: b?.finishedRecord?.note);
    improvement = TextEditingController(
      text: b?.finishedRecord?.nextImprovement,
    );
    ingredients =
        b?.ingredients.map(_IngredientDraft.fromIngredient).toList() ?? [];
    steps =
        b?.steps.map((s) => TextEditingController(text: s.content)).toList() ??
        [];
    imagePath = b?.finishedRecord?.imagePath;
  }

  @override
  void dispose() {
    for (final c in [title, note, rating, feedback, improvement, ...steps]) {
      c.dispose();
    }
    for (final item in ingredients) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> pickImage() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (picked != null && mounted) {
        setState(() {
          pickedImagePath = picked.path;
          removePhoto = false;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法选择照片，请检查相册权限')));
      }
    }
  }

  Future<String?> persistPickedImage() async {
    if (removePhoto) return null;
    if (pickedImagePath == null) return imagePath;
    final dir = await getApplicationDocumentsDirectory();
    final photos = Directory(p.join(dir.path, 'photos'));
    await photos.create(recursive: true);
    final destination = p.join(
      photos.path,
      '${DateTime.now().microsecondsSinceEpoch}${p.extension(pickedImagePath!)}',
    );
    await File(pickedImagePath!).copy(destination);
    return destination;
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
    setState(() => saving = true);
    String? newlyPersistedImage;
    try {
      final savedImagePath = await persistPickedImage();
      if (pickedImagePath != null) newlyPersistedImage = savedImagePath;
      final ingredientValues = ingredients
          .where((i) => i.name.text.trim().isNotEmpty)
          .map(
            (i) => IngredientInput(
              name: i.name.text.trim(),
              amount: i.amount.text.trim(),
              unit: i.unit.text.trim(),
            ),
          )
          .toList();
      final stepValues = steps
          .map((s) => s.text.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      await (await ref.read(repositoryProvider.future)).saveVersion(
        recipeId: widget.recipeId,
        versionId: widget.copyAsNew ? null : widget.bundle?.version.id,
        title: title.text.trim(),
        note: note.text.trim(),
        rating: rating.text.trim().isEmpty ? null : double.parse(rating.text),
        ingredients: ingredientValues,
        steps: stepValues,
        imagePath: savedImagePath,
        feedback: feedback.text.trim(),
        improvement: improvement.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      final orphan = newlyPersistedImage;
      if (orphan != null) {
        final file = File(orphan);
        if (await file.exists()) await file.delete();
      }
      if (mounted) {
        setState(() => saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AbsorbPointer(
      absorbing: saving,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          title: Text(
            widget.copyAsNew
                ? '复制为新版本'
                : widget.bundle == null
                ? '新建版本'
                : '编辑版本',
          ),
        ),
        body: Form(
          key: formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: title,
                  decoration: const InputDecoration(labelText: '版本名称'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '请输入版本名称' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: note,
                  decoration: const InputDecoration(labelText: '版本说明'),
                  maxLines: 2,
                ),
                const SizedBox(height: 18),
                _heading(
                  '材料列表',
                  () =>
                      setState(() => ingredients.add(_IngredientDraft.empty())),
                ),
                if (ingredients.isEmpty) const _EmptyLine('暂无材料，点击右侧加号添加'),
                ...List.generate(ingredients.length, _ingredientRow),
                const SizedBox(height: 18),
                _heading(
                  '制作步骤',
                  () => setState(() => steps.add(TextEditingController())),
                ),
                if (steps.isEmpty) const _EmptyLine('暂无步骤，点击右侧加号添加'),
                ...List.generate(steps.length, _stepRow),
                const SizedBox(height: 18),
                TextFormField(
                  controller: rating,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: '评分（0-5）'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final value = double.tryParse(v);
                    return value == null ||
                            !value.isFinite ||
                            value < 0 ||
                            value > 5
                        ? '请输入 0 到 5 之间的评分'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: pickImage,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(
                    (pickedImagePath ?? imagePath) == null
                        ? '选择成品照片'
                        : '更换成品照片',
                  ),
                ),
                if (!removePhoto && (pickedImagePath ?? imagePath) != null)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      pickedImagePath = null;
                      imagePath = null;
                      removePhoto = true;
                    }),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('移除成品照片'),
                  ),
                if ((pickedImagePath ?? imagePath) != null &&
                    File((pickedImagePath ?? imagePath)!).existsSync())
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File((pickedImagePath ?? imagePath)!),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: feedback,
                  decoration: const InputDecoration(labelText: '成品反馈'),
                  minLines: 3,
                  maxLines: 6,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: improvement,
                  decoration: const InputDecoration(labelText: '下次改进方向'),
                  minLines: 3,
                  maxLines: 6,
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: saving ? null : save,
                  icon: saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('保存版本'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _heading(String title, VoidCallback add) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      IconButton(
        onPressed: add,
        tooltip: '新增$title',
        icon: const Icon(Icons.add),
      ),
    ],
  );
  Widget _ingredientRow(int index) {
    final item = ingredients[index];
    return Card(
      key: ObjectKey(item),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            TextFormField(
              controller: item.name,
              decoration: const InputDecoration(labelText: '材料名称'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? '请输入材料名称' : null,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: item.amount,
                    decoration: const InputDecoration(labelText: '数量'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: item.unit,
                    decoration: const InputDecoration(labelText: '单位'),
                  ),
                ),
              ],
            ),
            _orderButtons(
              index,
              ingredients.length,
              () => _moveIngredient(index, -1),
              () => _moveIngredient(index, 1),
              () => setState(() {
                ingredients.removeAt(index).dispose();
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepRow(int index) => Card(
    key: ObjectKey(steps[index]),
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 14, right: 8),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Expanded(
                child: TextFormField(
                  controller: steps[index],
                  decoration: const InputDecoration(labelText: '步骤内容'),
                  minLines: 1,
                  maxLines: 5,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '请输入步骤内容' : null,
                ),
              ),
            ],
          ),
          _orderButtons(
            index,
            steps.length,
            () => _moveStep(index, -1),
            () => _moveStep(index, 1),
            () => setState(() => steps.removeAt(index).dispose()),
          ),
        ],
      ),
    ),
  );
  Widget _orderButtons(
    int index,
    int length,
    VoidCallback up,
    VoidCallback down,
    VoidCallback remove,
  ) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      IconButton(
        onPressed: index == 0 ? null : up,
        tooltip: '上移',
        icon: const Icon(Icons.arrow_upward),
      ),
      IconButton(
        onPressed: index == length - 1 ? null : down,
        tooltip: '下移',
        icon: const Icon(Icons.arrow_downward),
      ),
      IconButton(
        onPressed: remove,
        tooltip: '删除',
        icon: const Icon(Icons.delete_outline),
      ),
    ],
  );
  void _moveIngredient(int index, int delta) => setState(() {
    final item = ingredients.removeAt(index);
    ingredients.insert(index + delta, item);
  });
  void _moveStep(int index, int delta) => setState(() {
    final item = steps.removeAt(index);
    steps.insert(index + delta, item);
  });
}

class _IngredientDraft {
  _IngredientDraft(this.name, this.amount, this.unit);
  factory _IngredientDraft.empty() => _IngredientDraft(
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  );
  factory _IngredientDraft.fromIngredient(Ingredient i) => _IngredientDraft(
    TextEditingController(text: i.name),
    TextEditingController(text: i.amount),
    TextEditingController(text: i.unit),
  );
  final TextEditingController name, amount, unit;
  void dispose() {
    name.dispose();
    amount.dispose();
    unit.dispose();
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Text(text, style: const TextStyle(color: Colors.grey)),
  );
}
