import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/inventory_transfer_service.dart';
import '../../../core/database/recipe_export_service.dart';
import '../../../core/database/recipe_import_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/inventory_transfer.dart';
import '../../../models/recipe_transfer.dart';
import '../../../providers/inventory_providers.dart';
import '../../../providers/recipe_providers.dart';

class DataTransferPage extends ConsumerStatefulWidget {
  const DataTransferPage({
    super.key,
    required this.importing,
    this.recipes = false,
  });
  final bool importing;
  final bool recipes;
  @override
  ConsumerState<DataTransferPage> createState() => _DataTransferPageState();
}

class _DataTransferPageState extends ConsumerState<DataTransferPage> {
  InventoryTransferData? data;
  RecipeTransferData? recipeData;
  String? filename, result;
  final photos = <String, String>{};
  final staged = <String>{};
  bool busy = false;

  @override
  void dispose() {
    if (staged.isNotEmpty) InventoryTransferService.cleanStaged(staged);
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      result = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(
          () => result = switch (error) {
            FormatException e => e.message,
            PlatformException e => e.message ?? '文件选择或读写失败，请重试',
            MissingPluginException _ => '此功能目前支持 Android，请在手机安装新版后使用。',
            FileSystemException e => '文件读写失败：${e.message}',
            _ => '操作失败，现有数据已保留，请重试。',
          },
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _selectFile() => _run(() async {
    final selected = await InventoryTransferService.pickFile();
    if (selected == null) return;
    if (mounted) {
      setState(() {
        data = null;
        recipeData = null;
        filename = null;
        photos.clear();
      });
    }
    final path = selected['path']!;
    staged.add(path);
    final parsedRecipes = widget.recipes
        ? await RecipeImportService.read(path)
        : null;
    final parsed = widget.recipes
        ? null
        : await InventoryTransferService.read(path);
    if (!mounted) return;
    setState(() {
      data = parsed;
      recipeData = parsedRecipes;
      filename = selected['name'];
      photos.clear();
    });
  });

  Future<void> _selectPhotos() => _run(() async {
    final selected = await InventoryTransferService.pickImageFolder();
    if (selected == null) return;
    staged.addAll(selected.values);
    if (!mounted) return;
    setState(() {
      photos.clear();
      photos.addAll(selected);
    });
  });

  Future<void> _import() async {
    if (widget.recipes) return _importRecipes();
    final source = data;
    if (source == null || busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认合并导入？'),
        content: Text(
          '将处理 ${source.items.length} 件物品、${source.categories.length} 个分类。'
          '\n现有物品和菜谱会保留；同名分类合并，字段完全相同的物品跳过。'
          '\n导入分类时，同名分类的说明和排序会更新为导入内容。'
          '${source.items.any((item) => item.imagePaths.isNotEmpty) && source.images.isEmpty && photos.isEmpty ? '\n尚未选择旧图片文件夹，本次只导入文字，之后可选择同一 CSV 和图片文件夹补导。' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('合并导入'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      final repo = await ref.read(inventoryRepositoryProvider.future);
      final summary = await InventoryTransferService(repo.db)
          .importData(source, photos: photos);
      if (!mounted) return;
      refreshInventory(ref);
      setState(() => result = '导入完成\n$summary');
    });
  }

  Future<void> _importRecipes() async {
    final source = recipeData;
    if (source == null || busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认合并导入菜谱？'),
        content: Text(
          '将处理 ${source.recipeCount} 道菜谱、${source.versionCount} 个烹饪版本、${source.categoryCount} 个分类。'
          '\n现有数据会保留；ID 已存在的菜谱及其版本会整道跳过，不覆盖本地修改。'
          '\n同名分类合并，排序更新为备份中的内容。图片会自动恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('合并导入'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      final repo = await ref.read(repositoryProvider.future);
      final summary = await RecipeImportService(repo.db).importData(source);
      if (!mounted) return;
      ref.invalidate(recipesProvider);
      ref.invalidate(recipeProvider);
      ref.invalidate(versionsProvider);
      ref.invalidate(bundleProvider);
      ref.invalidate(statsProvider);
      ref.invalidate(recipeCategoryOrdersProvider);
      ref.invalidate(recipeCategoriesProvider);
      setState(() => result = '导入完成\n$summary');
    });
  }

  Future<void> _export() => _run(() async {
    final bool saved;
    if (widget.recipes) {
      final repo = await ref.read(repositoryProvider.future);
      saved = await RecipeExportService(repo.db).exportData();
    } else {
      final repo = await ref.read(inventoryRepositoryProvider.future);
      saved = await InventoryTransferService(repo.db).exportData();
    }
    if (mounted) {
      setState(() => result = saved ? '导出成功，备份已保存到你选择的位置。' : '已取消保存');
    }
  });

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.recipes
              ? widget.importing
                    ? '导入菜谱数据'
                    : '导出菜谱数据'
              : widget.importing
              ? '导入数据'
              : '导出数据',
        ),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _card(
            widget.recipes
                ? widget.importing
                      ? '恢复菜谱数据'
                      : '备份菜谱数据'
                : widget.importing
                ? '从老项目迁移万物数据'
                : '备份万物数据',
            [
              Text(
                widget.recipes
                    ? widget.importing
                          ? '选择“导出菜谱数据”生成的 JSON 文件，可一起恢复菜谱分类、菜谱、全部烹饪版本、食材、步骤、评分、成品反馈、下次改进和图片。'
                          : '备份包含菜谱、菜谱分类、全部烹饪版本、食材、步骤、评分、成品反馈、下次改进和图片，保存为一个 JSON 文件，可通过“导入菜谱数据”恢复。'
                    : widget.importing
                    ? '1. 在老项目“我的 → 导出”分别导出分类和物品。\n'
                          '2. 在这里先选择“导出分类_….csv”并导入，再选择“导出物品_….csv”。\n'
                          '3. 有图片时，选择与物品 CSV 同名的图片文件夹，然后导入。'
                    : '备份包含万物的分类、物品全部字段和图片，保存为一个 JSON 文件，可在此应用中重新导入。',
                style: const TextStyle(color: AppColors.muted, height: 1.8),
              ),
              const SizedBox(height: 12),
              Text(
                widget.recipes
                    ? '图片已包含在 JSON 中，无需单独选择。单张图片最多 20 MB，图片合计最多 65 MB，JSON 最多 100 MB。\n菜谱与万物备份请使用各自的导入入口。'
                    : '本页处理万物数据；菜谱、烹饪版本和提醒天数不包含在此备份中。',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.importing) ...[
            _card('选择导入内容', [
              OutlinedButton.icon(
                onPressed: busy ? null : _selectFile,
                icon: const Icon(Icons.description_outlined),
                label: Text(
                  widget.recipes ? '选择菜谱备份 JSON' : '选择 CSV 或万物备份 JSON',
                ),
              ),
              if (filename != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    filename!,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              if (recipeData != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${recipeData!.recipeCount} 道菜谱 · ${recipeData!.versionCount} 个版本 · ${recipeData!.categoryCount} 个分类 · ${recipeData!.images.length} 张图片',
                  style: const TextStyle(color: AppColors.primary),
                ),
              ],
              if (data != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${data!.items.length} 件物品 · ${data!.categories.length} 个分类',
                  style: const TextStyle(color: AppColors.primary),
                ),
                for (final warning in data!.warnings)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      warning,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (data!.legacy &&
                    data!.items.any((item) => item.imagePaths.isNotEmpty)) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: busy ? null : _selectPhotos,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('选择旧导出的图片文件夹'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '已选择 ${photos.values.toSet().length} 张图片',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  const Text(
                    '请选择 CSV 旁的同名文件夹，无需选择旧应用的私有目录。',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '若旧备份中有同名但不同来源的图片，为避免配错会跳过这些图片并计入未找到数量。使用更新后的老项目重新导出，可保留准确的图片对应关系。',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ],
            ]),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed:
                  busy || (widget.recipes ? recipeData == null : data == null)
                  ? null
                  : _import,
              icon: const Icon(Icons.download_outlined),
              label: const Text('合并导入'),
            ),
          ] else
            FilledButton.icon(
              onPressed: busy ? null : _export,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('导出并选择保存位置'),
            ),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: LinearProgressIndicator(),
            ),
          if (result != null)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: SelectableText(
                result!,
                style: const TextStyle(height: 1.7),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _card(String title, List<Widget> children) => Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: AppColors.border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
}
