part of 'design.dart';

class FlipClock extends StatelessWidget {
  final String value;
  final double size;
  final String label;
  const FlipClock(
    this.value, {
    super.key,
    this.size = 36,
    this.label = 'Elapsed time',
  });
  @override
  Widget build(BuildContext c) => Semantics(
    label: '$label $value',
    child: ExcludeSemantics(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            value.length,
            (i) => value[i] == ':'
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Text(
                      ':',
                      style: TextStyle(
                        fontFamily: 'Geist Mono',
                        fontSize: size * .8,
                        color: Theme.of(c).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _FlapDigit(
                      key: ValueKey(value.length - i),
                      digit: value[i],
                      size: size,
                    ),
                  ),
          ),
        ),
      ),
    ),
  );
}

class _FlapDigit extends StatefulWidget {
  final String digit;
  final double size;
  const _FlapDigit({super.key, required this.digit, required this.size});
  @override
  State<_FlapDigit> createState() => _FlapDigitState();
}

class _FlapDigitState extends State<_FlapDigit>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
    value: 1,
  );
  late String previous = widget.digit;
  @override
  void didUpdateWidget(_FlapDigit old) {
    super.didUpdateWidget(old);
    if (old.digit != widget.digit) {
      previous = old.digit;
      if (MediaQuery.disableAnimationsOf(context)) {
        controller.value = 1;
      } else {
        controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final colors = Theme.of(c).colorScheme;
    final height = widget.size * 1.5;
    Widget half(String digit, bool top) => SizedBox(
      height: height / 2,
      child: ClipRect(
        child: OverflowBox(
          alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
          minHeight: height,
          maxHeight: height,
          child: Container(
            height: height,
            color: colors.surfaceContainerHighest,
            alignment: Alignment.center,
            child: Text(
              digit,
              style: TextStyle(
                fontFamily: 'Geist Mono',
                fontSize: widget.size,
                height: 1,
                color: colors.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
    Widget rotate(Widget child, double angle, Alignment pivot) => Transform(
      alignment: pivot,
      transform: Matrix4.identity()
        ..setEntry(3, 2, .002)
        ..rotateX(angle),
      child: child,
    );
    return SizedBox(
      width: widget.size * .75,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: AnimatedBuilder(
          animation: controller,
          builder: (c, _) {
            final done =
                controller.value == 1 || MediaQuery.disableAnimationsOf(c);
            final phase = controller.value;
            final topProgress = Motion.curve.transform((phase * 2).clamp(0, 1));
            final bottomProgress = Motion.curve.transform(
              (phase * 2 - 1).clamp(0, 1),
            );
            return Stack(
              children: [
                Column(
                  children: [
                    half(widget.digit, true),
                    half(done ? widget.digit : previous, false),
                  ],
                ),
                if (!done && phase < .5)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: rotate(
                      half(previous, true),
                      -math.pi / 2 * topProgress,
                      Alignment.bottomCenter,
                    ),
                  ),
                if (!done && phase >= .5)
                  Positioned(
                    top: height / 2,
                    left: 0,
                    right: 0,
                    child: rotate(
                      half(widget.digit, false),
                      math.pi / 2 * (1 - bottomProgress),
                      Alignment.topCenter,
                    ),
                  ),
                Positioned(
                  top: height / 2 - .5,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: 1,
                      color: colors.surface.withValues(alpha: .8),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
