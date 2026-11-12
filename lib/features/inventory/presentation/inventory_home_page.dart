import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/inventory_item.dart';
import '../../../models/inventory_settings.dart';
import '../../../providers/inventory_providers.dart';
import 'inventory_add_item_page.dart';

enum _InventorySort {
  expiry('最近到期'),
  updated('最近更新'),
  created('最近创建');

  const _InventorySort(this.label);
  final String label;
}

class InventoryHomePage extends ConsumerStatefulWidget {
  const InventoryHomePage({super.key, this.initialCategoryId});
  final int? initialCategoryId;

  @override
  ConsumerState<InventoryHomePage> createState() => _InventoryHomePageState();
}

class _InventoryHomePageState extends ConsumerState<InventoryHomePage>
    with WidgetsBindingObserver {
  final search = TextEditingController();
  int? selectedRange;
  _InventorySort sort = _InventorySort.created;
  late int? selectedCategory = widget.initialCategoryId;
  Timer? dayTimer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleDayRefresh();
  }

  void _scheduleDayRefresh() {
    dayTimer?.cancel();
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    dayTimer = Timer(tomorrow.difference(now), () {
      if (!mounted) return;
      setState(() {});
      _scheduleDayRefresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
      _scheduleDayRefresh();
    }
  }

  @override
  void dispose() {
    search.dispose();
    WidgetsBinding.instance.removeObserver(this);
    dayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ref
        .watch(inventoryItemsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: TextButton(
              onPressed: () => ref.invalidate(inventoryItemsProvider),
              child: const Text('物品加载失败，点击重试'),
            ),
          ),
          data: (items) => ref
              .watch(expirySettingsProvider)
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => Center(
                  child: TextButton(
                    onPressed: () => ref.invalidate(expirySettingsProvider),
                    child: const Text('提醒设置加载失败，点击重试'),
                  ),
                ),
                data: (settings) => ref
                    .watch(inventoryCategoriesProvider)
                    .when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (_, _) => Center(
                        child: TextButton(
                          onPressed: () =>
                              ref.invalidate(inventoryCategoriesProvider),
                          child: const Text('分类加载失败，点击重试'),
                        ),
                      ),
                      data: (categories) =>
                          _content(items, settings, categories),
                    ),
              ),
        );
  }

  Widget _content(
    List<InventoryItem> items,
    ExpirySettings settings,
    List<InventoryCategory> categories,
  ) {
    final categoryId =
        selectedCategory == -1 ||
            categories.any((c) => c.id == selectedCategory)
        ? selectedCategory
        : null;
    final categoryName = categoryId == -1
        ? '未分类'
        : categories.where((c) => c.id == categoryId).firstOrNull?.name;
    final range = selectedRange == null
        ? null
        : selectedRange == -1
        ? -1
        : settings.days[selectedRange!];
    final filtered = items.where((item) {
      final matchesSearch = '${item.name} ${item.category} ${item.location}'
          .toLowerCase()
          .contains(search.text.trim().toLowerCase());
      final matchesCategory =
          categoryId == null ||
          (categoryId == -1
              ? item.categoryId == null
              : item.categoryId == categoryId);
      return matchesSearch && matchesCategory && item.matchesRange(range);
    }).toList();
    filtered.sort((a, b) {
      final difference = switch (sort) {
        _InventorySort.created => (b.id ?? 0).compareTo(a.id ?? 0),
        _InventorySort.expiry => a.remainingDays.compareTo(b.remainingDays),
        _InventorySort.updated =>
          a.updatedAt == null
              ? (b.updatedAt == null ? 0 : 1)
              : b.updatedAt == null
              ? -1
              : b.updatedAt!.compareTo(a.updatedAt!),
      };
      return difference == 0 ? (b.id ?? 0).compareTo(a.id ?? 0) : difference;
    });

    return RefreshIndicator(
      onRefresh: () async {
        refreshInventory(ref);
        ref.invalidate(expirySettingsProvider);
        await ref.read(inventoryItemsProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 96),
        children: [
          Text(
            '物品管理',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            '掌控万物',
            style: Theme.of(context).textTheme.headlineLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '搜索物品、分类、位置',
            ),
          ),
          const SizedBox(height: 14),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 2.15,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: [
              _status(
                items,
                '已过期',
                -1,
                -1,
                Icons.error_outline,
                const Color(0xFFB9565C),
              ),
              _status(
                items,
                '${settings.near} 天内到期',
                0,
                settings.near,
                Icons.schedule,
                AppColors.accent,
              ),
              _status(
                items,
                '${settings.middle} 天内到期',
                1,
                settings.middle,
                Icons.event,
                const Color(0xFF557DB5),
              ),
              _status(
                items,
                '${settings.far} 天内到期',
                2,
                settings.far,
                Icons.event_available,
                const Color(0xFF4F9475),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  categoryName != null
                      ? '$categoryName  ${filtered.length}'
                      : selectedRange == null && search.text.trim().isEmpty
                      ? '全部物品  ${filtered.length}'
                      : '筛选结果  ${filtered.length}',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              PopupMenuButton<_InventorySort>(
                tooltip: '排序',
                initialValue: sort,
                onSelected: (value) => setState(() => sort = value),
                itemBuilder: (_) => _InventorySort.values
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
          if (selectedRange != null ||
              categoryId != null ||
              search.text.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  selectedRange = null;
                  selectedCategory = null;
                  search.clear();
                }),
                icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                label: const Text('清除筛选'),
              ),
            ),
          if (filtered.isEmpty)
            _empty()
          else
            ...filtered.map((item) => _itemCard(item, settings)),
        ],
      ),
    );
  }

  Widget _status(
    List<InventoryItem> items,
    String title,
    int index,
    int range,
    IconData icon,
    Color color,
  ) {
    final count = items.where((item) => item.matchesRange(range)).length;
    final selected = selectedRange == index;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      color: selected ? AppColors.soft : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => selectedRange = selected ? null : index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$count',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openItem(InventoryItem item, {bool copy = false}) =>
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InventoryAddItemPage(item: item, copy: copy),
        ),
      );

  Future<void> _deleteItem(InventoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除物品？'),
        content: Text('确定删除“${item.name}”？此操作无法撤销。'),
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
          .deleteItem(item.id!);
      if (mounted) refreshInventory(ref);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('删除失败，请重试')));
    }
  }

  Widget _itemCard(InventoryItem item, ExpirySettings settings) {
    final days = item.remainingDays;
    final color = days < 0
        ? const Color(0xFFB9565C)
        : days <= settings.near
        ? AppColors.accent
        : days <= settings.middle
        ? const Color(0xFF557DB5)
        : days <= settings.far
        ? const Color(0xFF4F9475)
        : AppColors.primary;
    final initial = Text(
      item.name.isEmpty ? '?' : item.name.characters.first,
      style: const TextStyle(
        color: AppColors.primary,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
    );
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(top: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openItem(item),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppColors.soft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: item.imagePaths.isEmpty
                    ? initial
                    : Image.file(
                        File(item.imagePaths.first),
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => initial,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [item.category, item.location]
                          .where((value) => value.isNotEmpty)
                          .join(' · ')
                          .ifEmpty('未分类'),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '到期 ${_date(item.expiryDate)}${item.quantity.isEmpty ? '' : ' · ${item.quantity}'}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${days.abs()}天',
                    style: TextStyle(
                      color: color,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    days < 0 ? '已过期' : '剩余',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              PopupMenuButton<String>(
                tooltip: '物品操作',
                padding: EdgeInsets.zero,
                onSelected: (value) {
                  if (value == 'delete') {
                    _deleteItem(item);
                  } else {
                    _openItem(item, copy: value == 'copy');
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑物品')),
                  PopupMenuItem(value: 'copy', child: Text('复制物品')),
                  PopupMenuItem(value: 'delete', child: Text('删除物品')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Column(
      children: [
        const Icon(
          Icons.inventory_2_outlined,
          size: 42,
          color: AppColors.muted,
        ),
        const SizedBox(height: 10),
        Text(
          search.text.isEmpty &&
                  selectedRange == null &&
                  selectedCategory == null
              ? '还没有记录物品'
              : '没有找到匹配的物品',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        FilledButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const InventoryAddItemPage()),
          ),
          icon: const Icon(Icons.add),
          label: const Text('添加一件物品'),
        ),
      ],
    ),
  );

  String _date(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
