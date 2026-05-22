import 'package:flutter/material.dart';

/// One row in the model picker list.
typedef ModelChoice = ({String providerId, String modelId, String label});

/// Searchable bottom-sheet model picker.
///
/// Why a bottom sheet instead of the default `DropdownButtonFormField`?
/// On a phone the menu shows the full list with no search, which gets unusable
/// past ~15 entries. OpenCode users typically expose 50+ models across
/// providers, so we need a filter and a comfortable touch target.
///
/// Returns the selected [ModelChoice], or `null` if the user dismissed the
/// sheet.
Future<ModelChoice?> showModelPicker(
  BuildContext context, {
  required List<ModelChoice> models,
  ModelChoice? selected,
}) {
  return showModalBottomSheet<ModelChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _ModelPickerSheet(models: models, selected: selected),
  );
}

class _ModelPickerSheet extends StatefulWidget {
  const _ModelPickerSheet({required this.models, required this.selected});
  final List<ModelChoice> models;
  final ModelChoice? selected;

  @override
  State<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<_ModelPickerSheet> {
  final _query = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Don't auto-focus on open: keyboard popping immediately makes the sheet
    // jump and is jarring. The user taps the field when they want to search.
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Lowercased token list for fuzzy contains-match.
  List<ModelChoice> _filtered() {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return widget.models;
    return widget.models.where((m) {
      final hay = '${m.providerId} ${m.modelId} ${m.label}'.toLowerCase();
      return hay.contains(q);
    }).toList(growable: false);
  }

  /// Group by providerId so the user can scan visually.
  Map<String, List<ModelChoice>> _grouped(List<ModelChoice> source) {
    final groups = <String, List<ModelChoice>>{};
    for (final m in source) {
      groups.putIfAbsent(m.providerId, () => <ModelChoice>[]).add(m);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filtered();
    final groups = _grouped(filtered);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Choose model',
                style: theme.textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _query,
                focusNode: _focus,
                autofocus: false,
                decoration: InputDecoration(
                  hintText: 'Search providers / models',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _query.clear();
                            setState(() {});
                          },
                        ),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No model matches "${_query.text}".',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else
              Flexible(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    for (final entry in groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                        child: Text(
                          entry.key,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      for (final m in entry.value)
                        _ModelRow(
                          choice: m,
                          isSelected: widget.selected != null &&
                              widget.selected!.providerId == m.providerId &&
                              widget.selected!.modelId == m.modelId,
                          onTap: () => Navigator.of(context).pop(m),
                        ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.choice,
    required this.isSelected,
    required this.onTap,
  });

  final ModelChoice choice;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      title: Text(
        choice.modelId,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'monospace',
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface,
        ),
      ),
      subtitle: choice.label.trim().isEmpty || choice.label == choice.modelId
          ? null
          : Text(
              choice.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: isSelected
          ? Icon(Icons.check, color: theme.colorScheme.primary, size: 18)
          : null,
      onTap: onTap,
    );
  }
}
