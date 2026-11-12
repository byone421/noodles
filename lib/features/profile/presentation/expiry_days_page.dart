import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/inventory_settings.dart';
import '../../../providers/inventory_providers.dart';

class ExpiryDaysPage extends ConsumerWidget {
  const ExpiryDaysPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('过期天数设置'), centerTitle: true),
    body: ref
        .watch(expirySettingsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: TextButton(
              onPressed: () => ref.invalidate(expirySettingsProvider),
              child: const Text('设置加载失败，点击重试'),
            ),
          ),
          data: (settings) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                '提醒区间',
                style: TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < 3; i++)
                Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppColors.border),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: Icon(
                      Icons.circle,
                      size: 12,
                      color: [
                        AppColors.accent,
                        const Color(0xFF557DB5),
                        const Color(0xFF4F9475),
                      ][i],
                    ),
                    title: Text(
                      ['近期提醒', '中期提醒', '长期提醒'][i],
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${settings.days[i]}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 26,
                            color: [
                              AppColors.accent,
                              const Color(0xFF557DB5),
                              const Color(0xFF4F9475),
                            ][i],
                          ),
                        ),
                        const Text(
                          ' 天',
                          style: TextStyle(color: AppColors.muted),
                        ),
                        const Icon(Icons.chevron_right, color: AppColors.muted),
                      ],
                    ),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => _DaysEditor(settings: settings, index: i),
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              const Text(
                '控制万物顶部的到期统计与筛选。各区间累计统计，包含今天和第 N 天，不包含已过期物品。',
                style: TextStyle(color: AppColors.muted, height: 1.6),
              ),
            ],
          ),
        ),
  );
}

class _DaysEditor extends ConsumerStatefulWidget {
  const _DaysEditor({required this.settings, required this.index});
  final ExpirySettings settings;
  final int index;
  @override
  ConsumerState<_DaysEditor> createState() => _DaysEditorState();
}

class _DaysEditorState extends ConsumerState<_DaysEditor> {
  late final controller = TextEditingController(
    text: '${widget.settings.days[widget.index]}',
  );
  String? error;
  bool saving = false;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final days = widget.settings.days;
    days[widget.index] = int.tryParse(controller.text) ?? 0;
    final settings = ExpirySettings(
      near: days[0],
      middle: days[1],
      far: days[2],
    );
    if (!settings.isValid) {
      setState(() => error = '请输入 1–36500 的整数，且近期 < 中期 < 长期');
      return;
    }
    setState(() => saving = true);
    try {
      await (await ref.read(inventoryRepositoryProvider.future))
          .saveExpirySettings(settings);
      if (!mounted) return;
      ref.invalidate(expirySettingsProvider);
      Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = '保存失败，请重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: Text(['近期提醒', '中期提醒', '长期提醒'][widget.index]),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(5),
        ],
        decoration: InputDecoration(
          labelText: '到期天数',
          suffixText: '天',
          errorText: error,
          errorMaxLines: 3,
        ),
        onSubmitted: (_) {
          if (!saving) _save();
        },
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
