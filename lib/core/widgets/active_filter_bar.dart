import 'package:flutter/material.dart';

class ActiveFilterBar extends StatelessWidget {
  const ActiveFilterBar({
    super.key,
    required this.filters,
    required this.onClear,
  });

  final List<({String label, String clearTooltip, VoidCallback onClear})>
  filters;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (filters.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final filter in filters)
            InputChip(
              label: Text(
                filter.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              tooltip: filter.label,
              onDeleted: filter.onClear,
              deleteButtonTooltipMessage: filter.clearTooltip,
            ),
          Tooltip(
            message: '清除筛选',
            child: TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
              label: const Text('清除筛选'),
            ),
          ),
        ],
      ),
    );
  }
}
