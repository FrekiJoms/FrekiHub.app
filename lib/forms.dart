part of 'screens.dart';

class SessionForm extends ConsumerStatefulWidget {
  final AppData data;
  final Session? session;
  final String day;
  const SessionForm({
    super.key,
    required this.data,
    required this.day,
    this.session,
  });
  @override
  ConsumerState<SessionForm> createState() => _SessionFormState();
}

class _SessionFormState extends ConsumerState<SessionForm> {
  late DateTime day, start;
  DateTime? end;
  late String kind;
  late TextEditingController note;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    day = calendarDate(widget.day);
    start = widget.session == null
        ? DateTime(day.year, day.month, day.day, 8)
        : DateTime.fromMillisecondsSinceEpoch(widget.session!.started);
    end = widget.session == null
        ? DateTime(day.year, day.month, day.day, 17)
        : widget.session!.ended == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(widget.session!.ended!);
    kind = widget.session?.kind ?? 'OJT';
    note = TextEditingController(text: widget.session?.note ?? '');
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> time(bool ending) async {
    final old = ending ? end ?? start : start;
    final date = await showWheelDatePicker(
      context: context,
      initialDate: old,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) {
      return;
    }
    final t = await showWheelTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(old),
    );
    if (t != null && mounted) {
      setState(() {
        final value = DateTime(
          date.year,
          date.month,
          date.day,
          t.hour,
          t.minute,
        );
        if (ending) {
          end = value;
        } else {
          start = value;
          day = date;
        }
      });
    }
  }

  Future<void> save() async {
    if (end != null && !end!.isAfter(start)) {
      toast(context, 'Clock out must be later than clock in.', error: true);
      return;
    }
    if (end == null && start.isAfter(DateTime.now())) {
      toast(
        context,
        'A running session cannot start in the future.',
        error: true,
      );
      return;
    }
    setState(() {
      saving = true;
    });
    try {
      final db = ref.read(databaseProvider);
      await db
          .into(db.sessions)
          .insertOnConflictUpdate(
            Session(
              id: widget.session?.id ?? newId(),
              day: dayKey(day),
              kind: kind,
              started: start.millisecondsSinceEpoch,
              ended: end?.millisecondsSinceEpoch,
              note: note.text.trim(),
            ),
          );
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
        });
        toast(
          context,
          'Could not save session. Check that no other session is running, then try again.',
          error: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext c) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.session == null ? 'Add a session' : 'Session details',
          style: Theme.of(c).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        spaced(
          selectField('Session type', kind, [
            'OJT',
            'Work',
            'Study',
            'Personal',
          ], (v) => setState(() => kind = v)),
        ),
        spaced(
          OutlinedButton(
            onPressed: withFeedback(() => time(false)),
            child: Text(
              'Clock in · ${DateFormat('d MMM yyyy, HH:mm').format(start)}',
            ),
          ),
        ),
        spaced(
          OutlinedButton(
            onPressed: withFeedback(() => time(true)),
            child: Text(
              'Clock out · ${end == null ? 'Still running' : DateFormat('d MMM yyyy, HH:mm').format(end!)}',
            ),
          ),
        ),
        if (widget.session?.ended == null && widget.session != null)
          spaced(
            TextButton(
              onPressed: withFeedback(
                () => setState(() => end = DateTime.now()),
              ),
              child: const Text('End now'),
            ),
          ),
        spaced(
          TextField(
            controller: note,
            decoration: const InputDecoration(labelText: 'Session note'),
            minLines: 2,
            maxLines: 4,
          ),
        ),
        FilledButton(
          onPressed: withFeedback(saving ? null : save),
          child: Text(saving ? 'Saving…' : 'Save session'),
        ),
        if (widget.session != null)
          TextButton(
            onPressed: withFeedback(() async {
              final deleted = await deleteSession(c, ref, widget.session!);
              if (deleted && c.mounted) {
                Navigator.pop(c);
              }
            }),
            child: Text(
              'Delete session',
              style: TextStyle(color: Theme.of(c).colorScheme.error),
            ),
          ),
        TextButton(
          onPressed: withFeedback(() => Navigator.pop(c)),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

class EntryForm extends ConsumerStatefulWidget {
  final AppData data;
  final String day, kind;
  final Entry? entry;
  const EntryForm({
    super.key,
    required this.data,
    required this.day,
    required this.kind,
    this.entry,
  });
  @override
  ConsumerState<EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends ConsumerState<EntryForm> {
  late String category, method, kind, day;
  late TextEditingController amount, note;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    kind = e?.kind ?? widget.kind;
    day = e?.day ?? widget.day;
    category =
        e?.category ??
        (kind == 'income'
            ? 'Salary'
            : kind == 'savings'
            ? 'Savings'
            : widget.data.categories.first);
    method = e?.method ?? widget.data.methods.first;
    amount = TextEditingController(
      text: e == null ? '' : editableMoney(e.amount, e.currency),
    );
    note = TextEditingController(text: e?.note ?? '');
  }

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> save() async {
    try {
      final currency = widget.entry?.currency ?? widget.data.currency;
      final minor = parseMoney(amount.text, currency);
      if (minor <= 0) {
        throw const FormatException('Amount must be greater than zero.');
      }
      setState(() {
        busy = true;
      });
      final db = ref.read(databaseProvider);
      await db
          .into(db.entries)
          .insertOnConflictUpdate(
            Entry(
              id: widget.entry?.id ?? newId(),
              day: day,
              kind: kind,
              amount: minor,
              currency: currency,
              category: category,
              method: method,
              note: note.text.trim(),
              occurrence: widget.entry?.occurrence,
            ),
          );
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
      });
      toast(
        context,
        e is FormatException
            ? e.message
            : 'Unable to save transaction. Try again.',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext c) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.entry == null ? 'Add $kind' : 'Edit transaction',
          style: Theme.of(c).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        spaced(
          selectField('Type', kind, [
            'expense',
            'income',
            'savings',
          ], (v) => setState(() => kind = v)),
        ),
        spaced(
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText:
                  'Amount · ${widget.entry?.currency ?? widget.data.currency}',
            ),
          ),
        ),
        spaced(
          OutlinedButton(
            onPressed: withFeedback(() async {
              final d = await showWheelDatePicker(
                context: c,
                initialDate: calendarDate(day),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (d != null && mounted) {
                setState(() => day = dayKey(d));
              }
            }),
            child: Text(
              DateFormat('EEEE, d MMMM yyyy').format(calendarDate(day)),
            ),
          ),
        ),
        spaced(
          selectField(
            'Category',
            category,
            {...widget.data.categories, category}.toList(),
            (v) => category = v,
          ),
        ),
        spaced(
          selectField(
            'Payment method',
            method,
            {...widget.data.methods, method}.toList(),
            (v) => method = v,
          ),
        ),
        spaced(
          TextField(
            controller: note,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
            maxLines: 3,
          ),
        ),
        FilledButton(
          onPressed: withFeedback(busy ? null : save),
          child: Text(busy ? 'Saving…' : 'Save transaction'),
        ),
        if (widget.entry != null)
          TextButton(
            onPressed: withFeedback(() async {
              if (await confirm(
                c,
                'Delete transaction?',
                'This record will be permanently removed.',
              )) {
                if (!c.mounted) return;
                await guarded(c, () async {
                  final db = ref.read(databaseProvider);
                  await (db.delete(
                    db.entries,
                  )..where((e) => e.id.equals(widget.entry!.id))).go();
                  if (c.mounted) Navigator.pop(c);
                });
              }
            }),
            child: Text(
              'Delete transaction',
              style: TextStyle(color: Theme.of(c).colorScheme.error),
            ),
          ),
        TextButton(
          onPressed: withFeedback(() => Navigator.pop(c)),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

class RuleForm extends ConsumerStatefulWidget {
  final AppData data;
  final Rule? rule;
  const RuleForm({super.key, required this.data, this.rule});
  @override
  ConsumerState<RuleForm> createState() => _RuleFormState();
}

class _RuleFormState extends ConsumerState<RuleForm> {
  late TextEditingController title, amount, quantity;
  late String kind, basis, cadence, category, method, start;
  String? finish;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    final r = widget.rule;
    title = TextEditingController(text: r?.title ?? '');
    basis = r?.basis ?? 'fixed';
    amount = TextEditingController(
      text: r == null
          ? ''
          : editableMoney(r.amount, basis == 'fixed' ? r.currency : 'PHP'),
    );
    quantity = TextEditingController(text: '${r?.quantity ?? 1}');
    kind = r?.kind ?? 'expense';
    cadence = r?.cadence ?? 'monthly';
    category = r?.category ?? widget.data.categories.first;
    method = r?.method ?? widget.data.methods.first;
    start = r?.start ?? dayKey(DateTime.now());
    finish = r?.finish;
  }

  @override
  void dispose() {
    title.dispose();
    amount.dispose();
    quantity.dispose();
    super.dispose();
  }

  Future<void> save() async {
    try {
      if (title.text.trim().isEmpty) {
        throw const FormatException('Give this rule a name.');
      }
      final value = parseMoney(
        amount.text,
        basis == 'fixed'
            ? widget.rule?.currency ?? widget.data.currency
            : 'PHP',
      );
      final q = int.tryParse(quantity.text);
      if (q == null || q < 1 || q > 100000 || value <= 0) {
        throw const FormatException('Use a positive amount and quantity.');
      }
      if (BigInt.from(value) * BigInt.from(q) > BigInt.from(9000000000000000)) {
        throw const FormatException('Amount × quantity is too large.');
      }
      if (basis != 'fixed' && value > 10000) {
        throw const FormatException('Percentage must be between 0 and 100.');
      }
      if (finish != null && finish!.compareTo(start) < 0) {
        throw const FormatException('End date must follow the start date.');
      }
      setState(() {
        saving = true;
      });
      final db = ref.read(databaseProvider);
      await db
          .into(db.rules)
          .insertOnConflictUpdate(
            Rule(
              id: widget.rule?.id ?? newId(),
              title: title.text.trim(),
              kind: kind,
              amount: value,
              currency: widget.rule?.currency ?? widget.data.currency,
              quantity: q,
              basis: basis,
              cadence: cadence,
              start: start,
              finish: finish,
              category: category,
              method: method,
              position: widget.rule?.position ?? widget.data.rules.length,
            ),
          );
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
        });
        toast(
          context,
          e is FormatException ? e.message : 'Could not save rule. Try again.',
          error: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext c) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.rule == null ? 'Plan a transaction' : 'Edit planner rule',
          style: Theme.of(c).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        spaced(
          TextField(
            controller: title,
            decoration: const InputDecoration(
              labelText: 'Name, e.g. Rent or Payday savings',
            ),
          ),
        ),
        spaced(
          selectField('Transaction type', kind, [
            'expense',
            'income',
            'savings',
          ], (v) => setState(() => kind = v)),
        ),
        spaced(
          selectField(
            'Calculation',
            basis,
            ['fixed', 'income', 'expenses', 'net'],
            (v) => setState(() {
              basis = v;
              amount.clear();
            }),
          ),
        ),
        SizeTransitionPanel(
          child: Column(
            children: [
              spaced(
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: basis == 'fixed'
                        ? 'Amount · ${widget.rule?.currency ?? widget.data.currency}'
                        : 'Percentage of monthly $basis',
                  ),
                ),
              ),
              if (basis != 'fixed')
                spaced(
                  const Text(
                    'Calculated from actual records in the occurrence’s month.',
                  ),
                ),
              spaced(
                TextField(
                  controller: quantity,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantity / multiplier',
                  ),
                ),
              ),
            ],
          ),
        ),
        spaced(
          selectField('Repeat', cadence, [
            'once',
            'daily',
            'weekly',
            'monthly',
          ], (v) => setState(() => cadence = v)),
        ),
        spaced(
          OutlinedButton(
            onPressed: withFeedback(() async {
              final d = await showWheelDatePicker(
                context: c,
                initialDate: calendarDate(start),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (d != null && mounted) {
                setState(() => start = dayKey(d));
              }
            }),
            child: Text('Starts · $start'),
          ),
        ),
        if (cadence != 'once')
          spaced(
            OutlinedButton(
              onPressed: withFeedback(() async {
                final d = await showWheelDatePicker(
                  context: c,
                  initialDate: calendarDate(finish ?? start),
                  firstDate: calendarDate(start),
                  lastDate: DateTime(2100),
                );
                if (d != null && mounted) {
                  setState(() => finish = dayKey(d));
                }
              }),
              child: Text('Ends · ${finish ?? 'No end date'}'),
            ),
          ),
        if (finish != null)
          TextButton(
            onPressed: withFeedback(() => setState(() => finish = null)),
            child: const Text('Remove end date'),
          ),
        spaced(
          selectField(
            'Category',
            category,
            {...widget.data.categories, category}.toList(),
            (v) => category = v,
          ),
        ),
        spaced(
          selectField(
            'Payment method',
            method,
            {...widget.data.methods, method}.toList(),
            (v) => method = v,
          ),
        ),
        FilledButton(
          onPressed: withFeedback(saving ? null : save),
          child: Text(saving ? 'Saving…' : 'Save rule'),
        ),
        TextButton(
          onPressed: withFeedback(() => Navigator.pop(c)),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}
