import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/inventory_item.dart';
import '../../../models/inventory_settings.dart';
import '../../../providers/inventory_providers.dart';
import 'inventory_categories_page.dart';

class InventoryAddItemPage extends ConsumerStatefulWidget {
  const InventoryAddItemPage({super.key, this.item, this.copy = false});
  final InventoryItem? item;
  final bool copy;

  @override
  ConsumerState<InventoryAddItemPage> createState() =>
      _InventoryAddItemPageState();
}

class _InventoryAddItemPageState extends ConsumerState<InventoryAddItemPage> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final duration = TextEditingController();
  final category = TextEditingController();
  final purchasePrice = TextEditingController();
  final quantity = TextEditingController();
  final location = TextEditingController();
  final remark = TextEditingController();
  DateTime? productionDate;
  DateTime? expiryDate;
  String? expiryCalculationError;
  DateTime? purchaseDate;
  int? categoryId;
  String storageUnit = '天';
  bool saving = false;
  bool picking = false;
  final imagePaths = <String>[];
  final pickedPaths = <String>{};

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    if (item == null) return;
    name.text = item.name;
    duration.text = item.storageDuration;
    category.text = item.category;
    categoryId = item.categoryId;
    purchasePrice.text = item.purchasePrice;
    quantity.text = item.quantity;
    location.text = item.location;
    remark.text = item.remark;
    productionDate = item.productionDate;
    expiryDate = item.expiryDate;
    purchaseDate = item.purchaseDate;
    storageUnit = item.storageUnit;
    imagePaths.addAll(item.imagePaths);
  }

  @override
  void dispose() {
    name.dispose();
    duration.dispose();
    category.dispose();
    purchasePrice.dispose();
    quantity.dispose();
    location.dispose();
    remark.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDate(DateTime? current) => showDatePicker(
    context: context,
    initialDate: current ?? DateTime.now(),
    firstDate: DateTime(2000),
    lastDate: DateTime(2100, 12, 31),
  );

  void _calculateExpiry({bool notify = false}) {
    final value = int.tryParse(duration.text);
    if (productionDate == null ||
        value == null ||
        value <= 0 ||
        value > 36500) {
      if (notify) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先填写生产日期和 1–36500 的保存时长')),
        );
      }
      return;
    }
    final calculated = calculateInventoryExpiry(
      productionDate!,
      value,
      storageUnit,
    );
    if (calculated.year > 2100) {
      setState(() {
        expiryDate = null;
        expiryCalculationError = '计算结果超过 2100 年，请调整保存时长或手动选择到期日期';
      });
      if (notify) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('到期日期不能晚于 2100 年')));
      }
      return;
    }
    setState(() {
      expiryDate = calculated;
      expiryCalculationError = null;
    });
  }

  Future<void> _pickImages(ImageSource source) async {
    if (saving || picking || imagePaths.length >= 5) return;
    setState(() => picking = true);
    try {
      final available = 5 - imagePaths.length;
      final picker = ImagePicker();
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
    final selected = await Navigator.push<InventoryCategory>(
      context,
      MaterialPageRoute(
        builder: (_) => const InventoryCategoriesPage(selectMode: true),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        categoryId = selected.id;
        category.text = selected.id == null ? '' : selected.name;
      });
    }
  }

  Future<void> _save() async {
    if (saving || picking) return;
    final invalidFields = formKey.currentState!.validateGranularly();
    if (invalidFields.isNotEmpty) {
      await Scrollable.ensureVisible(
        invalidFields.first.context,
        duration: const Duration(milliseconds: 250),
        alignment: 0.2,
      );
      return;
    }
    if (expiryDate == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请选择到期日期，或使用自动计算')));
      return;
    }
    if (productionDate != null && expiryDate!.isBefore(productionDate!)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('到期日期不能早于生产日期')));
      return;
    }
    setState(() => saving = true);
    final copied = <String>[];
    var committed = false;
    try {
      final repository = await ref.read(inventoryRepositoryProvider.future);
      final categories = await repository.listCategories();
      final validCategory = categories.any((c) => c.id == categoryId)
          ? categoryId
          : null;
      final savedImages = <String>[];
      for (final path in imagePaths) {
        if (!pickedPaths.contains(path)) {
          savedImages.add(path);
          continue;
        }
        final dir = await getApplicationDocumentsDirectory();
        final photos = Directory(p.join(dir.path, 'inventory_photos'));
        await photos.create(recursive: true);
        final destination = p.join(
          photos.path,
          '${DateTime.now().microsecondsSinceEpoch}_${savedImages.length}${p.extension(path)}',
        );
        await File(path).copy(destination);
        copied.add(destination);
        savedImages.add(destination);
      }
      await repository.saveItem(
        InventoryItem(
          id: widget.copy ? null : widget.item?.id,
          name: name.text.trim(),
          expiryDate: expiryDate!,
          categoryId: validCategory,
          productionDate: productionDate,
          storageDuration: duration.text.trim(),
          storageUnit: storageUnit,
          location: location.text.trim(),
          quantity: quantity.text.trim(),
          purchaseDate: purchaseDate,
          purchasePrice: purchasePrice.text.trim(),
          remark: remark.text.trim(),
          imagePaths: savedImages,
        ),
      );
      committed = true;
      if (!mounted) return;
      refreshInventory(ref);
      Navigator.pop(context);
    } catch (_) {
      if (!committed) {
        for (final path in copied) {
          try {
            await File(path).delete();
          } catch (_) {}
        }
      }
      if (mounted) {
        setState(() => saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('保存失败，内容已保留，请重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(inventoryCategoriesProvider).valueOrNull;
    final current = categories?.where((c) => c.id == categoryId).firstOrNull;
    if (categories != null) category.text = current?.name ?? '';
    return PopScope(
      canPop: !saving,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          title: Text(
            widget.copy
                ? '复制物品'
                : widget.item == null
                ? '记录物品'
                : '编辑物品',
          ),
          centerTitle: true,
        ),
        bottomNavigationBar: _saveBar(),
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
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 16),
                    child: Text(
                      '填好名称和到期日期，就能记录一件物品',
                      style: TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                  ),
                  _section('基本信息', [
                    _input('名称', name, hint: '例如：牛奶', required: true),
                    TextFormField(
                      controller: category,
                      readOnly: true,
                      onTap: _chooseCategory,
                      decoration: _decoration(
                        '分类',
                        hint: '未分类 · 点击选择',
                      ).copyWith(suffixIcon: const Icon(Icons.chevron_right)),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  _section(
                    '保质期',
                    [
                      _dateField('生产日期', productionDate, (date) {
                        setState(() => productionDate = date);
                        _calculateExpiry();
                      }),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: _input(
                              '保存时长',
                              duration,
                              hint: '输入保存时长',
                              keyboard: TextInputType.number,
                              formatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(5),
                              ],
                              onChanged: (_) => _calculateExpiry(),
                              validator: (v) =>
                                  v != null &&
                                      v.isNotEmpty &&
                                      ((int.tryParse(v) ?? 0) <= 0 ||
                                          int.parse(v) > 36500)
                                  ? '请输入 1–36500 的整数'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: storageUnit,
                              isExpanded: true,
                              decoration: _decoration('单位'),
                              items: ['天', '周', '月', '年']
                                  .map(
                                    (unit) => DropdownMenuItem(
                                      value: unit,
                                      child: Text(unit),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (unit) {
                                setState(() => storageUnit = unit!);
                                _calculateExpiry();
                              },
                            ),
                          ),
                        ],
                      ),
                      _dateField(
                        '到期日期',
                        expiryDate,
                        (date) => setState(() {
                          expiryDate = date;
                          expiryCalculationError = null;
                        }),
                        required: true,
                      ),
                      if (expiryCalculationError != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            expiryCalculationError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                    action: TextButton.icon(
                      onPressed: () => _calculateExpiry(notify: true),
                      icon: const Icon(Icons.calculate_outlined, size: 18),
                      label: const Text('自动计算'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _section('补充信息', [
                    _dateField(
                      '购买日期',
                      purchaseDate,
                      (date) => setState(() => purchaseDate = date),
                    ),
                    _input('存放位置', location, hint: '例如：厨房、储物柜'),
                    _input(
                      '购买金额',
                      purchasePrice,
                      hint: '选填',
                      keyboard: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      formatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      suffix: '元',
                      validator: (value) =>
                          value == null ||
                              value.isEmpty ||
                              RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)
                          ? null
                          : '请输入有效金额（最多两位小数）',
                    ),
                    _input('数量', quantity, hint: '例如：2 瓶'),
                    _input('备注', remark, hint: '补充说明', maxLines: 3),
                  ], caption: '选填'),
                  const SizedBox(height: 16),
                  _section('物品图片', [
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
                                  errorBuilder: (_, _, _) => const SizedBox(
                                    width: 88,
                                    height: 88,
                                    child: Icon(Icons.broken_image_outlined),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: IconButton.filledTonal(
                                  tooltip: '移除图片',
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
                          onPressed: picking || imagePaths.length >= 5
                              ? null
                              : () => _pickImages(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('拍照'),
                        ),
                        OutlinedButton.icon(
                          onPressed: picking || imagePaths.length >= 5
                              ? null
                              : () => _pickImages(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('选择图片'),
                        ),
                      ],
                    ),
                  ], caption: '${imagePaths.length}/5 · 选填'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _saveBar() => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: AppColors.border)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: FilledButton.icon(
          onPressed: saving || picking ? null : _save,
          icon: saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded, size: 20),
          label: Text(saving ? '保存中…' : '保存物品'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _section(
    String title,
    List<Widget> fields, {
    String? caption,
    Widget? action,
  }) => Card(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (caption != null)
                Text(
                  caption,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ?action,
            ],
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < fields.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            fields[i],
          ],
        ],
      ),
    ),
  );

  InputDecoration _decoration(String label, {String? hint, String? suffix}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: suffix,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
        hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
        filled: true,
        fillColor: const Color(0xFFF5F7F4),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorMaxLines: 3,
      );

  Widget _input(
    String label,
    TextEditingController controller, {
    String? hint,
    String? suffix,
    bool required = false,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
    FormFieldValidator<String>? validator,
  }) => TextFormField(
    controller: controller,
    keyboardType: keyboard,
    inputFormatters: formatters,
    maxLines: maxLines,
    textInputAction: maxLines == 1
        ? TextInputAction.next
        : TextInputAction.newline,
    onChanged: onChanged,
    decoration: _decoration(
      required ? '$label *' : label,
      hint: hint,
      suffix: suffix,
    ),
    validator:
        validator ??
        (required
            ? (value) =>
                  value == null || value.trim().isEmpty ? '请输入$label' : null
            : null),
  );

  Widget _dateField(
    String label,
    DateTime? date,
    ValueChanged<DateTime> onChanged, {
    bool required = false,
  }) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: () async {
      final value = await _pickDate(date);
      if (value != null) onChanged(value);
    },
    child: InputDecorator(
      decoration: _decoration(required ? '$label *' : label).copyWith(
        fillColor: required ? AppColors.soft : const Color(0xFFF5F7F4),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              date == null ? '请选择$label' : _formatDate(date),
              style: TextStyle(
                color: date == null ? AppColors.muted : AppColors.text,
                fontSize: 14,
                fontWeight: required && date != null
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.calendar_today_outlined,
            size: 18,
            color: AppColors.muted,
          ),
        ],
      ),
    ),
  );

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
