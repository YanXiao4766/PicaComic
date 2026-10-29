import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/comic_source/comic_source.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/nhentai_ranking_archive.dart';
import 'package:pica_comic/foundation/nhentai_ranking_store.dart';
import 'package:pica_comic/network/cloudflare.dart';
import 'package:pica_comic/network/base_comic.dart';
import 'package:pica_comic/network/nhentai_network/nhentai_main_network.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/tools/translations.dart';

import 'ranking_calendar.dart';

class NhentaiRankingHistoryPage extends StatefulWidget {
  const NhentaiRankingHistoryPage(
      {super.key,
      required this.language,
      required this.title,
      required this.liveLoader,
      required this.category,
      required this.param,
      this.archive});

  final String language;
  final String title;
  final CategoryComicsLoader liveLoader;
  final String category;
  final String param;
  final NhentaiRankingArchive? archive;

  @override
  State<NhentaiRankingHistoryPage> createState() => _RankingHistoryPageState();
}

class _RankingHistoryPageState extends State<NhentaiRankingHistoryPage> {
  late final archive = widget.archive ?? NhentaiRankingArchive.instance;
  final instanceKey = UniqueKey();
  DateTime selected = DateUtils.dateOnly(DateTime.now());
  NhentaiSort sort = NhentaiSort.recent;
  int liveRevision = 0;

  static const labels = {
    NhentaiSort.recent: '最近',
    NhentaiSort.popularToday: '热门 | 今天',
    NhentaiSort.popularWeek: '热门 | 一周',
    NhentaiSort.popularMonth: '热门 | 本月',
    NhentaiSort.popularAll: '热门 | 所有时间',
  };

  bool get supportsHistory => NhentaiRankingArchive.rankings.contains(sort);
  bool get historyMode => supportsHistory && !isToday;
  String get date => rankingDateKey(selected);
  bool get isToday => DateUtils.isSameDay(selected, DateTime.now());

  @override
  void initState() {
    super.initState();
    unawaited(archive.initialize());
  }

  void selectDate(DateTime value) {
    setState(() {
      selected = DateUtils.dateOnly(value);
      if (isToday) liveRevision++;
    });
    if (isToday) unawaited(archive.collectToday());
  }

  Future<void> showCalendar() async {
    Widget picker() => AnimatedBuilder(
        animation: archive,
        builder: (_, __) => NhentaiRankingCalendar(
              selectedDate: selected,
              today: DateTime.now(),
              availableDates: archive.ready
                  ? archive.store
                      .availableDates(widget.language, sort.queryValue)
                  : {},
              description: '${widget.title} · ${labels[sort]!.tl} · 本机归档',
            ));
    final DateTime? result;
    if (MediaQuery.sizeOf(context).width >= 600) {
      result = await showDialog<DateTime>(
          context: context,
          builder: (_) => Dialog(child: SizedBox(width: 420, child: picker())));
    } else {
      result = await showModalBottomSheet<DateTime>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          enableDrag: false,
          builder: (_) => ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .95),
                child: SafeArea(top: false, child: picker()),
              ));
    }
    if (mounted && result != null) selectDate(result);
  }

  void retry({bool refresh = false}) {
    final record = archive.ready
        ? archive.store.read(date, widget.language, sort.queryValue)
        : null;
    final error = record?.lastError ?? archive.connectionError ?? '';
    final challenge = CloudflareException.fromString(error) ??
        (error.contains('验证')
            ? CloudflareException(NhentaiNetwork().baseUrl)
            : null);
    if (challenge != null) {
      passCloudflare(
          challenge, () => unawaited(archive.collectToday(refresh: refresh)));
    } else {
      unawaited(archive.collectToday(refresh: refresh));
    }
  }

  Widget dateControls() => Material(
        color: Theme.of(context).colorScheme.secondaryContainer,
        elevation: 4,
        borderRadius: BorderRadius.circular(18),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
              tooltip: '上一天',
              onPressed: () => selectDate(
                  DateTime(selected.year, selected.month, selected.day - 1)),
              icon: const Icon(Icons.chevron_left)),
          TextButton(
              onPressed: showCalendar,
              child: Text(
                '${selected.month.toString().padLeft(2, '0')}/${selected.day.toString().padLeft(2, '0')}',
              )),
          IconButton(
              tooltip: '下一天',
              onPressed: isToday
                  ? null
                  : () => selectDate(DateTime(
                      selected.year, selected.month, selected.day + 1)),
              icon: const Icon(Icons.chevron_right)),
        ]),
      );

  Widget header(NhentaiRankingRecord? record) {
    final capturing = archive.isCapturing(date, widget.language, sort);
    String status;
    if (!supportsHistory) {
      status = '实时列表 · 不支持日期回看';
    } else if (isToday) {
      status = '实时列表 · 今天 · 在线分页加载';
    } else if (record != null && record.ids.isNotEmpty) {
      final time = record.capturedAt;
      status =
          '${isToday ? '' : '历史记录 · '}${selected.month} 月 ${selected.day} 日 · '
          '${record.complete ? '已归档 ${record.ids.length} 项' : '部分记录 ${record.ids.length}/100'} · '
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} 更新';
      final briefs = archive.store.readBriefs(record.ids);
      final hidden =
          briefs.values.where((comic) => isBlocked(comic) != null).length;
      if (hidden > 0) status += ' · 当前可见 ${record.ids.length - hidden} 项';
      if (record.lastError != null) status += ' · 最近更新未成功';
    } else {
      status = '${selected.month} 月 ${selected.day} 日 · 无归档';
    }
    if (supportsHistory && (capturing || (isToday && archive.collecting))) {
      status += ' · 正在保存今日榜单';
    }
    final error = archive.initializationError ??
        record?.lastError ??
        (isToday ? archive.connectionError : null);
    return SliverToBoxAdapter(
        child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final option in labels.entries)
            OptionChip(
              text: option.value.tl,
              isSelected: sort == option.key,
              onTap: () => setState(() => sort = option.key),
            ),
        ]),
        const Divider(),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(status, style: Theme.of(context).textTheme.bodySmall)),
        if (supportsHistory && error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              Expanded(
                  child: Tooltip(
                      message: error,
                      child: Text(
                        error.contains('Cloudflare') || error.contains('验证')
                            ? '站点需要验证，请点击重试完成验证'
                            : isToday
                                ? '自动归档未成功，不影响在线列表加载'
                                : '归档更新未成功，已有记录仍可查看',
                        style: Theme.of(context).textTheme.bodySmall,
                      ))),
              if (isToday)
                TextButton(
                    onPressed: archive.collecting ? null : retry,
                    child: const Text('重试')),
            ]),
          ),
        const SizedBox(height: 8),
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: archive,
        builder: (_, __) {
          final record = historyMode && archive.ready
              ? archive.store.read(date, widget.language, sort.queryValue)
              : null;
          // Other boards finishing must not reset this list or its scroll position.
          final revision =
              '${record?.capturedAt.toIso8601String()}/${record?.ids.length}';
          return Scaffold(
            appBar: Appbar(title: Text(widget.title), actions: [
              if (supportsHistory && isToday)
                IconButton(
                  tooltip: '手动更新今日榜单',
                  onPressed: archive.collecting
                      ? null
                      : () {
                          setState(() => liveRevision++);
                          retry(refresh: true);
                        },
                  icon: const Icon(Icons.refresh),
                ),
            ]),
            body: historyMode
                ? _ArchivedComicsList(
                    key: ValueKey(
                        '$instanceKey/$date/${sort.queryValue}/$revision'),
                    identity: '$instanceKey/$date/${sort.queryValue}/$revision',
                    archive: archive,
                    record: record,
                    header: header(record),
                    bottomRightFooter: dateControls(),
                    language: widget.language,
                    onToday: () => selectDate(DateTime.now()),
                    isToday: isToday,
                  )
                : _LiveLanguageComicsList(
                    key: ValueKey(
                        '$instanceKey/live/$date/${sort.queryValue}/$liveRevision'),
                    identity:
                        '$instanceKey/live/$date/${sort.queryValue}/$liveRevision',
                    header: header(null),
                    bottomRightFooter: supportsHistory ? dateControls() : null,
                    loader: (page) => widget.liveLoader(
                        widget.category, widget.param, [sort.value], page),
                  ),
          );
        },
      );
}

