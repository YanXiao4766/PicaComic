import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/comic_source/built_in/nhentai.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/nhentai_ranking_archive.dart';
import 'package:pica_comic/foundation/nhentai_ranking_store.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/nhentai_network/models.dart';
import 'package:pica_comic/network/nhentai_network/nhentai_main_network.dart'
    show NhentaiSort;
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/nhentai/ranking_history_page.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    open.overrideFor(
        OperatingSystem.windows, () => DynamicLibrary.open('winsqlite3.dll'));
  }
  late NhentaiRankingStore store;
  late NhentaiRankingArchive archive;
  late List<String> settings;
  late List<ComicSource> sources;
  late List<String> blockedWords;
  var liveCalls = 0;
  var archiveProbes = 0;
  final today = DateUtils.dateOnly(DateTime.now());
  NhentaiComicBrief comic(int id) =>
      NhentaiComicBrief('测试漫画 $id', '', '$id', '中文', const []);

  setUp(() {
    settings = List.of(appdata.settings);
    sources = List.of(ComicSource.sources);
    blockedWords = List.of(appdata.blockingKeyword);
    appdata.blockingKeyword = [];
    ComicSource.sources = [nhentai];
    appdata.settings[25] = '0';
    appdata.settings[44] = '1';
    appdata.settings[50] = 'cn';
    appdata.settings[72] = '0';
    appdata.settings[73] = '0';
    liveCalls = 0;
    archiveProbes = 0;
    store = NhentaiRankingStore(sqlite3.openInMemory());
    store.commit(
        language: 'chinese',
        ranking: 'popular-today',
        startedAt: today,
        finishedAt: today,
        comics: List.generate(100, (i) => comic(i + 1)),
        complete: true);
    for (final language in NhentaiRankingArchive.languages) {
      for (final ranking in NhentaiRankingArchive.rankings) {
        if (language == 'chinese' && ranking == NhentaiSort.popularToday) {
          continue;
        }
        store.commit(
            language: language,
            ranking: ranking.queryValue,
            startedAt: today,
            finishedAt: today,
            comics: [comic(8000)],
            complete: true);
      }
    }
    store.commit(
        language: 'chinese',
        ranking: 'popular-today',
        startedAt: today.subtract(const Duration(days: 1)),
        finishedAt: today.subtract(const Duration(days: 1)),
        comics: List.generate(100, (i) => comic(201 + i)),
        complete: true);
    store.commit(
        language: 'chinese',
        ranking: 'popular-today',
        startedAt: DateTime(today.year, today.month, today.day - 2),
        finishedAt: DateTime(today.year, today.month, today.day - 2),
        comics: List.generate(40, (i) => comic(401 + i)),
        complete: true);
    archive = NhentaiRankingArchive(
        store: store,
        probe: () async {
          archiveProbes++;
          return false;
        },
        loader: (_, __, ___) async =>
            throw StateError('must use local archive'));
  });

  tearDown(() {
    archive.dispose();
    store.close();
    appdata.settings = settings;
    ComicSource.sources = sources;
    appdata.blockingKeyword = blockedWords;
  });

  Future<void> openPage(
    WidgetTester tester, {
    Future<Res<List<BaseComic>>> Function(int)? popularLoader,
    bool settlePopular = true,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: App.navigatorKey,
      home: NhentaiRankingHistoryPage(
        language: 'chinese',
        title: '中文',
        category: '中文',
        param: '/language/chinese',
        archive: archive,
        liveLoader: (_, __, options, page) async {
          liveCalls++;
          if (options.first.isNotEmpty && popularLoader != null) {
            return popularLoader(page);
          }
          return Res<List<BaseComic>>(
            List.generate(20, (i) => comic(900 + (page - 1) * 20 + i)),
            subData: 50,
          );
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('热门 | 今天'));
    if (settlePopular) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets(
      'today loads online with original page count and keeps date controls',
      (tester) async {
    await openPage(tester);
    expect(liveCalls, 2);
    expect(find.textContaining('已归档 100 项'), findsNothing);
    expect(find.text('测试漫画 900'), findsOneWidget);
    expect(find.text('测试漫画 1'), findsNothing);
    expect(find.text('1/50'), findsOneWidget);
    final jump = tester.getRect(find.text('1/50'));
    final previous = tester.getRect(find.byTooltip('上一天'));
    expect(jump.bottom, lessThan(previous.top));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'jump uses local page count; changing date resets to first archive page',
      (tester) async {
    await openPage(tester);
    await tester.tap(find.byTooltip('上一天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1/5'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '3');
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();
    expect(find.text('3/5'), findsOneWidget);
    expect(find.text('测试漫画 241'), findsOneWidget);
    await tester.tap(find.byTooltip('上一天'));
    await tester.pumpAndSettle();
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('测试漫画 401'), findsOneWidget);
    expect(liveCalls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'empty dates keep calendar available; realtime mode hides date controls',
      (tester) async {
    await openPage(tester);
    await tester.tap(find.byTooltip('上一天'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('上一天'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('上一天'));
    await tester.pumpAndSettle();
    expect(find.text('这一天没有保存的榜单'), findsOneWidget);
    expect(find.text('0/0'), findsOneWidget);
    expect(find.byTooltip('上一天'), findsOneWidget);
    await tester.tap(find.text('最近'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('上一天'), findsNothing);
    expect(liveCalls, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('blocked first page does not hide later visible archive entries',
      (tester) async {
    appdata.settings[83] = '1';
    store.commit(
        language: 'chinese',
        ranking: 'popular-today',
        startedAt: DateTime(today.year, today.month, today.day - 1),
        finishedAt: DateTime(today.year, today.month, today.day - 1),
        complete: true,
        comics: List.generate(
            100,
            (i) => NhentaiComicBrief(i < 20 ? 'blocked $i' : 'visible $i', '',
                '${i + 1}', '中文', const [])));
    appdata.blockingKeyword = ['blocked'];
    await openPage(tester);
    await tester.tap(find.byTooltip('上一天'));
    await tester.pumpAndSettle();
    expect(find.text('visible 20'), findsOneWidget);
    expect(find.text('1/4'), findsOneWidget);
    expect(find.textContaining('当前可见 80 项'), findsOneWidget);
    expect(
        store
            .read(
                rankingDateKey(
                    DateTime(today.year, today.month, today.day - 1)),
                'chinese',
                'popular-today')!
            .ids
            .length,
        100);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paginated list mode keeps local jump and date controls usable',
      (tester) async {
    appdata.settings[25] = '1';
    appdata.settings[64] = '1';
    await openPage(tester);
    await tester.tap(find.byTooltip('上一天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1/5').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '3');
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();
    expect(find.text('测试漫画 241'), findsOneWidget);
    await tester.tap(find.byTooltip('上一天'));
    await tester.pumpAndSettle();
    expect(find.text('测试漫画 401'), findsOneWidget);
    expect(find.text('1/2'), findsWidgets);
    expect(liveCalls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'next-day arrow returns to online loading even with a saved today',
      (tester) async {
    await openPage(tester);
    await tester.tap(find.byTooltip('上一天'));
    await tester.pumpAndSettle();
    expect(find.text('测试漫画 201'), findsOneWidget);
    expect(liveCalls, 2);
    await tester.tap(find.byTooltip('下一天'));
    await tester.pumpAndSettle();
    expect(liveCalls, 3);
    expect(find.text('测试漫画 900'), findsOneWidget);
    expect(find.text('1/50'), findsOneWidget);
    expect(find.text('测试漫画 1'), findsNothing);
    expect(find.textContaining('历史记录'), findsNothing);
    expect(archiveProbes, 0);
  });

  testWidgets(
      'calendar return-today reloads online instead of showing saved IDs',
      (tester) async {
    await openPage(tester);
    await tester.tap(find.byTooltip('上一天'));
    await tester.pumpAndSettle();
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final dateLabel =
        '${yesterday.month.toString().padLeft(2, '0')}/${yesterday.day.toString().padLeft(2, '0')}';
    await tester.tap(find.text(dateLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ranking-return-today')));
    await tester.pumpAndSettle();
    expect(liveCalls, 3);
    expect(find.text('测试漫画 900'), findsOneWidget);
    expect(find.text('1/50'), findsOneWidget);
  });

  testWidgets(
      'today online failure never silently falls back to saved today IDs',
      (tester) async {
    await openPage(tester,
        popularLoader: (_) async => const Res.error('online unavailable'));
    expect(find.text('online unavailable'), findsOneWidget);
    expect(find.text('测试漫画 1'), findsNothing);
    expect(find.byTooltip('上一天'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'late online response cannot replace a selected past-date archive',
      (tester) async {
    final response = Completer<Res<List<BaseComic>>>();
    await openPage(tester,
        popularLoader: (_) => response.future, settlePopular: false);
    await tester.tap(find.byTooltip('上一天'));
    await tester.pumpAndSettle();
    expect(find.text('测试漫画 201'), findsOneWidget);
    response.complete(Res<List<BaseComic>>([comic(9999)], subData: 50));
    await tester.pumpAndSettle();
    expect(find.text('测试漫画 201'), findsOneWidget);
    expect(find.text('测试漫画 9999'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'top-right manual update refreshes online list and forces archive update',
      (tester) async {
    await openPage(tester);
    expect(archiveProbes, 0);
    await tester.tap(find.byTooltip('手动更新今日榜单'));
    await tester.pumpAndSettle();
    expect(liveCalls, 3);
    expect(archiveProbes, 1);
    expect(find.text('测试漫画 900'), findsOneWidget);
    expect(find.textContaining('不影响在线列表加载'), findsOneWidget);
    expect(
        store
            .read(rankingDateKey(today), 'chinese', 'popular-today')!
            .ids
            .first,
        '1');
    expect(tester.takeException(), isNull);
  });
}
