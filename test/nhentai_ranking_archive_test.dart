import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/foundation/nhentai_ranking_archive.dart';
import 'package:pica_comic/foundation/nhentai_ranking_store.dart';
import 'package:pica_comic/network/nhentai_network/nhentai_main_network.dart';
import 'package:pica_comic/network/res.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

NhentaiComicBrief brief(int id, {String prefix = '漫画'}) => NhentaiComicBrief(
    '$prefix $id', 'https://example.test/$id.jpg', '$id', '中文', const []);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    open.overrideFor(
        OperatingSystem.windows, () => DynamicLibrary.open('winsqlite3.dll'));
  }

  late NhentaiRankingStore store;
  final date = DateTime(2026, 10, 29, 9, 42);
  const ranking = NhentaiSort.popularToday;
  setUp(() => store = NhentaiRankingStore(sqlite3.openInMemory()));
  tearDown(() => store.close());

  void save(List<NhentaiComicBrief> comics,
      {bool complete = true,
      String language = 'chinese',
      String rank = 'popular-today',
      DateTime? at,
      String? error}) {
    store.commit(
        language: language,
        ranking: rank,
        startedAt: at ?? date,
        finishedAt: at ?? date,
        comics: comics,
        complete: complete,
        error: error);
  }

  NhentaiRankingArchive collector(RankingPageLoader loader,
      {Future<bool> Function()? probe, DateTime Function()? now}) {
    final archive = NhentaiRankingArchive(
        store: store,
        loader: loader,
        probe: probe ?? () async => true,
        now: now ?? () => date,
        retryDelay: Duration.zero,
        pageDelay: Duration.zero);
    addTearDown(archive.dispose);
    return archive;
  }

  test(
      'persists ordered IDs, briefs and independent date/language/ranking keys',
      () {
    save([brief(5), brief(2), brief(8)]);
    save([brief(99)], language: 'english');
    save([brief(77)], rank: 'popular-week');
    save([brief(66)], at: DateTime(2026, 10, 28));
    expect(store.read('2026-10-29', 'chinese', 'popular-today')!.ids,
        ['5', '2', '8']);
    expect(store.read('2026-10-29', 'english', 'popular-today')!.ids, ['99']);
    expect(store.read('2026-10-29', 'chinese', 'popular-week')!.ids, ['77']);
    expect(store.readBriefs(['5'])['5']!.title, '漫画 5');
    expect(store.availableDates('chinese', 'popular-today').keys,
        unorderedEquals(['2026-10-28', '2026-10-29']));
  });

  test(
      'latest successful refresh replaces today, failures preserve old success',
      () {
    save([brief(1), brief(2)]);
    save([brief(3), brief(4)], at: date.add(const Duration(hours: 1)));
    save([brief(9)], complete: false, error: 'offline');
    final record = store.read('2026-10-29', 'chinese', 'popular-today')!;
    expect(record.ids, ['3', '4']);
    expect(record.complete, true);
    expect(record.lastError, 'offline');
    expect(record.capturedAt.hour, 10);
    save([brief(8)], at: date.add(const Duration(hours: 2)));
    expect(store.read('2026-10-29', 'chinese', 'popular-today')!.lastError,
        isNull);
  });

  test(
      'partial archives are marked; wholly failed boards are not available dates',
      () {
    save([brief(1)], complete: false, error: 'timeout');
    save([], complete: false, language: 'japanese', error: 'offline');
    expect(store.availableDates('chinese', 'popular-today'),
        {'2026-10-29': false});
    expect(store.availableDates('japanese', 'popular-today'), isEmpty);
    save([], complete: false, error: 'offline');
    expect(store.read('2026-10-29', 'chinese', 'popular-today')!.ids, ['1']);
  });

  test('metadata and board roll back together if a transaction fails', () {
    save([brief(1)]);
    store.database
        .execute('''CREATE TRIGGER reject_brief BEFORE INSERT ON nh_briefs
      WHEN NEW.id = '999' BEGIN SELECT RAISE(ABORT, 'test failure'); END''');
    expect(() => save([brief(2), brief(999)]), throwsA(isA<SqliteException>()));
    expect(store.read('2026-10-29', 'chinese', 'popular-today')!.ids, ['1']);
    expect(store.readBriefs(['2']), isEmpty);
  });

  test('a reopened database restores history without fetching current rankings',
      () {
    final directory =
        Directory.systemTemp.createTempSync('pica-nh-ranking-test-');
    final path = '${directory.path}${Platform.pathSeparator}rankings.db';
    final original = NhentaiRankingStore.open(path);
    original.commit(
        language: 'chinese',
        ranking: 'popular-today',
        startedAt: date,
        finishedAt: date,
        comics: [brief(20), brief(10)],
        complete: true);
    original.close();
    final reopened = NhentaiRankingStore.open(path);
    expect(reopened.read('2026-10-29', 'chinese', 'popular-today')!.ids,
        ['20', '10']);
    expect(reopened.readBriefs(['20'])['20']!.cover,
        'https://example.test/20.jpg');
    reopened.close();
    File(path).deleteSync();
    directory.deleteSync();
  });

  test('collector follows pages, keeps first occurrence and stops at 100 IDs',
      () async {
    final requested = <int>[];
    final archive = collector((language, sort, page) async {
      expect(language, 'chinese');
      expect(sort, ranking);
      requested.add(page);
      return Res(NhentaiRankingPage(
          List.generate(30, (i) => brief((page - 1) * 25 + i + 1)),
          reachedEnd: false));
    });
    await archive.capture('chinese', ranking);
    final record = store.read('2026-10-29', 'chinese', ranking.queryValue)!;
    expect(requested, [1, 2, 3, 4]);
    expect(record.ids, List.generate(100, (i) => '${i + 1}'));
    expect(record.complete, true);
  });

  test('a confirmed short final page is a complete archive with actual count',
      () async {
    final archive = collector((_, __, ___) async =>
        Res(NhentaiRankingPage([brief(1), brief(2)], reachedEnd: true)));
    await archive.capture('chinese', ranking);
    final record = store.read('2026-10-29', 'chinese', ranking.queryValue)!;
    expect(record.ids.length, 2);
    expect(record.complete, true);
    expect(record.reachedEnd, true);
  });

  test('an interrupted first capture saves partial IDs and retries only twice',
      () async {
    var failures = 0;
    final archive = collector((_, __, page) async {
      if (page == 1) {
        return Res(NhentaiRankingPage([brief(1)], reachedEnd: false));
      }
      failures++;
      return const Res.error('offline');
    });
    await archive.capture('chinese', ranking);
    final record = store.read('2026-10-29', 'chinese', ranking.queryValue)!;
    expect(failures, 3);
    expect(record.ids, ['1']);
    expect(record.complete, false);
  });

  test('verification failure stops retries without opening a UI', () async {
    var calls = 0;
    final archive = collector((_, __, ___) async {
      calls++;
      return const Res.error('CloudflareException: https://example.test/');
    });
    await archive.capture('chinese', ranking);
    expect(calls, 1);
    expect(store.availableDates('chinese', ranking.queryValue), isEmpty);
  });

  test('repeated pagination is stopped instead of spinning indefinitely',
      () async {
    var calls = 0;
    final archive = collector((_, __, ___) async {
      calls++;
      return Res(NhentaiRankingPage([brief(1)], reachedEnd: false));
    });
    await archive.capture('chinese', ranking);
    expect(calls, 2);
    expect(store.read('2026-10-29', 'chinese', ranking.queryValue)!.complete,
        false);
  });

  test(
      'nine boards use at most two workers; overlapping launches are coalesced',
      () async {
    var running = 0, maxRunning = 0, calls = 0;
    final archive = collector((_, __, ___) async {
      running++;
      calls++;
      if (running > maxRunning) maxRunning = running;
      await Future<void>.delayed(const Duration(milliseconds: 1));
      running--;
      return Res(NhentaiRankingPage([brief(calls)], reachedEnd: true));
    });
    await Future.wait([
      archive.collectToday(refresh: true),
      archive.collectToday(refresh: true)
    ]);
    expect(calls, 9);
    expect(maxRunning, 2);
    for (final language in NhentaiRankingArchive.languages) {
      for (final ranking in NhentaiRankingArchive.rankings) {
        expect(store.read('2026-10-29', language, ranking.queryValue)!.complete,
            true);
      }
    }
  });

  test('offline launch fills missing same-day boards after reconnect',
      () async {
    var online = false, calls = 0;
    final archive = collector((_, __, ___) async {
      calls++;
      return Res(NhentaiRankingPage([brief(2)], reachedEnd: true));
    }, probe: () async => online);
    await archive.collectToday();
    expect(calls, 0);
    online = true;
    await archive.checkConnection();
    expect(calls, 9);
    expect(store.read('2026-10-29', 'chinese', 'popular-today')!.ids, ['2']);
    await archive.checkConnection();
    expect(calls, 9);
  });

  test('existing complete today skips requests and even the connectivity probe',
      () async {
    for (final language in NhentaiRankingArchive.languages) {
      for (final ranking in NhentaiRankingArchive.rankings) {
        save([brief(1)], language: language, rank: ranking.queryValue);
      }
    }
    var calls = 0, probes = 0;
    final archive = collector((_, __, ___) async {
      calls++;
      return Res(NhentaiRankingPage([brief(2)], reachedEnd: true));
    }, probe: () async {
      probes++;
      return true;
    });
    await archive.collectToday();
    await archive.collectToday();
    await archive.checkConnection(resumed: true);
    await archive.capture('chinese', ranking);
    expect(calls, 0);
    expect(probes, 0);
    expect(store.read('2026-10-29', 'chinese', 'popular-today')!.ids, ['1']);
    await archive.collectToday(refresh: true);
    expect(calls, 9);
    expect(probes, 1);
    expect(store.read('2026-10-29', 'chinese', 'popular-today')!.ids, ['2']);
  });

  test('automatic collection fills only the missing or partial board',
      () async {
    for (final language in NhentaiRankingArchive.languages) {
      for (final ranking in NhentaiRankingArchive.rankings) {
        if (language == 'japanese' && ranking == NhentaiSort.popularMonth) {
          continue;
        }
        save([brief(1)],
            language: language,
            rank: ranking.queryValue,
            complete:
                !(language == 'english' && ranking == NhentaiSort.popularWeek));
      }
    }
    final requested = <String>[];
    final archive = collector((language, sort, _) async {
      requested.add('$language/${sort.queryValue}');
      return Res(NhentaiRankingPage([brief(2)], reachedEnd: true));
    });
    await archive.collectToday();
    expect(requested,
        unorderedEquals(['japanese/popular-month', 'english/popular-week']));
    expect(store.read('2026-10-29', 'chinese', 'popular-today')!.ids, ['1']);
    await archive.collectToday();
    expect(requested.length, 2);
  });

  test(
      'failed manual update preserves existing data and does not trigger automatic overwrite',
      () async {
    for (final language in NhentaiRankingArchive.languages) {
      for (final ranking in NhentaiRankingArchive.rankings) {
        save([brief(1)], language: language, rank: ranking.queryValue);
      }
    }
    var calls = 0;
    final archive = collector((_, __, ___) async {
      calls++;
      return const Res.error('offline');
    }, probe: () async => throw StateError('existing data must not probe'));
    await archive.capture('chinese', ranking, refresh: true);
    expect(calls, 3);
    expect(store.read('2026-10-29', 'chinese', ranking.queryValue)!.lastError,
        'offline');
    await archive.collectToday();
    await archive.checkConnection(resumed: true);
    expect(calls, 3);
    expect(store.read('2026-10-29', 'chinese', ranking.queryValue)!.ids, ['1']);
  });

  test('cross-day resume collects the new day without modifying yesterday',
      () async {
    var now = date;
    var calls = 0;
    final archive = collector((_, __, ___) async {
      calls++;
      return Res(NhentaiRankingPage([brief(calls)], reachedEnd: true));
    }, now: () => now);
    await archive.collectToday();
    expect(calls, 9);
    final oldIds = store.read('2026-10-29', 'chinese', 'popular-today')!.ids;
    now = DateTime(2026, 10, 30);
    await archive.checkConnection(resumed: true);
    expect(calls, 18);
    expect(store.read('2026-10-30', 'chinese', 'popular-today'), isNotNull);
    expect(store.read('2026-10-29', 'chinese', 'popular-today')!.ids, oldIds);
  });

  test('capture crossing midnight stays on its start date', () async {
    var now = DateTime(2026, 12, 31, 23, 59);
    final archive = collector((_, __, ___) async {
      now = DateTime(2027, 1, 1, 0, 1);
      return Res(NhentaiRankingPage([brief(1)], reachedEnd: true));
    }, now: () => now);
    await archive.capture('chinese', ranking);
    expect(
        store
            .read('2026-12-31', 'chinese', ranking.queryValue)!
            .capturedAt
            .year,
        2027);
    expect(store.read('2027-01-01', 'chinese', ranking.queryValue), isNull);
  });

  test('loading briefs uses archived order, not the SQL result order',
      () async {
    save([brief(1), brief(2), brief(3)]);
    final archive =
        collector((_, __, ___) async => throw StateError('must not fetch'));
    await archive.initialize();
    expect(
        (await archive.loadComics(['3', '1', '2'], 'chinese')).map((c) => c.id),
        ['3', '1', '2']);
  });

  String gallery(int id) => '<div class="gallery" data-tags="29963">'
      '<a href="/g/$id/"><img src="https://example.test/$id.jpg"></a>'
      '<div class="caption">Title $id</div></div>';

  test('parser rejects verification/empty/unrecognized pages', () {
    final network = NhentaiNetwork();
    expect(
        network.parseRankingPage('<html>Just a moment</html>', 1).error, true);
    expect(
        network
            .parseRankingPage('<div class="index-container"></div>', 1)
            .error,
        true);
    expect(
        network
            .parseRankingPage(
                '<div id="challenge-stage"></div>'
                '<div class="index-container">${gallery(1)}</div>',
                1)
            .error,
        true);
  });

  test(
      'parser detects next and last pages without mixing URL digits into page count',
      () {
    final network = NhentaiNetwork();
    final first = network.parseRankingPage(
        '<div class="index-container">${gallery(1)}</div>'
        '<section class="pagination"><a class="last" href="/language/chinese/?page=8">8</a></section>',
        1);
    expect(first.error, false);
    expect(first.data.reachedEnd, false);
    final last = network.parseRankingPage(
        '<div class="index-container">${gallery(2)}</div>'
        '<section class="pagination"><a href="?page=7">7</a></section>',
        8);
    expect(last.data.reachedEnd, true);
    final next = network.parseRankingPage(
        '<div class="index-container">${gallery(3)}</div>'
        '<section class="pagination"><a class="next" href="?page=2">Next</a></section>',
        1);
    expect(next.data.reachedEnd, false);
  });
}