class _ArchivedComicsList extends ComicsPage<NhentaiComicBrief> {
  const _ArchivedComicsList(
      {super.key,
      required this.identity,
      required this.archive,
      required this.record,
      required this.header,
      required this.bottomRightFooter,
      required this.language,
      required this.onToday,
      required this.isToday});

  final String identity;
  final NhentaiRankingArchive archive;
  final NhentaiRankingRecord? record;
  final String language;
  final VoidCallback onToday;
  final bool isToday;
  @override
  final Widget header;
  @override
  final Widget bottomRightFooter;
  @override
  String get sourceKey => 'nhentai';
  @override
  String get tag => identity;
  @override
  String? get title => null;

  @override
  Future<Res<List<NhentaiComicBrief>>> getComics(int page) async {
    final ids = List<String>.of(record?.ids ?? const []);
    if (appdata.appSettings.fullyHideBlockedWorks) {
      final briefs = archive.store.readBriefs(ids);
      ids.removeWhere(
          (id) => briefs[id] != null && isBlocked(briefs[id]!) != null);
    }
    final maxPage =
        math.max(1, (ids.length / NhentaiRankingArchive.pageSize).ceil());
    final start = (page - 1) * NhentaiRankingArchive.pageSize;
    if (start >= ids.length) return Res(const [], subData: maxPage);
    final comics = await archive.loadComics(
        ids.sublist(start,
            math.min(start + NhentaiRankingArchive.pageSize, ids.length)),
        language);
    return Res(comics, subData: maxPage);
  }

  @override
  Widget buildEmptyView(BuildContext context) {
    final hasArchive = record?.ids.isNotEmpty ?? false;
    return Center(
        child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 180),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.calendar_month_outlined, size: 48),
        const SizedBox(height: 16),
        Text(hasArchive
            ? '已有归档，当前内容被屏蔽规则隐藏'
            : isToday
                ? '今天还没有保存的榜单'
                : '这一天没有保存的榜单'),
        const SizedBox(height: 8),
        Text(isToday ? '联网后自动采集，也可以点击上方刷新按钮重试。' : '可在日历中选择有底色的日期，或返回今天。',
            textAlign: TextAlign.center),
        if (!isToday) TextButton(onPressed: onToday, child: const Text('返回今天')),
      ]),
    ));
  }
}

class _LiveLanguageComicsList extends ComicsPage<BaseComic> {
  const _LiveLanguageComicsList(
      {super.key,
      required this.identity,
      required this.header,
      required this.loader,
      this.bottomRightFooter});
  final String identity;
  final Future<Res<List<BaseComic>>> Function(int) loader;
  @override
  final Widget header;
  @override
  final Widget? bottomRightFooter;
  @override
  String get sourceKey => 'nhentai';
  @override
  String get tag => identity;
  @override
  String? get title => null;
  @override
  Future<Res<List<BaseComic>>> getComics(int page) => loader(page);
}
