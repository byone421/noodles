import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/account_entry.dart';
import '../../../providers/accounting_providers.dart';

class AccountCategoriesPage extends ConsumerStatefulWidget {
  const AccountCategoriesPage({super.key, this.selectMode = false, this.type});

  final bool selectMode;
  final AccountType? type;

  @override
  ConsumerState<AccountCategoriesPage> createState() =>
      _AccountCategoriesPageState();
}

class _AccountCategoriesPageState extends ConsumerState<AccountCategoriesPage> {
  late AccountType type = widget.type ?? AccountType.expense;
  String query = '';

  Future<void> _edit([AccountCategory? category]) => showDialog<void>(
    context: context,
    builder: (_) => _AccountCategoryEditor(category: category, type: type),
  );

  Future<void> _delete(AccountCategory category) async {
    final id = category.id;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除记账分类？'),
        content: Text('删除“${category.name}”后，历史记录仍会保留。'),
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
      await (await ref.read(accountingRepositoryProvider.future))
          .deleteCategory(id);
      ref.invalidate(accountCategoriesProvider(type));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('删除失败，请重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(accountCategoriesProvider(type));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.selectMode
              ? '选择${type == AccountType.expense ? '支出' : '收入'}分类'
              : '记账分类设置',
        ),
        actions: [
          IconButton(
            onPressed: () => _edit(),
            tooltip: '添加分类',
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: categories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(accountCategoriesProvider(type)),
            child: const Text('分类加载失败，点击重试'),
          ),
        ),
        data: (items) {
          final filtered = items
              .where(
                (category) => category.name.toLowerCase().contains(
                  query.trim().toLowerCase(),
                ),
              )
              .toList();
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (!widget.selectMode)
                SegmentedButton<AccountType>(
                  segments: const [
                    ButtonSegment(
                      value: AccountType.expense,
                      label: Text('支出分类'),
                    ),
                    ButtonSegment(
                      value: AccountType.income,
                      label: Text('收入分类'),
                    ),
                  ],
                  selected: {type},
                  onSelectionChanged: (selected) => setState(() {
                    type = selected.first;
                    query = '';
                  }),
                ),
              if (!widget.selectMode) const SizedBox(height: 16),
              TextField(
                onChanged: (value) => setState(() => query = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '搜索分类',
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '${type == AccountType.expense ? '支出' : '收入'}分类 · ${items.length}',
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
                      vertical: 6,
                    ),
                    title: Text(
                      category.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text('排序 ${category.sortOrder}'),
                    trailing: PopupMenuButton<String>(
                      tooltip: '分类操作',
                      onSelected: (action) => action == 'edit'
                          ? _edit(category)
                          : _delete(category),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('编辑分类')),
                        PopupMenuItem(value: 'delete', child: Text('删除分类')),
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
}

class _AccountCategoryEditor extends ConsumerStatefulWidget {
  const _AccountCategoryEditor({required this.type, this.category});

  final AccountType type;
  final AccountCategory? category;

  @override
  ConsumerState<_AccountCategoryEditor> createState() =>
      _AccountCategoryEditorState();
}

class _AccountCategoryEditorState
    extends ConsumerState<_AccountCategoryEditor> {
  final formKey = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.category?.name);
  late final order = TextEditingController(
    text: '${widget.category?.sortOrder ?? 0}',
  );
  bool saving = false;
  String? error;

  @override
  void dispose() {
    name.dispose();
    order.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (saving || !formKey.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await (await ref.read(accountingRepositoryProvider.future)).saveCategory(
        AccountCategory(
          id: widget.category?.id,
          name: name.text,
          type: widget.type,
          sortOrder: int.tryParse(order.text) ?? 0,
        ),
      );
      if (!mounted) return;
      ref.invalidate(accountCategoriesProvider(widget.type));
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
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: name,
              autofocus: true,
              maxLength: 30,
              enabled: !saving,
              decoration: const InputDecoration(labelText: '分类名称'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请输入分类名称' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: order,
              enabled: !saving,
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
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
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
