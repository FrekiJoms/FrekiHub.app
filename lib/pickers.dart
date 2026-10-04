part of 'screens.dart';

Future<DateTime?> showWheelDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) => panel<DateTime>(
  context,
  _WheelPickerSheet(
    initial:
        DateUtils.dateOnly(initialDate).isBefore(DateUtils.dateOnly(firstDate))
        ? DateUtils.dateOnly(firstDate)
        : DateUtils.dateOnly(initialDate).isAfter(DateUtils.dateOnly(lastDate))
        ? DateUtils.dateOnly(lastDate)
        : DateUtils.dateOnly(initialDate),
    first: DateUtils.dateOnly(firstDate),
    last: DateUtils.dateOnly(lastDate),
  ),
);

Future<TimeOfDay?> showWheelTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) async {
  final value = await panel<DateTime>(
    context,
    _WheelPickerSheet(
      initial: DateTime(2026, 1, 1, initialTime.hour, initialTime.minute),
      timeOnly: true,
    ),
  );
  return value == null ? null : TimeOfDay.fromDateTime(value);
}

class _WheelPickerSheet extends StatefulWidget {
  final DateTime initial;
  final DateTime? first, last;
  final bool timeOnly;
  const _WheelPickerSheet({
    required this.initial,
    this.first,
    this.last,
    this.timeOnly = false,
  });
  @override
  State<_WheelPickerSheet> createState() => _WheelPickerSheetState();
}

class _WheelPickerSheetState extends State<_WheelPickerSheet> {
  late DateTime value = widget.initial;
  final pickerKey = GlobalKey();
  bool autoScrolling = false;

  Future<void> jumpToNow() async {
    if (autoScrolling) return;
    final now = DateTime.now();
    var target = widget.timeOnly
        ? DateTime(value.year, value.month, value.day, now.hour, now.minute)
        : DateUtils.dateOnly(now);
    if (!widget.timeOnly) {
      if (target.isBefore(widget.first!)) target = widget.first!;
      if (target.isAfter(widget.last!)) target = widget.last!;
    }
    // Keep CupertinoDatePicker's native wheels, labels and selection styling.
    // Its descendant CupertinoPicker widgets expose their public controllers.
    final controllers = <FixedExtentScrollController>[];
    void collect(Element element) {
      final child = element.widget;
      if (child is CupertinoPicker && child.scrollController != null) {
        controllers.add(child.scrollController!);
      }
      element.visitChildElements(collect);
    }

    pickerKey.currentContext?.visitChildElements(collect);
    if (controllers.length != 3) return;
    setState(() => autoScrolling = true);
    final positions = widget.timeOnly
        ? [target.hour, target.minute, target.hour >= 12 ? 1 : 0]
        : [target.month - 1, target.day - 1, target.year];
    final duration = Motion.duration(context, 450);
    await Future.wait([
      for (var i = 0; i < controllers.length; i++)
        if (controllers[i].hasClients)
          duration == Duration.zero
              ? Future<void>.sync(() => controllers[i].jumpToItem(positions[i]))
              : controllers[i].animateToItem(
                  positions[i],
                  duration: duration,
                  curve: Motion.curve,
                ),
    ]);
    if (!mounted) return;
    setState(() {
      value = target;
      autoScrolling = false;
    });
  }

  @override
  Widget build(BuildContext c) {
    final colors = Theme.of(c).colorScheme;
    final rowHeight = math.max(40.0, MediaQuery.textScalerOf(c).scale(22) + 12);
    return PanelContent(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
      header: Row(
        children: [
          TextButton(
            onPressed: withFeedback(() => Navigator.pop(c)),
            child: const Text('Cancel'),
          ),
          Expanded(
            child: Semantics(
              header: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.timeOnly ? 'Select time' : 'Select date',
                    textAlign: TextAlign.center,
                    style: Theme.of(c).textTheme.titleMedium,
                  ),
                  IconButton(
                    tooltip: widget.timeOnly
                        ? 'Jump to current time'
                        : 'Jump to today',
                    onPressed: autoScrolling ? null : withFeedback(jumpToNow),
                    icon: SvgPicture.asset(
                      'assets/icons/rotate-ccw.svg',
                      width: 20,
                      height: 20,
                      colorFilter: ColorFilter.mode(
                        colors.onSurface,
                        BlendMode.srcIn,
                      ),
                      excludeFromSemantics: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          TextButton(
            onPressed: autoScrolling
                ? null
                : withFeedback(() => Navigator.pop(c, value)),
            child: const Text('Confirm'),
          ),
        ],
      ),
      child: SizedBox(
        height: rowHeight * 5,
        child: CupertinoTheme(
          data: CupertinoThemeData(
            brightness: Theme.of(c).brightness,
            primaryColor: colors.primary,
            textTheme: CupertinoTextThemeData(
              dateTimePickerTextStyle: TextStyle(
                fontFamily: 'Geist',
                fontSize: 20,
                color: colors.onSurface,
              ),
            ),
          ),
          child: AbsorbPointer(
            absorbing: autoScrolling,
            child: CupertinoDatePicker(
              key: pickerKey,
              mode: widget.timeOnly
                  ? CupertinoDatePickerMode.time
                  : CupertinoDatePickerMode.date,
              initialDateTime: widget.initial,
              minimumDate: widget.first,
              maximumDate: widget.last,
              minimumYear: widget.first?.year ?? 1,
              maximumYear: widget.last?.year,
              dateOrder: DatePickerDateOrder.mdy,
              use24hFormat: false,
              itemExtent: rowHeight,
              backgroundColor: colors.surface,
              selectionOverlayBuilder:
                  (context, {required selectedIndex, required columnCount}) =>
                      Container(
                        decoration: BoxDecoration(
                          color: colors.onSurface.withValues(alpha: .035),
                          border: Border.symmetric(
                            horizontal: BorderSide(
                              color: colors.outlineVariant.withValues(
                                alpha: .6,
                              ),
                            ),
                          ),
                        ),
                      ),
              onDateTimeChanged: (date) {
                if (autoScrolling || date == value) return;
                value = date;
                ActionFeedback.tap();
              },
            ),
          ),
        ),
      ),
    );
  }
}
