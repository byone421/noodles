import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/active_filter_bar.dart';
import '../../../models/account_entry.dart';
import '../../../providers/accounting_providers.dart';
import 'account_categories_page.dart';

const _paymentMethods = ['微信', '支付宝', '亲密付', '银行卡', '信用卡', '云闪付', '零钱', '现金'];

class AccountingPage extends ConsumerStatefulWidget {
  const AccountingPage({super.key, this.initialCategory});

  final AccountCategory? initialCategory;

  @override
  ConsumerState<AccountingPage> createState() => _AccountingPageState();
}

class _AccountingPageState extends ConsumerState<AccountingPage> {
  late AccountCategory? selectedCategory = widget.initialCategory;
  String? selectedPaymentMethod;
  late DateTime start = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime end = DateTime(
    DateTime.now().year,
    DateTime.now().month + 1,
    0,
  );

  ({DateTime start, DateTime end}) get range => (start: start, end: end);

  Future<void> _chooseRange() async {
    final value = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: DateTimeRange(start: start, end: end),
      helpText: '选择统计日期范围',
      saveText: '完成',
    );
    if (value != null) {
      setState(() {
        start = value.start;
        end = value.end;
      });
    }
  }

  Future<void> _chooseCategory() async {
    final category = await Navigator.push<AccountCategory>(
      context,
      MaterialPageRoute(
        builder: (_) => const AccountCategoriesPage(selectMode: true),
      ),
    );
    if (category != null && mounted) {
      setState(() => selectedCategory = category);
    }
  }

  Future<void> _openEntry([AccountEntry? entry]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AccountEntryPage(entry: entry)),
    );
    if (saved == true && mounted) ref.invalidate(accountEntriesProvider);
  }

  Future<void> _deleteEntry(AccountEntry entry) async {
    final id = entry.id;
    if (id == null) return;
    await (await ref.read(accountingRepositoryProvider.future)).deleteEntry(id);
    ref.invalidate(accountEntriesProvider(range));
  }

  @override
  Widget build(BuildContext context) => ref
      .watch(accountEntriesProvider(range))
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(accountEntriesProvider(range)),
            icon: const Icon(Icons.refresh),
            label: const Text('账本加载失败，点击重试'),
          ),
        ),
        data: (allEntries) {
          final category = selectedCategory;
          final payment = selectedPaymentMethod;
          final entries = allEntries
              .where(
                (entry) =>
                    (category == null ||
                        (entry.type == category.type &&
                            entry.categoryId == category.id)) &&
                    (payment == null || entry.paymentMethod == payment),
              )
              .toList();
          final expense = entries
              .where((e) => e.type == AccountType.expense)
              .toList();
          final income = entries
              .where((e) => e.type == AccountType.income)
              .toList();
          int total(List<AccountEntry> values) =>
              values.fold<int>(0, (sum, item) => sum + item.amountCents);
          final grouped = <String, int>{};
          for (final entry in entries) {
            final key = '${entry.type.name}:${entry.category}';
            grouped.update(
              key,
              (value) => value + entry.amountCents,
              ifAbsent: () => entry.amountCents,
            );
          }
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  children: [
                    Text(
                      '收支概览',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '记一笔，心里有数',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _chooseRange,
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text('${_date(start)}  至  ${_date(end)}'),
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                        side: const BorderSide(color: AppColors.border),
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _chooseCategory,
                          icon: const Icon(Icons.category_outlined),
                          label: const Text('分类'),
                        ),
                        MenuAnchor(
                          menuChildren: [
                            for (final method in _paymentMethods)
                              MenuItemButton(
                                onPressed: () => setState(
                                  () => selectedPaymentMethod = method,
                                ),
                                trailingIcon: payment == method
                                    ? const Icon(Icons.check)
                                    : null,
                                child: Text(method),
                              ),
                          ],
                          builder: (_, controller, _) => OutlinedButton.icon(
                            onPressed: () => controller.isOpen
                                ? controller.close()
                                : controller.open(),
                            icon: const Icon(Icons.payments_outlined),
                            label: const Text('支付方式'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ActiveFilterBar(
                      filters: [
                        if (category != null)
                          (
                            label:
                                '分类：${category.type == AccountType.expense ? '支出' : '收入'} · ${category.name}',
                            clearTooltip: '清除分类筛选',
                            onClear: () =>
                                setState(() => selectedCategory = null),
                          ),
                        if (payment != null)
                          (
                            label: '支付方式：$payment',
                            clearTooltip: '清除支付方式筛选',
                            onClear: () =>
                                setState(() => selectedPaymentMethod = null),
                          ),
                      ],
                      onClear: () => setState(() {
                        selectedCategory = null;
                        selectedPaymentMethod = null;
                      }),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _totalCard(
                            '总支出',
                            total(expense),
                            const Color(0xFF4F9475),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _totalCard(
                            '总收入',
                            total(income),
                            const Color(0xFFB9565C),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _sectionTitle('分类统计'),
                    if (grouped.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          category == null && payment == null
                              ? '所选日期内还没有记录'
                              : '没有符合筛选条件的记录',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      )
                    else ...[
                      _categorySummary(
                        '支出',
                        AccountType.expense,
                        grouped,
                        total(expense),
                      ),
                      _categorySummary(
                        '收入',
                        AccountType.income,
                        grouped,
                        total(income),
                      ),
                    ],
                    const SizedBox(height: 18),
                    _sectionTitle('收支明细（${entries.length}）'),
                    if (entries.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.receipt_long_outlined,
                              size: 38,
                              color: AppColors.muted,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              payment != null
                                  ? '没有符合筛选条件的收支明细'
                                  : category == null
                                  ? '还没有收支记录'
                                  : '所选分类在此日期内还没有记录',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _openEntry,
                              icon: const Icon(Icons.add),
                              label: const Text('记下第一笔'),
                            ),
                          ],
                        ),
                      )
                    else
                      ...entries.map((entry) => _entryTile(entry)),
                  ],
                ),
              ),
            ],
          );
        },
      );

  Widget _totalCard(String label, int cents, Color color) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            '¥${_money(cents)}',
            maxLines: 1,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
    ),
  );

  Widget _categorySummary(
    String title,
    AccountType type,
    Map<String, int> grouped,
    int all,
  ) {
    final values =
        grouped.entries
            .where((entry) => entry.key.startsWith('${type.name}:'))
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    if (values.isEmpty) return const SizedBox.shrink();
    final color = type == AccountType.expense
        ? const Color(0xFF4F9475)
        : const Color(0xFFB9565C);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
          ),
          const SizedBox(height: 8),
          ...values.map((item) {
            final name = item.key.substring(type.name.length + 1);
            final ratio = all == 0 ? 0.0 : item.value / all;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 5,
                      color: color,
                      backgroundColor: AppColors.soft,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '¥${_money(item.value)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _entryTile(AccountEntry entry) {
    final isExpense = entry.type == AccountType.expense;
    final color = isExpense ? const Color(0xFF4F9475) : const Color(0xFFB9565C);
    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除这条记录？'),
          content: const Text('删除后不会计入统计。'),
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
      ),
      onDismissed: (_) => _deleteEntry(entry),
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.only(right: 18),
        alignment: Alignment.centerRight,
        color: const Color(0xFFB9565C),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: InkWell(
          onTap: () => _openEntry(entry),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isExpense ? Icons.north_east : Icons.south_west,
                    color: color,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.category,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        [
                              _date(entry.date),
                              entry.note,
                              if (entry.categoryId != null) entry.category,
                              ?entry.paymentMethod,
                            ]
                            .map((part) => part.trim())
                            .where((part) => part.isNotEmpty)
                            .join(' · '),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${isExpense ? '-' : '+'}¥${_money(entry.amountCents)}',
                  style: TextStyle(fontWeight: FontWeight.w800, color: color),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _date(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
  static String _money(int cents) => (cents / 100).toStringAsFixed(2);
}

class AccountEntryPage extends ConsumerStatefulWidget {
  const AccountEntryPage({
    super.key,
    this.entry,
    this.initialAmount = '',
    this.initialNote = '',
  });
  final AccountEntry? entry;
  final String initialAmount;
  final String initialNote;

  @override
  ConsumerState<AccountEntryPage> createState() => _AccountEntryPageState();
}

class _AccountEntryPageState extends ConsumerState<AccountEntryPage> {
  final formKey = GlobalKey<FormState>();
  final amount = TextEditingController();
  final note = TextEditingController();
  AccountType type = AccountType.expense;
  DateTime date = DateTime.now();
  int? categoryId;
  String? categoryName;
  String? paymentMethod;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    if (entry == null) {
      amount.text = widget.initialAmount;
      note.text = widget.initialNote;
      return;
    }
    amount.text = (entry.amountCents / 100).toStringAsFixed(2);
    note.text = entry.note;
    type = entry.type;
    date = entry.date;
    categoryId = entry.categoryId;
    categoryName = entry.category;
    paymentMethod = entry.paymentMethod;
  }

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!formKey.currentState!.validate() || saving) return;
    if (ref.read(accountCategoriesProvider(type)).isLoading) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('分类加载中，请稍后重试')));
      return;
    }
    final cents = ((double.parse(amount.text) * 100).round());
    setState(() => saving = true);
    try {
      final categories = await (await ref.read(
        accountingRepositoryProvider.future,
      )).listCategories(type);
      final category = _selectedCategory(categories);
      if (widget.entry == null && category == null) {
        throw StateError('没有可用分类');
      }
      await (await ref.read(accountingRepositoryProvider.future)).saveEntry(
        AccountEntry(
          id: widget.entry?.id,
          type: type,
          amountCents: cents,
          categoryId: category?.id,
          category: category?.name ?? '未分类',
          date: date,
          note: note.text.trim(),
          paymentMethod: paymentMethod,
        ),
      );
      if (mounted) {
        ref.invalidate(accountEntriesProvider);
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('保存失败，请重试')));
      }
    }
  }

  AccountCategory? _selectedCategory(List<AccountCategory> categories) =>
      categories.where((item) => item.id == categoryId).firstOrNull ??
      (widget.entry == null || type != widget.entry!.type
          ? categories.firstOrNull
          : null);

  @override
  Widget build(BuildContext context) {
    final categories =
        ref.watch(accountCategoriesProvider(type)).valueOrNull ??
        const <AccountCategory>[];
    final selectedCategory = _selectedCategory(categories);
    return Scaffold(
      appBar: AppBar(title: Text(widget.entry == null ? '记一笔' : '编辑账单')),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SegmentedButton<AccountType>(
              segments: const [
                ButtonSegment(
                  value: AccountType.expense,
                  label: Text('支出'),
                  icon: Icon(Icons.north_east),
                ),
                ButtonSegment(
                  value: AccountType.income,
                  label: Text('收入'),
                  icon: Icon(Icons.south_west),
                ),
              ],
              selected: {type},
              onSelectionChanged: (value) => setState(() {
                type = value.first;
                categoryId = null;
                categoryName = null;
              }),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: amount,
              autofocus: widget.entry == null,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(
                labelText: '金额',
                prefixText: '¥ ',
                hintText: '0.00',
              ),
              validator: (value) {
                final parsed = double.tryParse(value ?? '');
                if (parsed == null || parsed <= 0 || parsed > 999999999) {
                  return '请输入有效金额';
                }
                if ((value!.split('.').elementAtOrNull(1)?.length ?? 0) > 2) {
                  return '最多保留两位小数';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final selected = await Navigator.push<AccountCategory>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        AccountCategoriesPage(selectMode: true, type: type),
                  ),
                );
                if (selected != null && mounted) {
                  setState(() {
                    categoryId = selected.id;
                    categoryName = selected.name;
                  });
                }
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: '分类'),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        categoryName ?? selectedCategory?.name ?? '请选择分类',
                        style: TextStyle(
                          color:
                              categoryName == null && selectedCategory == null
                              ? AppColors.muted
                              : AppColors.text,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: paymentMethod,
              decoration: const InputDecoration(labelText: '支付方式'),
              hint: const Text('可选'),
              items: [
                for (final method in _paymentMethods)
                  DropdownMenuItem(value: method, child: Text(method)),
              ],
              onChanged: saving
                  ? null
                  : (value) => setState(() => paymentMethod = value),
            ),
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final value = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100, 12, 31),
                );
                if (value != null) setState(() => date = value);
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: '日期'),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(DateFormat('yyyy-MM-dd').format(date)),
                    ),
                    const Icon(Icons.calendar_today_outlined, size: 18),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: note,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: '备注',
                hintText: '可选',
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: saving ? null : _save,
                child: Text(saving ? '保存中…' : '保存记录'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
