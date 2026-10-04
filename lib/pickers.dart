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
  late final wheels = [
    for (final index in indices(value))
      FixedExtentScrollController(initialItem: index),
  ];
  bool autoScrolling = false;
  int scrollGeneration = 0;

  List<int> indices(DateTime date) => widget.timeOnly
      ? [(date.hour + 11) % 12, date.minute, date.hour >= 12 ? 1 : 0]
      : [date.month - 1, date.day - 1, date.year - widget.first!.year];

  DateTime bounded(DateTime date) {
    if (widget.timeOnly) return date;
    if (date.isBefore(widget.first!)) return widget.first!;
    if (date.isAfter(widget.last!)) return widget.last!;
    return date;
  }

  void setTime(int hour, int minute) {
    if (autoScrolling) return;
    final next = DateTime(value.year, value.month, value.day, hour, minute);
    if (next != value) {
      setState(() => value = next);
      ActionFeedback.tap();
    }
  }

  void setDate(int year, int month, int day) {
    if (autoScrolling) return;
    final next = bounded(
      DateTime(
        year,
        month,
        math.min(day, DateUtils.getDaysInMonth(year, month)),
      ),
    );
    if (next != value) {
      setState(() => value = next);
      ActionFeedback.tap();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || autoScrolling) return;
      final target = indices(value);
      for (var i = 0; i < wheels.length; i++) {
        if (wheels[i].hasClients && wheels[i].selectedItem != target[i]) {
          wheels[i].jumpToItem(target[i]);
        }
      }
    });
  }

  Future<void> jumpToNow() async {
    final now = DateTime.now();
    final target = bounded(
      widget.timeOnly
          ? DateTime(value.year, value.month, value.day, now.hour, now.minute)
          : DateUtils.dateOnly(now),
    );
    final generation = ++scrollGeneration;
    setState(() {
      value = target;
      autoScrolling = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || generation != scrollGeneration) return;
    final positions = indices(target);
    final duration = Motion.duration(context, 450);
    await Future.wait([
      for (var i = 0; i < wheels.length; i++)
        if (wheels[i].hasClients)
          duration == Duration.zero
              ? Future<void>.sync(() => wheels[i].jumpToItem(positions[i]))
              : wheels[i].animateToItem(
                  positions[i],
                  duration: duration,
                  curve: Motion.curve,
                ),
    ]);
    if (mounted && generation == scrollGeneration) {
      setState(() => autoScrolling = false);
    }
  }

  Widget wheel(
    String label,
    int count,
    String Function(int) text,
    int column,
    ValueChanged<int> changed,
    double extent,
  ) => Expanded(
    child: Semantics(
      label: label,
      child: CupertinoPicker.builder(
        scrollController: wheels[column],
        itemExtent: extent,
        childCount: count,
        onSelectedItemChanged: changed,
        itemBuilder: (context, index) => Center(
          child: Text(
            text(index),
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 20,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    scrollGeneration++;
    for (final controller in wheels) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final colors = Theme.of(c).colorScheme;
    final rowHeight = math.max(40.0, MediaQuery.textScalerOf(c).scale(22) + 12);
    return PanelContent(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
      header: PanelHeading(
        title: widget.timeOnly ? 'Select time' : 'Select date',
        trailing: IconButton(
          tooltip: widget.timeOnly ? 'Jump to current time' : 'Jump to today',
          onPressed: withFeedback(jumpToNow),
          icon: SvgPicture.asset(
            'assets/icons/rotate-ccw.svg',
            width: 20,
            height: 20,
            colorFilter: ColorFilter.mode(colors.onSurface, BlendMode.srcIn),
            excludeFromSemantics: true,
          ),
        ),
      ),
      footer: PanelActions(
        children: [
          AppButton(
            label: 'Confirm',
            onPressed: autoScrolling ? null : () => Navigator.pop(c, value),
          ),
          AppButton(
            label: 'Cancel',
            secondary: true,
            onPressed: () => Navigator.pop(c),
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
            child: Row(
              children: widget.timeOnly
                  ? [
                      wheel(
                        'Hour',
                        12,
                        (i) => '${i + 1}',
                        0,
                        (i) => setTime(
                          (i + 1) % 12 + (value.hour >= 12 ? 12 : 0),
                          value.minute,
                        ),
                        rowHeight,
                      ),
                      wheel(
                        'Minute',
                        60,
                        (i) => i.toString().padLeft(2, '0'),
                        1,
                        (i) => setTime(value.hour, i),
                        rowHeight,
                      ),
                      wheel(
                        'AM or PM',
                        2,
                        (i) => i == 0 ? 'AM' : 'PM',
                        2,
                        (i) => setTime(value.hour % 12 + i * 12, value.minute),
                        rowHeight,
                      ),
                    ]
                  : [
                      wheel(
                        'Month',
                        12,
                        (i) => DateFormat.MMM().format(DateTime(2000, i + 1)),
                        0,
                        (i) => setDate(value.year, i + 1, value.day),
                        rowHeight,
                      ),
                      wheel(
                        'Day',
                        DateUtils.getDaysInMonth(value.year, value.month),
                        (i) => '${i + 1}',
                        1,
                        (i) => setDate(value.year, value.month, i + 1),
                        rowHeight,
                      ),
                      wheel(
                        'Year',
                        widget.last!.year - widget.first!.year + 1,
                        (i) => '${widget.first!.year + i}',
                        2,
                        (i) => setDate(
                          widget.first!.year + i,
                          value.month,
                          value.day,
                        ),
                        rowHeight,
                      ),
                    ],
            ),
          ),
        ),
      ),
    );
  }
}
