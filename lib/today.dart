part of 'screens.dart';

class TodayScreen extends ConsumerStatefulWidget {
  final AppData data;
  final DateTime Function() clockNow;
  const TodayScreen({
    super.key,
    required this.data,
    this.clockNow = DateTime.now,
  });
  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen>
    with WidgetsBindingObserver {
  final note = TextEditingController();
  Timer? timer;
  late final tick = ValueNotifier<DateTime>(widget.clockNow());
  StreamSubscription<List<ConnectivityResult>>? connectivity;
  bool offline = false, busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    note.text = widget.data.running?.note ?? '';
    refreshTime();
    connectivity = Connectivity().onConnectivityChanged.listen(
      updateConnection,
      onError: (Object _) {},
    );
    Connectivity()
        .checkConnectivity()
        .then(updateConnection)
        .catchError((Object _) {});
  }

  void refreshTime() {
    timer?.cancel();
    final previous = tick.value;
    final now = widget.clockNow();
    tick.value = now;
    if (dayKey(previous) != dayKey(now)) setState(() {});
    // Re-align after every sample, including resume and device clock changes.
    timer = Timer(
      Duration(
        microseconds: 1000000 - now.microsecond - now.millisecond * 1000,
      ),
      refreshTime,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refreshTime();
    } else {
      timer?.cancel();
    }
  }

