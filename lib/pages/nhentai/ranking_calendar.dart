import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pica_comic/foundation/nhentai_ranking_store.dart';

/// Browsing a month/year is deliberately separate from selecting a date.
class NhentaiRankingCalendar extends StatefulWidget {
  const NhentaiRankingCalendar({
    super.key,
    required this.selectedDate,
    required this.today,
    required this.availableDates,
    required this.description,
  });

  final DateTime selectedDate;
  final DateTime today;
  final Map<String, bool> availableDates;
  final String description;

  @override
  State<NhentaiRankingCalendar> createState() => _RankingCalendarState();
}

class _RankingCalendarState extends State<NhentaiRankingCalendar> {
  late DateTime month;
  Offset drag = Offset.zero;
  Offset dragStart = Offset.zero;
  DateTime? lastWheel;
  double wheelDistance = 0;
  bool? horizontalWheel;

  DateTime get upper => DateTime(widget.today.year, widget.today.month);
  int get firstYear => [
        widget.today.year - 10,
        widget.selectedDate.year,
        ...widget.availableDates.keys.map((d) => int.parse(d.substring(0, 4))),
      ].reduce(math.min);

  @override
  void initState() {
    super.initState();
    month = DateTime(widget.selectedDate.year, widget.selectedDate.month);
  }

  void browse(int delta) {
    final target = DateTime(month.year, month.month + delta);
    final lower = DateTime(firstYear);
    setState(() {
      month = target.isAfter(upper)
          ? upper
          : target.isBefore(lower)
              ? lower
              : target;
    });
  }

  void endDrag(DragEndDetails details) {
    final x = drag.dx.abs(), y = drag.dy.abs();
    if (math.max(x, y) < 48) return;
    if (x > y * 1.25) {
      browse(drag.dx < 0 ? 12 : -12);
    } else if (y > x * 1.25) {
      browse(drag.dy < 0 ? 1 : -1);
    }
  }

  void startDrag(DragStartDetails details) {
    dragStart = details.globalPosition;
    drag = Offset.zero;
  }

  void updateDrag(DragUpdateDetails details) {
    drag = details.globalPosition - dragStart;
  }

