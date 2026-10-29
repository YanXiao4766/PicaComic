import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/nhentai_network/nhentai_main_network.dart';
import 'package:pica_comic/network/res.dart';

import 'nhentai_ranking_store.dart';

typedef RankingPageLoader = Future<Res<NhentaiRankingPage>> Function(
    String language, NhentaiSort ranking, int page);

/// Nine independent boards; at most two boards and one page per board in flight.
class NhentaiRankingArchive extends ChangeNotifier {
  NhentaiRankingArchive({
    NhentaiRankingStore? store,
    RankingPageLoader? loader,
    Future<bool> Function()? probe,
    DateTime Function()? now,
    this.retryDelay = const Duration(seconds: 2),
    this.pageDelay = const Duration(milliseconds: 300),
  })  : _store = store,
        _loader = loader ?? NhentaiNetwork().getRankingPage,
        _probe = probe ?? NhentaiNetwork().isReachable,
        _now = now ?? DateTime.now;

  static final instance = NhentaiRankingArchive();
  static const languages = ['chinese', 'japanese', 'english'];
  static const rankings = [
    NhentaiSort.popularToday,
    NhentaiSort.popularWeek,
    NhentaiSort.popularMonth,
  ];
  static const pageSize = 20;

  NhentaiRankingStore? _store;
  NhentaiRankingStore get store => _store!;
  final RankingPageLoader _loader;
  final Future<bool> Function() _probe;
  final DateTime Function() _now;
  final Duration retryDelay;
  final Duration pageDelay;
  Future<void>? _initializing;
  Future<void>? _batch;
  Timer? _timer;
  bool _foreground = true;
  bool _started = false;
  bool _disposed = false;
  bool? _reachable;
  bool _checking = false;
  String? _sessionDate;
  final Set<String> _active = {};
  final Map<String, Future<NhentaiComicBrief?>> _briefRequests = {};
  String? initializationError;
  String? connectionError;

