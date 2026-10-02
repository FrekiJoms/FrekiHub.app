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
  scrollable: true,
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
    scrollable: true,
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
  @override
  Widget build(BuildContext c) {
    final colors = Theme.of(c).colorScheme;
    final rowHeight = math.max(40.0, MediaQuery.textScalerOf(c).scale(22) + 12);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                TextButton(
                  onPressed: withFeedback(() => Navigator.pop(c)),
                  child: const Text('Cancel'),
                ),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      widget.timeOnly ? 'Select time' : 'Select date',
                      textAlign: TextAlign.center,
                      style: Theme.of(c).textTheme.titleMedium,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: withFeedback(() => Navigator.pop(c, value)),
                  child: const Text('Confirm'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
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
                child: CupertinoDatePicker(
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
                      (
                        context, {
                        required selectedIndex,
                        required columnCount,
                      }) => Container(
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
                    if (date == value) return;
                    value = date;
                    ActionFeedback.tap();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
