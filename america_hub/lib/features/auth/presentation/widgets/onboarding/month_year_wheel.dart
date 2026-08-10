import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'aurora_surfaces.dart';

const _monthNames = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
];

/// The earliest arrival year offered. Members who came before this are rare
/// enough that a longer wheel costs everyone else scrolling.
const _earliestYear = 1950;

/// Height of one row on either wheel.
const kWheelItemExtent = 40.0;

/// Only the rows around a wheel's centre are built, so a test cannot reach a
/// distant month by tapping its label. These let it drag the right wheel by a
/// known number of [kWheelItemExtent] steps instead.
const monthWheelKey = ValueKey('arrival-month-wheel');
const yearWheelKey = ValueKey('arrival-year-wheel');

/// Month and year picked side by side on two wheels.
///
/// The grid-of-months plus horizontal year strip this replaces took roughly
/// twice the height and, worse, showed only four years at a time with no sign
/// that it scrolled — members read that as "the app only knows four years".
/// A wheel is self-evidently scrollable and puts both halves of one answer on
/// one line.
///
/// Index 0 of each wheel is a blank placeholder, so "nothing chosen yet" is a
/// real state. Without it the wheel would always look like an answer and the
/// step could no longer be skipped.
class MonthYearWheel extends StatefulWidget {
  const MonthYearWheel({
    super.key,
    required this.month,
    required this.year,
    required this.currentYear,
    required this.onChanged,
    this.accent = const Color(0xFFE8A33A),
  });

  final int? month;
  final int? year;
  final int currentYear;
  final void Function(int? month, int? year) onChanged;
  final Color accent;

  @override
  State<MonthYearWheel> createState() => _MonthYearWheelState();
}

class _MonthYearWheelState extends State<MonthYearWheel> {
  late int _monthIndex = widget.month ?? 0;
  late int _yearIndex = widget.year == null ? 0 : widget.currentYear - widget.year! + 1;
  late final FixedExtentScrollController _monthController =
      FixedExtentScrollController(initialItem: _monthIndex);
  late final FixedExtentScrollController _yearController =
      FixedExtentScrollController(initialItem: _yearIndex);

  int get _yearCount => widget.currentYear - _earliestYear + 2;

  int? get _month => _monthIndex == 0 ? null : _monthIndex;
  int? get _year => _yearIndex == 0 ? null : widget.currentYear - (_yearIndex - 1);

  @override
  void dispose() {
    _monthController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  /// Passing over a detent only redraws and ticks. Committing every item a
  /// flick sweeps past would fire the step's auto-advance on a year the member
  /// never stopped on.
  void _hover({int? monthIndex, int? yearIndex}) {
    setState(() {
      if (monthIndex != null) _monthIndex = monthIndex;
      if (yearIndex != null) _yearIndex = yearIndex;
    });
    HapticFeedback.selectionClick();
  }

  void _commit() => widget.onChanged(_month, _year);

  @override
  Widget build(BuildContext context) {
    final summary = switch ((_month, _year)) {
      (final int m, final int y) => '${_monthNames[m - 1]} $y',
      (final int m, null) => _monthNames[m - 1],
      (null, final int y) => '$y',
      _ => 'Ay ve yılı seç',
    };

    return AuroraCard(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Column(
        children: [
          SizedBox(
            height: kWheelItemExtent * 3,
            child: Stack(
              children: [
                // The band sits behind both wheels so the pair reads as one
                // control rather than two independent lists.
                Center(
                  child: Container(
                    height: kWheelItemExtent,
                    decoration: BoxDecoration(
                      color: widget.accent.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: widget.accent.withValues(alpha: .75)),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _Wheel(
                        key: monthWheelKey,
                        controller: _monthController,
                        itemExtent: kWheelItemExtent,
                        count: _monthNames.length + 1,
                        selectedIndex: _monthIndex,
                        labelAt: (index) => index == 0 ? '—' : _monthNames[index - 1],
                        semanticsLabel: 'Ay',
                        onHover: (index) => _hover(monthIndex: index),
                        onCommit: _commit,
                      ),
                    ),
                    Expanded(
                      child: _Wheel(
                        key: yearWheelKey,
                        controller: _yearController,
                        itemExtent: kWheelItemExtent,
                        count: _yearCount,
                        selectedIndex: _yearIndex,
                        labelAt: (index) =>
                            index == 0 ? '—' : '${widget.currentYear - (index - 1)}',
                        semanticsLabel: 'Yıl',
                        onHover: (index) => _hover(yearIndex: index),
                        onCommit: _commit,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            summary,
            style: AuroraText.body(
              size: 14,
              weight: FontWeight.w700,
              alpha: _month == null && _year == null ? .5 : 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _Wheel extends StatelessWidget {
  const _Wheel({
    super.key,
    required this.controller,
    required this.itemExtent,
    required this.count,
    required this.selectedIndex,
    required this.labelAt,
    required this.semanticsLabel,
    required this.onHover,
    required this.onCommit,
  });

  final FixedExtentScrollController controller;
  final double itemExtent;
  final int count;
  final int selectedIndex;
  final String Function(int index) labelAt;
  final String semanticsLabel;
  final ValueChanged<int> onHover;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticsLabel,
    child: NotificationListener<ScrollEndNotification>(
      // The answer is what the wheel came to rest on, not every detent a flick
      // swept past.
      onNotification: (_) {
        onCommit();
        return false;
      },
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: itemExtent,
        diameterRatio: 1.7,
        perspective: 0.004,
        overAndUnderCenterOpacity: .45,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: onHover,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: count,
          builder: (context, index) => GestureDetector(
            // Tapping a neighbour is faster than flicking for a one-step move.
            onTap: () => controller.animateToItem(
              index,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
            ),
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: Text(
                labelAt(index),
                style: AuroraText.body(
                  size: 16,
                  weight: index == selectedIndex ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
