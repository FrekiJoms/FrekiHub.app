part of 'screens.dart';

class _SelectionField extends StatefulWidget {
  final String label, value;
  final List<String> values;
  final ValueChanged<String> changed;
  const _SelectionField({
    required this.label,
    required this.value,
    required this.values,
    required this.changed,
  });
  @override
  State<_SelectionField> createState() => _SelectionFieldState();
}

class _SelectionFieldState extends State<_SelectionField> {
  bool open = false;
  Future<void> choose() async {
    if (open || widget.values.isEmpty) return;
    ActionFeedback.tap();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => open = true);
    final result = await panel<String>(
      context,
      _ChoiceSheet(
        title: widget.label,
        selected: widget.value,
        values: widget.values,
      ),
    );
    if (!mounted) return;
    setState(() => open = false);
    if (result != null &&
        widget.values.contains(result) &&
        result != widget.value) {
      widget.changed(result);
    }
  }

  @override
  Widget build(BuildContext c) {
    final colors = Theme.of(c).colorScheme;
    final value = widget.values.contains(widget.value)
        ? widget.value
        : widget.values.firstOrNull ?? 'No options';
    return Semantics(
      button: true,
      label: widget.label,
      value: value,
      enabled: widget.values.isNotEmpty,
      onTap: widget.values.isEmpty ? null : choose,
      child: ExcludeSemantics(
        child: TextButton(
          onPressed: widget.values.isEmpty ? null : choose,
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(Size(48, 64)),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerLow),
            foregroundColor: WidgetStatePropertyAll(colors.onSurface),
            alignment: Alignment.centerLeft,
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            side: WidgetStateProperty.resolveWith(
              (states) => BorderSide(
                color: open || states.contains(WidgetState.focused)
                    ? colors.primary.withValues(alpha: .55)
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedRotation(
                turns: open ? .5 : 0,
                duration: Motion.duration(c, 180),
                child: Icon(
                  LucideIcons.chevronDown,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceSheet extends StatefulWidget {
  final String title;
  final String? selected;
  final List<String> values;
  const _ChoiceSheet({
    required this.title,
    required this.values,
    this.selected,
  });
  @override
  State<_ChoiceSheet> createState() => _ChoiceSheetState();
}

class _ChoiceSheetState extends State<_ChoiceSheet> {
  String query = '';
  @override
  Widget build(BuildContext c) {
    final colors = Theme.of(c).colorScheme;
    final values = widget.values
        .where((v) => v.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.max(
              120,
              (MediaQuery.sizeOf(c).height -
                      MediaQuery.viewInsetsOf(c).bottom) *
                  .7,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        widget.title,
                        style: Theme.of(c).textTheme.titleLarge,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close selection',
                    onPressed: withFeedback(() => Navigator.pop(c)),
                    icon: const Icon(LucideIcons.x, size: 18),
                  ),
                ],
              ),
              if (widget.values.length > 8)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 12),
                  child: TextField(
                    onChanged: (v) => setState(() => query = v.trim()),
                    decoration: const InputDecoration(
                      hintText: 'Find an option',
                      prefixIcon: Icon(LucideIcons.search, size: 18),
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Flexible(
                child: values.isEmpty
                    ? ListView(
                        children: const [
                          Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No matching options',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: values.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 4),
                        itemBuilder: (c, i) {
                          final selected = values[i] == widget.selected;
                          return Semantics(
                            selected: selected,
                            child: Material(
                              color: selected
                                  ? colors.primaryContainer
                                  : colors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(14),
                              clipBehavior: Clip.antiAlias,
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                title: Text(
                                  values[i],
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: selected
                                        ? colors.onPrimaryContainer
                                        : colors.onSurface,
                                  ),
                                ),
                                trailing: selected
                                    ? Icon(
                                        LucideIcons.check,
                                        size: 18,
                                        color: colors.onPrimaryContainer,
                                      )
                                    : null,
                                onTap: withFeedback(
                                  () => Navigator.pop(c, values[i]),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