  bool get ready => _store != null;
  bool get collecting => _batch != null;

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    try {
      _store ??=
          NhentaiRankingStore.open('${App.dataPath}/nhentai_rankings.db');
    } catch (e, s) {
      initializationError = '无法打开榜单归档：$e';
      LogManager.addLog(LogLevel.error, 'nhentai archive', '$e\n$s');
    }
    _notify();
  }

  Future<void> start() async {
    if (_started || _disposed || ComicSource.find('nhentai') == null) return;
    _started = true;
    await initialize();
    if (!ready || _disposed) return;
    // A lightweight HEAD probe detects offline -> reachable transitions. It does
    // not re-fetch nine failed boards every minute or open verification windows.
    _timer =
        Timer.periodic(const Duration(minutes: 1), (_) => checkConnection());
    await collectToday();
  }

  void setForeground(bool foreground) {
    _foreground = foreground;
    if (foreground && _started) unawaited(checkConnection(resumed: true));
  }

  Future<void> checkConnection({bool resumed = false}) async {
    if (!_foreground || _disposed || _checking || collecting || !ready) return;
    _checking = true;
    try {
      final dateChanged = _sessionDate != rankingDateKey(_now());
      if (dateChanged) {
        await collectToday();
        return;
      }
      if (!_hasMissingBoards()) return;
      final reachable = await _probe();
      final recovered = reachable && _reachable == false;
      _reachable = reachable;
      if (recovered || (resumed && reachable && _hasMissingBoards())) {
        await collectToday();
      }
    } catch (e) {
      _reachable = false;
    } finally {
      _checking = false;
    }
  }

  bool _hasMissingBoards() {
    return languages.any((language) =>
        rankings.any((ranking) => _needsCapture(language, ranking)));
  }

  Future<void> collectToday({bool refresh = false}) async {
    await initialize();
    if (!ready || _disposed) return;
    if (_batch != null) return _batch!;
    final future = _collectBatch(refresh);
    _batch = future;
    _notify();
    try {
      await future;
    } catch (e, s) {
      connectionError = '采集失败：$e';
      LogManager.addLog(LogLevel.error, 'nhentai archive', '$e\n$s');
    } finally {
      _batch = null;
      _notify();
    }
  }

  Future<void> _collectBatch(bool refresh) async {
    _sessionDate = rankingDateKey(_now());
    final tasks = <(String, NhentaiSort)>[
      for (final language in languages)
        for (final ranking in rankings)
          if (refresh || _needsCapture(language, ranking)) (language, ranking),
    ];
    // Opening/resuming the app checks local data before even probing the site.
    // Only an explicit manual update is allowed to refresh complete boards.
    if (tasks.isEmpty) return;
    _reachable = await _probe();
    if (!_reachable!) {
      connectionError = '暂时无法连接 nhentai，联网恢复后自动补采';
      return;
    }
    connectionError = null;
    var next = 0;
    Future<void> worker() async {
      while (next < tasks.length && !_disposed && _foreground) {
        final (language, ranking) = tasks[next++];
        try {
          await capture(language, ranking, refresh: refresh);
        } catch (e, s) {
          LogManager.addLog(LogLevel.error, 'nhentai archive', '$e\n$s');
          connectionError = '部分榜单保存失败，可重试';
        }
      }
    }

    await Future.wait([worker(), worker()]);
  }

  bool _needsCapture(String language, NhentaiSort ranking) {
    final record =
        store.read(rankingDateKey(_now()), language, ranking.queryValue);
    return record == null || !record.complete;
  }

  bool isCapturing(String date, String language, NhentaiSort ranking) =>
      _active.contains('$date/$language/${ranking.queryValue}');

  /// Public for explicit retry and deterministic collector tests.
  Future<void> capture(String language, NhentaiSort ranking,
      {bool refresh = false}) async {
    await initialize();
    if (!ready || _disposed) return;
    final started = _now();
    if (!refresh &&
        store
                .read(rankingDateKey(started), language, ranking.queryValue)
                ?.complete ==
            true) {
      return;
    }
    final taskKey =
        '${rankingDateKey(started)}/$language/${ranking.queryValue}';
    if (!_active.add(taskKey)) return;
    _notify();
    final comics = <String, NhentaiComicBrief>{};
    var complete = false;
    var reachedEnd = false;
    String? error;
    try {
      for (var page = 1; page <= 100; page++) {
        Res<NhentaiRankingPage>? result;
        for (var attempt = 0; attempt < 3; attempt++) {
          try {
            result = await _loader(language, ranking, page);
          } catch (e) {
            result = Res.error(e.toString());
          }
          if (!result.error ||
              result.errorMessageWithoutNull.contains('CloudflareException')) {
            break;
          }
          if (attempt < 2) await Future.delayed(retryDelay * (attempt + 1));
        }
        if (result!.error) {
          error = result.errorMessageWithoutNull;
          break;
        }
        final before = comics.length;
        for (final comic in result.data.comics) {
          if (RegExp(r'^\d+$').hasMatch(comic.id)) {
            comics.putIfAbsent(comic.id, () => comic);
          }
          if (comics.length == 100) break;
        }
        reachedEnd = result.data.reachedEnd;
        if (comics.length >= 100 || reachedEnd) {
          complete = true;
          break;
        }
        if (comics.length == before) {
          error = '榜单分页未返回新的编号';
          break;
        }
        if (_disposed || !_foreground) {
          error = '应用已暂停，下次打开时继续补采';
          break;
        }
        await Future.delayed(pageDelay);
      }
      if (!complete && error == null) error = '榜单未能收集到 100 个有效编号';
      store.commit(
        language: language,
        ranking: ranking.queryValue,
        startedAt: started,
        finishedAt: _now(),
        comics: comics.values.toList(),
        complete: complete,
        reachedEnd: reachedEnd,
        error: error,
      );
      if (error != null) connectionError = error;
    } finally {
      _active.remove(taskKey);
      _notify();
    }
  }

  Future<List<NhentaiComicBrief>> loadComics(
      List<String> ids, String language) async {
    final cached = store.readBriefs(ids);
    final missing = ids.where((id) => !cached.containsKey(id)).toList();
    var next = 0;
    Future<void> worker() async {
      while (next < missing.length) {
        final id = missing[next++];
        final request = _briefRequests.putIfAbsent(id, () => _restoreBrief(id));
        final comic = await request;
        _briefRequests.remove(id);
        if (comic != null) cached[id] = comic;
      }
    }

    await Future.wait([worker(), worker()]);
    return [
      for (final id in ids)
        cached[id] ?? NhentaiComicBrief('该漫画暂不可访问', '', id, language, const []),
    ];
  }

  Future<NhentaiComicBrief?> _restoreBrief(String id) async {
    final res = await NhentaiNetwork().getComicInfo(id);
    if (res.error) return null;
    final info = res.data;
    final brief = NhentaiComicBrief(info.title, info.cover, id, '',
        info.tags.values.expand((tags) => tags).toList());
    store.saveBriefs([brief]);
    return brief;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
