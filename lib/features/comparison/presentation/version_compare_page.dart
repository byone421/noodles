import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/database/recipe_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/recipe.dart';

class VersionComparePage extends StatefulWidget {
  const VersionComparePage({super.key, required this.repository, required this.versions});
  final RecipeRepository repository;
  final List<RecipeVersion> versions;
  @override State<VersionComparePage> createState() => _VersionComparePageState();
}

class _VersionComparePageState extends State<VersionComparePage> {
  late String left;
  late String right;
  late Future<List<VersionBundle?>> comparison;

  @override
  void initState() {
    super.initState();
    left = widget.versions.first.id;
    right = widget.versions.length > 1 ? widget.versions[1].id : left;
    comparison = _loadComparison();
  }

  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('版本对比')), body: ListView(padding: const EdgeInsets.all(20), children: [
    _selector(left, (v) => setState(() { left = v!; comparison = _loadComparison(); })), const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Icon(Icons.compare_arrows)), _selector(right, (v) => setState(() { right = v!; comparison = _loadComparison(); })), const SizedBox(height: 18),
    FutureBuilder(future: comparison, builder: (_, snapshot) { if (snapshot.hasError) return Text('对比加载失败：${snapshot.error}'); if (!snapshot.hasData) return const Center(child: CircularProgressIndicator()); final a = snapshot.data![0], b = snapshot.data![1]; if (a == null || b == null) return const Text('所选版本不存在'); return Column(children: [_diffSection('版本名称', '${a.version.title} → ${b.version.title}', Icons.label_outline), _diffSection('评分变化', '${a.version.rating?.toStringAsFixed(1) ?? '未评分'} → ${b.version.rating?.toStringAsFixed(1) ?? '未评分'}', Icons.star_outline), ..._ingredientDiff(a, b), ..._stepDiff(a, b), _sideBySide('版本说明', a.version.note, b.version.note), _photoComparison(a, b), _sideBySide('成品反馈', a.finishedRecord?.note ?? '', b.finishedRecord?.note ?? ''), _sideBySide('下次改进', a.finishedRecord?.nextImprovement ?? '', b.finishedRecord?.nextImprovement ?? '')]); }),
  ]));

  Widget _selector(String value, ValueChanged<String?> changed) => DropdownButtonFormField<String>(value: value, decoration: const InputDecoration(labelText: '选择版本'), items: widget.versions.map((v) => DropdownMenuItem(value: v.id, child: Text('版本 ${v.versionNumber}'))).toList(), onChanged: changed);
  Future<List<VersionBundle?>> _loadComparison() => Future.wait([widget.repository.bundle(left), widget.repository.bundle(right)]);
  Widget _diffSection(String title, String text, IconData icon) => Card(elevation: 0, child: ListTile(leading: Icon(icon, color: AppColors.accent), title: Text(title), subtitle: Text(text, style: const TextStyle(fontWeight: FontWeight.w700))));
  Widget _sideBySide(String title, String a, String b) => Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), const Divider(), Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: _value('左侧', a)), const VerticalDivider(), Expanded(child: _value('右侧', b))])])));
  Widget _value(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700)), const SizedBox(height: 4), Text(value.isEmpty ? '无记录' : value)]);
  Widget _photoComparison(VersionBundle a, VersionBundle b) => Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('成品照片', style: TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 8), Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: _photo(a.finishedRecord?.imagePath)), const SizedBox(width: 8), Expanded(child: _photo(b.finishedRecord?.imagePath))])])));
  Widget _photo(String? path) => path != null && File(path).existsSync() ? Image.file(File(path), fit: BoxFit.contain) : const AspectRatio(aspectRatio: 1, child: Center(child: Text('暂无照片', style: TextStyle(color: AppColors.muted))));

  List<Widget> _ingredientDiff(VersionBundle a, VersionBundle b) {
    final before = {for (final i in a.ingredients) i.name: '${i.amount}${i.unit}'};
    final after = {for (final i in b.ingredients) i.name: '${i.amount}${i.unit}'};
    final rows = <Widget>[];
    for (final name in {...before.keys, ...after.keys}) {
      if (!before.containsKey(name)) rows.add(_diffSection('新增材料', '$name ${after[name]}', Icons.add_circle_outline));
      else if (!after.containsKey(name)) rows.add(_diffSection('删除材料', '$name ${before[name]}', Icons.remove_circle_outline));
      else if (before[name] != after[name]) rows.add(_diffSection('修改用量', '$name ${before[name]} → ${after[name]}', Icons.change_circle_outlined));
    }
    return rows.isEmpty ? [_diffSection('材料变化', '无变化', Icons.check_circle_outline)] : rows;
  }

  List<Widget> _stepDiff(VersionBundle a, VersionBundle b) {
    final rows = <Widget>[];
    final beforeSteps = a.steps.map((s) => s.content).toList();
    final afterSteps = b.steps.map((s) => s.content).toList();
    if (beforeSteps.length == afterSteps.length && beforeSteps.toSet().containsAll(afterSteps) && !_sameOrder(beforeSteps, afterSteps)) {
      return [_diffSection('步骤顺序变化', '步骤内容相同，但排列顺序已调整', Icons.swap_vert)];
    }
    final length = a.steps.length > b.steps.length ? a.steps.length : b.steps.length;
    for (var i = 0; i < length; i++) {
      final before = i < a.steps.length ? a.steps[i].content : null;
      final after = i < b.steps.length ? b.steps[i].content : null;
      if (before == null) rows.add(_diffSection('新增步骤 ${i + 1}', after!, Icons.add_circle_outline));
      else if (after == null) rows.add(_diffSection('删除步骤 ${i + 1}', before, Icons.remove_circle_outline));
      else if (before != after) rows.add(_diffSection('步骤修改 ${i + 1}', '$before → $after', Icons.change_circle_outlined));
    }
    return rows.isEmpty ? [_diffSection('步骤变化', '无变化', Icons.check_circle_outline)] : rows;
  }
  bool _sameOrder(List<String> a, List<String> b) { for (var i = 0; i < a.length; i++) { if (a[i] != b[i]) return false; } return true; }
}
