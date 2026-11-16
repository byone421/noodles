import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/inventory_settings.dart';
import '../../../providers/inventory_providers.dart';

class InventoryCategoriesPage extends ConsumerStatefulWidget {
  const InventoryCategoriesPage({super.key, this.selectMode = false});
  final bool selectMode;
  @override
  ConsumerState<InventoryCategoriesPage> createState() =>
      _InventoryCategoriesPageState();
}

class _InventoryCategoriesPageState
    extends ConsumerState<InventoryCategoriesPage> {
  String query = '';

  Future<void> _edit([InventoryCategory? category]) => showDialog<void>(
    context: context,
    builder: (_) => _CategoryEditor(category: category),
  );

  Future<void> _delete(InventoryCategory category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除分类？'),
        content: Text(
          '确定删除“${category.name}”？其中的 ${category.itemCount} 件物品将保留，并移到未分类。',
        ),
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
      await (await ref.read(inventoryRepositoryProvider.future))
          .deleteCategory(category.id!);
      if (mounted) refreshInventory(ref);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('删除失败，请重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.selectMode ? '选择分类' : '万物分类设置'),
      centerTitle: true,
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      actions: [
        IconButton(
          onPressed: () => _edit(),
          tooltip: '添加分类',
          icon: const Icon(Icons.add),
        ),
      ],
    ),
    body: ref
        .watch(inventoryCategoriesProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: TextButton(
              onPressed: () => ref.invalidate(inventoryCategoriesProvider),
              child: const Text('分类加载失败，点击重试'),
            ),
          ),
          data: (categories) {
            final filtered = categories
                .where(
                  (c) => c.name.toLowerCase().contains(
                    query.trim().toLowerCase(),
                  ),
                )
                .toList();
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                TextField(
                  onChanged: (value) => setState(() => query = value),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '搜索分类',
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '分类管理 · ${categories.length}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 10),
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.category_outlined,
                          size: 40,
                          color: AppColors.muted,
                        ),
                        const SizedBox(height: 12),
                        Text(query.trim().isEmpty ? '还没有分类' : '没有找到匹配的分类'),
                        if (query.trim().isEmpty)
                          TextButton.icon(
                            onPressed: () => _edit(),
                            icon: const Icon(Icons.add),
                            label: const Text('添加第一个分类'),
                          ),
                      ],
                    ),
                  ),
                ...filtered.map(
                  (category) => Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: AppColors.border),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      title: Text(
                        category.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text('排序 ${category.sortOrder}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.soft,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${category.itemCount} 件',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: '分类操作',
                            onSelected: (action) => action == 'edit'
                                ? _edit(category)
                                : _delete(category),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('编辑分类')),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('删除分类'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      onTap: () => Navigator.pop(context, category),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
  );
}

class _CategoryEditor extends ConsumerStatefulWidget {
  const _CategoryEditor({this.category});
  final InventoryCategory? category;
  @override
  ConsumerState<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends ConsumerState<_CategoryEditor> {
  final key = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.category?.name);
  late final order = TextEditingController(
    text: '${widget.category?.sortOrder ?? 0}',
  );
  String? error;
  bool saving = false;
  @override
  void dispose() {
    name.dispose();
    order.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!key.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await (await ref.read(inventoryRepositoryProvider.future)).saveCategory(
        InventoryCategory(
          id: widget.category?.id,
          name: name.text,
          description: widget.category?.description ?? '',
          sortOrder: int.tryParse(order.text) ?? 0,
        ),
      );
      if (!mounted) return;
      refreshInventory(ref);
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e is ArgumentError ? '${e.message}' : '保存失败，请重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: Text(widget.category == null ? '添加分类' : '编辑分类'),
      scrollable: true,
      content: Form(
        key: key,
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                autofocus: true,
                maxLength: 30,
                decoration: const InputDecoration(labelText: '分类名称'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '请输入分类名称' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: order,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(9),
                ],
                decoration: const InputDecoration(
                  labelText: '排序',
                  helperText: '数字越小，排列越靠前',
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: saving ? null : _save,
          child: Text(saving ? '保存中…' : '保存'),
        ),
      ],
    ),
  );
}
