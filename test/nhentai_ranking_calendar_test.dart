import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/foundation/nhentai_ranking_store.dart';
import 'package:pica_comic/pages/nhentai/ranking_calendar.dart';

void main() {
  final today = DateTime(2026, 10, 29);
  Future<void> openPicker(WidgetTester tester, {DateTime? selected}) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        final result = await showDialog<DateTime>(
                            context: context,
                            builder: (_) => Dialog(
                                child: SizedBox(
                                    width: 420,
                                    child: NhentaiRankingCalendar(
                                      selectedDate: selected ?? today,
                                      today: today,
                                      availableDates: const {
                                        '2026-10-28': true,
                                        '2026-10-27': false
                                      },
                                      description: '中文 · 热门 | 今天',
                                    ))));
                        if (context.mounted && result != null) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content:
                                  Text('picked:${rankingDateKey(result)}')));
                        }
                      },
                      child: const Text('打开日历')),
                ))));
    await tester.tap(find.text('打开日历'));
    await tester.pumpAndSettle();
  }

  int year(WidgetTester tester) => tester
      .widget<DropdownButton<int>>(find.byKey(const ValueKey('ranking-year')))
      .value!;
  int month(WidgetTester tester) => tester
      .widget<DropdownButton<int>>(find.byKey(const ValueKey('ranking-month')))
      .value!;
  final grid = find.byKey(const ValueKey('ranking-calendar-grid'));

  testWidgets(
      'up/down browse months; right/left browse years without selecting',
      (tester) async {
    await openPicker(tester);
    await tester.drag(grid, const Offset(0, 130));
    await tester.pumpAndSettle();
    expect(month(tester), 9);
    await tester.drag(grid, const Offset(0, -130));
    await tester.pumpAndSettle();
    expect(month(tester), 10);
    await tester.drag(grid, const Offset(130, 0));
    await tester.pumpAndSettle();
    expect(year(tester), 2025);
    await tester.drag(grid, const Offset(-130, 0));
    await tester.pumpAndSettle();
    expect(year(tester), 2026);
    expect(find.text('2026 年 10 月 29 日'), findsOneWidget);
    expect(find.textContaining('picked:'), findsNothing);
  });

  testWidgets(
      'future dates and forward navigation at current month are disabled',
      (tester) async {
    await openPicker(tester);
    expect(
        tester
            .widget<InkWell>(
                find.byKey(const ValueKey('ranking-day-2026-10-30')))
            .onTap,
        isNull);
    expect(
        tester
            .widget<IconButton>(
                find.byKey(const ValueKey('ranking-next-month')))
            .onPressed,
        isNull);
    await tester.drag(grid, const Offset(-130, 0));
    await tester.pumpAndSettle();
    expect(year(tester), 2026);
    expect(month(tester), 10);
  });

  testWidgets('month navigation crosses year boundaries', (tester) async {
    await openPicker(tester, selected: DateTime(2026, 1, 15));
    await tester.drag(grid, const Offset(0, 130));
    await tester.pumpAndSettle();
    expect(year(tester), 2025);
    expect(month(tester), 12);
    await tester.drag(grid, const Offset(0, -130));
    await tester.pumpAndSettle();
    expect(year(tester), 2026);
    expect(month(tester), 1);
  });

  testWidgets('a tap commits a date', (tester) async {
    await openPicker(tester);
    await tester.tap(find.byKey(const ValueKey('ranking-day-2026-10-28')));
    await tester.pumpAndSettle();
    expect(find.text('picked:2026-10-28'), findsOneWidget);
  });

  testWidgets('return-today commits today', (tester) async {
    await openPicker(tester, selected: DateTime(2026, 10, 28));
    await tester.tap(find.byKey(const ValueKey('ranking-return-today')));
    await tester.pumpAndSettle();
    expect(find.text('picked:2026-10-29'), findsOneWidget);
  });

  testWidgets('small or diagonal drags do not switch months or select a day',
      (tester) async {
    await openPicker(tester);
    await tester.drag(grid, const Offset(30, 0));
    await tester.pumpAndSettle();
    expect(month(tester), 10);
    await tester.drag(grid, const Offset(100, 100));
    await tester.pumpAndSettle();
    expect(year(tester), 2026);
    expect(month(tester), 10);
    expect(find.textContaining('picked:'), findsNothing);
  });

  testWidgets('six-week month fits a narrow phone with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
      data: const MediaQueryData(
          size: Size(320, 640), textScaler: TextScaler.linear(1.3)),
      child: Scaffold(
          body: NhentaiRankingCalendar(
              selectedDate: DateTime(2026, 3, 15),
              today: today,
              availableDates: const {},
              description: '中文 · 热门 | 今天')),
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester
        .ensureVisible(find.byKey(const ValueKey('ranking-return-today')));
    expect(tester.takeException(), isNull);
  });
}
