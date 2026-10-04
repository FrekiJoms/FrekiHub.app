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
  final noteFocus = FocusNode();
  Timer? noteDebounce;
  (String, String)? pendingNote;
  Future<void> noteWrites = Future.value();
  AppDatabase? noteStore;
  String lastDraft = '';
  bool wasComposing = false, noteBound = false;
  Timer? timer;
  late final tick = ValueNotifier<DateTime>(widget.clockNow());
  StreamSubscription<List<ConnectivityResult>>? connectivity;
  bool offline = false, busy = false, confirming = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    note.text = widget.data.running?.note ?? '';
    bindNote();
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

  void bindNote() {
    if (noteBound) return;
    noteBound = true;
    lastDraft = note.text;
    note.addListener(queueNote);
    noteFocus.addListener(flushOnBlur);
  }

  void queueNote() {
    final value = note.value;
    final composing = value.composing.isValid && !value.composing.isCollapsed;
    if (value.text == lastDraft && composing == wasComposing) return;
    lastDraft = value.text;
    wasComposing = composing;
    final running = widget.data.running;
    if (busy || running == null) return;
    // Capture while mounted, before a blur/navigation flush can run in dispose.
    noteStore ??= ref.read(databaseProvider);
    pendingNote = (running.id, value.text);
    noteDebounce?.cancel();
    // Selection/caret changes do not write; keep IME composition local.
    if (!composing) {
      noteDebounce = Timer(const Duration(milliseconds: 400), () {
        unawaited(flushNote());
      });
    }
  }

  void flushOnBlur() {
    if (!noteFocus.hasFocus) unawaited(flushNote());
  }

  Future<void> flushNote() {
    noteDebounce?.cancel();
    final draft = pendingNote;
    pendingNote = null;
    if (draft == null) return noteWrites;
    final db = noteStore!;
    // Serialize writes so an earlier draft cannot overwrite the latest one.
    noteWrites = noteWrites
        .then((_) async {
          await (db.update(db.sessions)
                ..where((s) => s.id.equals(draft.$1) & s.ended.isNull()))
              .write(SessionsCompanion(note: Value(draft.$2)));
        })
        .catchError((Object _) {
          if (mounted) {
            toast(context, 'Could not save your note. Try again.', error: true);
          }
        });
    return noteWrites;
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
      unawaited(flushNote());
    }
  }

  void updateConnection(List<ConnectivityResult> values) {
    if (mounted) {
      setState(() => offline = values.contains(ConnectivityResult.none));
    }
  }

  @override
  void dispose() {
    unawaited(flushNote());
    note.removeListener(queueNote);
    noteFocus.removeListener(flushOnBlur);
    noteFocus.dispose();
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    tick.dispose();
    connectivity?.cancel();
    note.dispose();
    super.dispose();
  }

  Future<void> clock() async {
    if (busy || confirming) return;
    final running = widget.data.running;
    var endingNote = note.text.trim();
    try {
      if (running != null) {
        setState(() => confirming = true);
        final accepted = await panel<String>(
          context,
          _EndSessionConfirmation(
            data: widget.data,
            session: running,
            tick: tick,
            initialNote: note.text,
          ),
        );
        if (!mounted || accepted == null) return;
        endingNote = accepted;
      }
      if (!mounted) return;
      setState(() => busy = true);
      await flushNote();
      if (!mounted) return;
      final db = ref.read(databaseProvider);
      if (running == null) {
        await db.clockIn(note.text.trim());
        HapticFeedback.mediumImpact();
        unawaited(
          FeedbackSound.play(widget.data.prefs['sound'] == 'true', 'clock-in'),
        );
      } else {
        await db.transaction(() async {
          await (db.update(db.sessions)
                ..where((s) => s.id.equals(running.id) & s.ended.isNull()))
              .write(SessionsCompanion(note: Value(endingNote)));
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
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          confirming = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext c) {
    // Also bind newly added listeners when reviewing this state with hot reload.
    bindNote();
    final d = widget.data;
    final running = d.running;
    int duration(Session s, DateTime now) => math.max(
      0,
      ((s.ended ?? now.millisecondsSinceEpoch) - s.started) ~/ 1000,
    );
    final recent = [...d.sessions]
      ..sort((a, b) => b.started.compareTo(a.started));
    return _HomeBalanceDock(
      balance: Semantics(
        label:
            'Total balance in ${d.currency}: ${money(d.balance, d.currency)}',
        child: ExcludeSemantics(
          child: Chrome(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
      builder: (scrollController, balanceSlot) => PageBody(
        scrollController: scrollController,
        leading: balanceSlot,
        title: 'HOME',
        subtitle: DateFormat('EEEE, d MMMM').format(tick.value),
        compactHeader: true,
        children: [
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
                ValueListenableBuilder<DateTime>(
                  valueListenable: tick,
                  builder: (c, now, _) => Text(
                    'Current time · ${DateFormat(d.prefs['clockFormat'] == '12' ? 'hh:mm:ss a' : 'HH:mm:ss').format(now)}',
                    style: TextStyle(
                      fontFamily: 'Geist Mono',
                      fontSize: 11,
                      color: Theme.of(c).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
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
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: withFeedback(busy || confirming ? null : clock),
                    icon: Icon(
                      running == null ? LucideIcons.play : LucideIcons.square,
                      size: 19,
                    ),
                    label: SkeletonValue(
                      loading: busy,
                      semanticsLabel: running == null
                          ? 'Clocking in'
                          : 'Clocking out',
                      child: Text(running == null ? 'Clock in' : 'Clock out'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                RepaintBoundary(
                  child: TextField(
                    controller: note,
                    focusNode: noteFocus,
                    decoration: const InputDecoration(
                      labelText: 'What are you working on?',
                      prefixIcon: Icon(LucideIcons.pencilLine, size: 18),
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
      ),
    );
  }
}

class _EndSessionConfirmation extends StatefulWidget {
  final AppData data;
  final Session session;
  final ValueNotifier<DateTime> tick;
  final String initialNote;
  const _EndSessionConfirmation({
    required this.data,
    required this.session,
    required this.tick,
    required this.initialNote,
  });

  @override
  State<_EndSessionConfirmation> createState() =>
      _EndSessionConfirmationState();
}

class _EndSessionConfirmationState extends State<_EndSessionConfirmation> {
  late final draft = TextEditingController(text: widget.initialNote);
  @override
  void dispose() {
    draft.dispose();
    super.dispose();
  }

  void choose(BuildContext context, bool accepted) {
    if (ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop(accepted ? draft.text.trim() : null);
    }
  }

  @override
  Widget build(BuildContext context) => PanelContent(
    padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
    header: const PanelHeading(
      title: 'End this session?',
      leading: Chrome(
        padding: EdgeInsets.all(10),
        child: Icon(LucideIcons.timer, size: 20),
      ),
    ),
    footer: PanelActions(
      children: [
        AppButton(
          label: 'End session',
          icon: LucideIcons.square,
          onPressed: () => choose(context, true),
        ),
        AppButton(
          label: 'Keep running',
          secondary: true,
          onPressed: () => choose(context, false),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Save your time and notes to Sessions.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Session duration'),
            const SizedBox(height: 6),
            ValueListenableBuilder<DateTime>(
              valueListenable: widget.tick,
              builder: (context, now, _) => Text(
                elapsed(
                  math.max(
                    0,
                    (now.millisecondsSinceEpoch - widget.session.started) ~/
                        1000,
                  ),
                ),
                style: const TextStyle(
                  fontFamily: 'Geist Mono',
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${widget.session.kind} · Started at ${clockTime(widget.data, widget.session.started)}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        RepaintBoundary(
          child: TextField(
            key: const ValueKey('end-session-note'),
            controller: draft,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Session note',
              hintText: 'What did you work on?',
              alignLabelWithHint: true,
            ),
          ),
        ),
      ],
    ),
  );
}

// The invisible slot reserves the original layout; only one pill is painted
// and exposed to accessibility. Scroll updates rebuild its transform alone.
class _HomeBalanceDock extends StatefulWidget {
  final Widget balance;
  final Widget Function(ScrollController, Widget) builder;
  const _HomeBalanceDock({required this.balance, required this.builder});

  @override
  State<_HomeBalanceDock> createState() => _HomeBalanceDockState();
}

class _HomeBalanceDockState extends State<_HomeBalanceDock> {
  final scroll = ScrollController();
  final stackKey = GlobalKey();
  final slotKey = GlobalKey();
  final geometry = ValueNotifier<({double top, double width})?>(null);
  late final movement = Listenable.merge([scroll, geometry]);

  void measure() {
    if (!mounted) return;
    final stack = stackKey.currentContext?.findRenderObject() as RenderBox?;
    final slot = slotKey.currentContext?.findRenderObject() as RenderBox?;
    if (stack == null || slot == null || !slot.attached) return;
    geometry.value = (
      top: slot.localToGlobal(Offset.zero, ancestor: stack).dy + scroll.offset,
      width: slot.size.width,
    );
  }

  @override
  void dispose() {
    scroll.dispose();
    geometry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WidthLayoutBuilder(
    builder: (context, width) {
      WidgetsBinding.instance.addPostFrameCallback((_) => measure());
      final inset = width < 380 ? 16.0 : 24.0;
      final horizontal = math.max(inset, (width - 720) / 2);
      final reduced = MediaQuery.disableAnimationsOf(context);
      return Stack(
        key: stackKey,
        children: [
          Positioned.fill(
            child: widget.builder(
              scroll,
              Center(
                child: Visibility(
                  visible: false,
                  maintainState: true,
                  maintainAnimation: true,
                  maintainSize: true,
                  child: KeyedSubtree(key: slotKey, child: widget.balance),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: horizontal,
            right: horizontal,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: movement,
                child: RepaintBoundary(
                  child: KeyedSubtree(
                    key: const ValueKey('home-balance-pill'),
                    child: widget.balance,
                  ),
                ),
                builder: (context, child) {
                  final measured = geometry.value;
                  if (measured == null) return const SizedBox.shrink();
                  final offset = scroll.hasClients ? scroll.offset : 0.0;
                  final progress = reduced
                      ? (offset > 48 ? 1.0 : 0.0)
                      : Curves.easeInOutCubic.transform(
                          (offset / 120).clamp(0.0, 1.0),
                        );
                  // Settings is at y=16 with a 48px touch target; dock 9px below.
                  final top = measured.top + (73 - measured.top) * progress;
                  final rightShift = (width - measured.width) / 2 - 16;
                  return Transform.translate(
                    offset: Offset(rightShift * progress, top),
                    child: Center(child: child),
                  );
                },
              ),
            ),
          ),
        ],
      );
    },
  );
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