  void updateConnection(List<ConnectivityResult> values) {
    if (mounted) {
      setState(() => offline = values.contains(ConnectivityResult.none));
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    tick.dispose();
    connectivity?.cancel();
    note.dispose();
    super.dispose();
  }

  Future<void> clock() async {
    setState(() => busy = true);
    try {
      final db = ref.read(databaseProvider);
      final running = widget.data.running;
      if (running == null) {
        await db.clockIn(note.text.trim());
        HapticFeedback.mediumImpact();
        unawaited(
          FeedbackSound.play(widget.data.prefs['sound'] == 'true', 'clock-in'),
        );
      } else {
        await db.transaction(() async {
          await (db.update(db.sessions)..where((s) => s.id.equals(running.id)))
              .write(SessionsCompanion(note: Value(note.text.trim())));
          await db.clockOut(running.id);
        });
        HapticFeedback.mediumImpact();
        unawaited(
          FeedbackSound.play(widget.data.prefs['sound'] == 'true', 'clock-out'),
        );
        note.clear();
      }
    } on StateError catch (e) {
      if (mounted) {
        toast(context, e.message.toString(), error: true);
      }
    } catch (e) {
      if (mounted) {
        toast(
          context,
          'Your session could not be saved. Try again.',
          error: true,
        );
      }
    }
    if (mounted) {
      setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final d = widget.data;
    final running = d.running;
    final today = dayKey(tick.value);
    final todaySessions = d.sessions.where((s) => s.day == today).toList();
    int duration(Session s, DateTime now) => math.max(
      0,
      ((s.ended ?? now.millisecondsSinceEpoch) - s.started) ~/ 1000,
    );
    int total(DateTime now) =>
        todaySessions.fold(0, (sum, s) => sum + duration(s, now));
    final recent = [...d.sessions]
      ..sort((a, b) => b.started.compareTo(a.started));
    return PageBody(
      title: 'Home.',
      subtitle: DateFormat('EEEE, d MMMM').format(tick.value),
      compactHeader: true,
      children: [
        Center(
          child: Semantics(
            label:
                'Total balance in ${d.currency}: ${money(d.balance, d.currency)}',
            child: ExcludeSemantics(
              child: Surface(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Icon(
                      LucideIcons.wallet,
                      size: 15,
                      color: Theme.of(c).colorScheme.onSurfaceVariant,
                    ),
                    Text(
                      'Balance',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(c).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      money(d.balance, d.currency),
                      style: const TextStyle(
                        fontFamily: 'Geist Mono',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (offline)
          const Surface(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(LucideIcons.wifiOff, size: 18),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Offline · all records save on this phone'),
                ),
              ],
            ),
          ),
        Surface(
          child: Column(
            children: [
              const SizedBox(height: 8),
              RepaintBoundary(
                child: ValueListenableBuilder<DateTime>(
                  valueListenable: tick,
                  builder: (c, now, _) =>
                      AnalogClock(now: now, clockNow: widget.clockNow),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                running == null
                    ? 'READY WHEN YOU ARE'
                    : 'YOUR SESSION IS RUNNING',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 2,
                  color: Theme.of(c).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<DateTime>(
                valueListenable: tick,
                builder: (c, now, _) => FlipClock(
                  running == null
                      ? DateFormat(
                          d.prefs['clockFormat'] == '12'
                              ? 'hh:mm:ss'
                              : 'HH:mm:ss',
                        ).format(now)
                      : elapsed(duration(running, now)),
                  size: 36,
                  label: running == null ? 'Current time' : 'Elapsed time',
                ),
              ),
              const SizedBox(height: 10),
              ValueListenableBuilder<DateTime>(
                valueListenable: tick,
                builder: (c, now, _) => Text(
                  running == null
                      ? d.prefs['clockFormat'] == '12'
                            ? 'Current time · ${DateFormat('a').format(now)}'
                            : 'Current time'
                      : 'Clocked in at ${clockTime(d, running.started)}',
                  style: TextStyle(
                    color: Theme.of(c).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: withFeedback(busy ? null : clock),
                  icon: Icon(
                    running == null ? LucideIcons.play : LucideIcons.square,
                    size: 19,
                  ),
                  label: Text(
                    busy
                        ? 'Saving…'
                        : running == null
                        ? 'Clock in'
                        : 'Clock out',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                decoration: const InputDecoration(
                  labelText: 'What are you working on?',
                  prefixIcon: Icon(LucideIcons.pencilLine, size: 18),
                ),
                onChanged: (value) {
                  if (running != null) {
                    final db = ref.read(databaseProvider);
                    unawaited(
                      (db.update(db.sessions)
                            ..where((s) => s.id.equals(running.id)))
                          .write(SessionsCompanion(note: Value(value))),
                    );
                  }
                },
              ),
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: ValueListenableBuilder<DateTime>(
                  valueListenable: tick,
                  builder: (c, now, _) => Text(
                    'Today’s total  ${elapsed(total(now))}',
                    style: const TextStyle(
                      fontFamily: 'Geist Mono',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SectionHeading(
          'Recent sessions',
          trailing: Text(
            '${d.sessions.length} records',
            style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant),
          ),
        ),
        if (recent.isEmpty)
          const Surface(
            child: EmptyState(
              'Your first session starts here.',
              'Clock in above, or add a past session.',
              LucideIcons.clock3,
            ),
          )
        else
          ...recent.take(3).map((s) => sessionTile(c, ref, d, s)),
      ],
    );
  }
}

class AnalogClock extends StatefulWidget {
  final DateTime now;
  final DateTime Function() clockNow;
  const AnalogClock({
    super.key,
    required this.now,
    this.clockNow = DateTime.now,
  });
  @override
  State<AnalogClock> createState() => _AnalogClockState();
}

class _AnalogClockState extends State<AnalogClock>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.stop();
    } else if (!controller.isAnimating) {
      controller.repeat();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Semantics(
    label: 'Current time ${DateFormat('HH:mm').format(widget.now)}',
    child: SizedBox(
      width: 164,
      height: 164,
      child: CustomPaint(
        painter: _ClockPainter(
          controller,
          Theme.of(c).colorScheme.onSurface,
          Theme.of(c).colorScheme.surfaceContainerHighest,
          widget.now,
          MediaQuery.disableAnimationsOf(c) ? null : widget.clockNow,
        ),
      ),
    ),
  );
}

class _ClockPainter extends CustomPainter {
  final Color ink, muted;
  final DateTime sampledTime;
  final DateTime Function()? clockNow;
  _ClockPainter(
    Listenable animation,
    this.ink,
    this.muted,
    this.sampledTime,
    this.clockNow,
  ) : super(repaint: animation);
  @override
  void paint(Canvas c, Size s) {
    final center = s.center(Offset.zero), radius = s.width / 2;
    c.drawCircle(center, radius, Paint()..color = muted.withValues(alpha: .35));
    for (var i = 0; i < 60; i++) {
      final angle = i * math.pi / 30 - math.pi / 2;
      final outer =
          center + Offset(math.cos(angle), math.sin(angle)) * (radius - 13);
      final inner =
          center +
          Offset(math.cos(angle), math.sin(angle)) *
              (radius - (i % 5 == 0 ? 26 : 18));
      c.drawLine(
        inner,
        outer,
        Paint()
          ..color = ink.withValues(alpha: i % 5 == 0 ? .7 : .2)
          ..strokeWidth = i % 5 == 0 ? 2 : 1
          ..strokeCap = StrokeCap.round,
      );
    }
    final now = clockNow?.call() ?? sampledTime;
    final seconds = now.second + now.millisecond / 1000;
    void hand(
      double value,
      double maximum,
      double length,
      double width,
      Color color,
    ) {
      final a = value / maximum * 2 * math.pi - math.pi / 2;
      final vector = Offset(math.cos(a), math.sin(a));
      c.drawLine(
        center - vector * 9,
        center + vector * length,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
    }

    hand(
      now.hour % 12 + (now.minute + seconds / 60) / 60,
      12,
      radius * .46,
      5,
      ink,
    );
    hand(now.minute + seconds / 60, 60, radius * .67, 3, ink);
    hand(seconds, 60, radius * .77, 1.2, ink.withValues(alpha: .5));
    c.drawCircle(center, 4, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(_ClockPainter old) =>
      ink != old.ink ||
      muted != old.muted ||
      sampledTime != old.sampledTime ||
      clockNow != old.clockNow;
}