  void onScroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      final now = DateTime.now();
      if (lastWheel != null &&
          now.difference(lastWheel!) < const Duration(milliseconds: 300)) {
        return;
      }
      final x = event.scrollDelta.dx, y = event.scrollDelta.dy;
      if (x.abs() <= y.abs() * 1.25 && y.abs() <= x.abs() * 1.25) return;
      final horizontal = x.abs() > y.abs();
      if (horizontalWheel != horizontal) wheelDistance = 0;
      horizontalWheel = horizontal;
      wheelDistance += horizontal ? x : y;
      if (wheelDistance.abs() >= 50) {
        browse((wheelDistance > 0 ? 1 : -1) * (horizontal ? 12 : 1));
        wheelDistance = 0;
        lastWheel = now;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selected = widget.selectedDate;
    final today =
        DateTime(widget.today.year, widget.today.month, widget.today.day);
    final leading = DateTime(month.year, month.month).weekday - 1;
    final count = DateTime(month.year, month.month + 1, 0).day;
    final rows = ((leading + count) / 7).ceil();
    Widget cell(int index) {
      final day = index - leading + 1;
      if (day < 1 || day > count) return const SizedBox(height: 48);
      final date = DateTime(month.year, month.month, day);
      final future = date.isAfter(today);
      final state = widget.availableDates[rankingDateKey(date)];
      final isSelected = DateUtils.isSameDay(selected, date);
      final isToday = DateUtils.isSameDay(today, date);
      final background = isSelected
          ? colors.primary
          : state != null
              ? colors.secondaryContainer
              : colors.surfaceContainerHighest;
      final foreground = isSelected
          ? colors.onPrimary
          : future
              ? colors.onSurface.withValues(alpha: 0.3)
              : state != null
                  ? colors.onSecondaryContainer
                  : colors.onSurfaceVariant;
      final label = '${date.year}年${date.month}月$day日，'
          '${future ? '未来日期，不可选' : state == null ? '无记录' : state ? '有记录' : '部分记录'}';
      return Semantics(
        selected: isSelected,
        enabled: !future,
        label: label,
        child: Tooltip(
          message: label,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Material(
              color: background,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                key: ValueKey('ranking-day-${rankingDateKey(date)}'),
                borderRadius: BorderRadius.circular(10),
                onTap: future ? null : () => Navigator.pop(context, date),
                child: SizedBox(
                  height: 48,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('$day',
                          style: TextStyle(
                              color: foreground,
                              decoration:
                                  isToday ? TextDecoration.underline : null)),
                      SizedBox(
                          height: 12,
                          child: state == null
                              ? null
                              : Text(
                                  state ? '●' : '△',
                                  style:
                                      TextStyle(fontSize: 9, color: foreground),
                                )),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
          child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Expanded(child: Text('选择归档日期')),
              IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
            ]),
            Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${selected.year} 年 ${selected.month} 月 ${selected.day} 日',
                  style: Theme.of(context).textTheme.headlineSmall,
                )),
            const SizedBox(height: 8),
            Align(
                alignment: Alignment.centerLeft,
                child: Text(widget.description,
                    style: Theme.of(context).textTheme.bodySmall)),
            const SizedBox(height: 12),
            Row(children: [
              IconButton(
                  key: const ValueKey('ranking-prev-month'),
                  tooltip: '上个月',
                  onPressed: month.isAfter(DateTime(firstYear))
                      ? () => browse(-1)
                      : null,
                  icon: const Icon(Icons.chevron_left)),
              Expanded(
                  child: DropdownButton<int>(
                key: const ValueKey('ranking-year'),
                value: month.year,
                isExpanded: true,
                items: [
                  for (var year = firstYear; year <= today.year; year++)
                    DropdownMenuItem(value: year, child: Text('$year 年'))
                ],
                onChanged: (year) {
                  if (year == null) return;
                  browse((year - month.year) * 12);
                },
              )),
              const SizedBox(width: 8),
              Expanded(
                  child: DropdownButton<int>(
                key: const ValueKey('ranking-month'),
                value: month.month,
                isExpanded: true,
                items: [
                  for (var m = 1; m <= 12; m++)
                    DropdownMenuItem(
                        value: m,
                        enabled: month.year < today.year || m <= today.month,
                        child: Text('$m 月'))
                ],
                onChanged: (value) {
                  if (value != null) browse(value - month.month);
                },
              )),
              IconButton(
                  key: const ValueKey('ranking-next-month'),
                  tooltip: '下个月',
                  onPressed: month.isBefore(upper) ? () => browse(1) : null,
                  icon: const Icon(Icons.chevron_right)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              for (final label in const ['一', '二', '三', '四', '五', '六', '日'])
                Expanded(child: Center(child: Text(label)))
            ]),
            const SizedBox(height: 8),
            Listener(
              onPointerSignal: onScroll,
              child: GestureDetector(
                key: const ValueKey('ranking-calendar-grid'),
                behavior: HitTestBehavior.opaque,
                dragStartBehavior: DragStartBehavior.down,
                onVerticalDragStart: startDrag,
                onVerticalDragUpdate: updateDrag,
                onVerticalDragEnd: endDrag,
                onHorizontalDragStart: startDrag,
                onHorizontalDragUpdate: updateDrag,
                onHorizontalDragEnd: endDrag,
                child: Table(children: [
                  for (var row = 0; row < rows; row++)
                    TableRow(children: [
                      for (var col = 0; col < 7; col++) cell(row * 7 + col)
                    ])
                ]),
              ),
            ),
            const SizedBox(height: 12),
            const Wrap(spacing: 16, runSpacing: 4, children: [
              Text('● 有记录'),
              Text('△ 部分记录'),
              Text('灰色：无记录'),
            ]),
            const SizedBox(height: 8),
            Text('上下滑动翻月 · 左右滑动翻年 · 下划线标记今天',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      )),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const ValueKey('ranking-return-today'),
              onPressed: () => Navigator.pop(context, today),
              child: Text('返回今天 · ${today.month} 月 ${today.day} 日'),
            )),
      ),
    ]);
  }
}
