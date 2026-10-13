import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/recipe_providers.dart';

class NewRecipePage extends ConsumerStatefulWidget {
  const NewRecipePage({super.key});
  @override
  ConsumerState<NewRecipePage> createState() => _NewRecipePageState();
}

class _NewRecipePageState extends ConsumerState<NewRecipePage> {
  final formKey = GlobalKey<FormState>();
  final title = TextEditingController(), description = TextEditingController(), ingredients = TextEditingController(), steps = TextEditingController();
  String category = '家常菜'; bool saving = false;
  @override void dispose() { title.dispose(); description.dispose(); ingredients.dispose(); steps.dispose(); super.dispose(); }

  Future<void> save() async { if (!formKey.currentState!.validate()) return; setState(() => saving = true); try { final id = await (await ref.read(repositoryProvider.future)).createRecipe(title: title.text.trim(), category: category, description: description.text.trim(), ingredientsText: ingredients.text, stepsText: steps.text); if (mounted) Navigator.pop(context, id); } catch (e) { if (mounted) { setState(() => saving = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建失败：$e'))); } } }

  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('记录一道新菜')), body: Form(key: formKey, child: ListView(padding: const EdgeInsets.all(20), children: [
    TextFormField(controller: title, decoration: const InputDecoration(labelText: '菜谱名称', hintText: '例如：周末咖喱鸡'), validator: (v) => v == null || v.trim().isEmpty ? '请输入菜谱名称后再创建' : null), const SizedBox(height: 14),
    DropdownButtonFormField<String>(initialValue: category, decoration: const InputDecoration(labelText: '分类'), items: ['家常菜', '快手菜', '面食', '汤羹', '烘焙'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => category = v!), const SizedBox(height: 14),
    TextFormField(controller: description, decoration: const InputDecoration(labelText: '一句话简介'), maxLines: 2), const SizedBox(height: 14),
    TextFormField(controller: ingredients, decoration: const InputDecoration(labelText: '第一版材料', hintText: '每行一种，例如：番茄 3 个'), minLines: 4, maxLines: 8), const SizedBox(height: 14),
    TextFormField(controller: steps, decoration: const InputDecoration(labelText: '第一版步骤', hintText: '每行一个步骤'), minLines: 5, maxLines: 10), const SizedBox(height: 22),
    FilledButton.icon(onPressed: saving ? null : save, icon: saving ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check), label: const Text('创建菜谱')),
  ])));
}
