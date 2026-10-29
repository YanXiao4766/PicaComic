import 'dart:convert';

import 'package:pica_comic/network/nhentai_network/models.dart';
import 'package:sqlite3/sqlite3.dart';

String rankingDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

class NhentaiRankingRecord {
  final String date;
  final String language;
  final String ranking;
  final List<String> ids;
  final DateTime startedAt;
  final DateTime capturedAt;
  final bool complete;
  final bool reachedEnd;
  final String? lastError;
  final DateTime lastAttemptAt;

  const NhentaiRankingRecord({
    required this.date,
    required this.language,
    required this.ranking,
    required this.ids,
    required this.startedAt,
    required this.capturedAt,
    required this.complete,
    required this.reachedEnd,
    this.lastError,
    required this.lastAttemptAt,
  });

  factory NhentaiRankingRecord.fromRow(Row row) => NhentaiRankingRecord(
        date: row['date'] as String,
        language: row['language'] as String,
        ranking: row['ranking'] as String,
        ids: List<String>.from(jsonDecode(row['ids'] as String)),
        startedAt: DateTime.parse(row['started_at'] as String),
        capturedAt: DateTime.parse(row['captured_at'] as String),
        complete: row['complete'] == 1,
        reachedEnd: row['reached_end'] == 1,
        lastError: row['last_error'] as String?,
        lastAttemptAt: DateTime.parse(row['last_attempt_at'] as String),
      );
}

/// Permanent archives, deliberately outside the disposable image cache.
/// Each board and its brief metadata are committed in one SQLite transaction.
class NhentaiRankingStore {
  NhentaiRankingStore(this.database) {
    database.execute('PRAGMA busy_timeout = 5000');
    database.execute('''CREATE TABLE IF NOT EXISTS nh_rankings (
      date TEXT NOT NULL, language TEXT NOT NULL, ranking TEXT NOT NULL,
      ids TEXT NOT NULL, started_at TEXT NOT NULL, captured_at TEXT NOT NULL,
      timezone_offset INTEGER NOT NULL, complete INTEGER NOT NULL,
      reached_end INTEGER NOT NULL, last_error TEXT, last_attempt_at TEXT NOT NULL,
      PRIMARY KEY (date, language, ranking)
    )''');
    database.execute('''CREATE TABLE IF NOT EXISTS nh_briefs (
      id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL, cover TEXT NOT NULL,
      language TEXT NOT NULL, tags TEXT NOT NULL
    )''');
    database.execute('PRAGMA user_version = 1');
  }

  final Database database;

  factory NhentaiRankingStore.open(String path) =>
      NhentaiRankingStore(sqlite3.open(path));

  NhentaiRankingRecord? read(String date, String language, String ranking) {
    final rows = database.select(
      'SELECT * FROM nh_rankings WHERE date = ? AND language = ? AND ranking = ?',
      [date, language, ranking],
    );
    return rows.isEmpty ? null : NhentaiRankingRecord.fromRow(rows.first);
  }

  Map<String, bool> availableDates(String language, String ranking) => {
        for (final row in database.select(
          'SELECT date, complete FROM nh_rankings '
          'WHERE language = ? AND ranking = ? AND ids != ?',
          [language, ranking, '[]'],
        ))
          row['date'] as String: row['complete'] == 1,
      };

  void saveBriefs(Iterable<NhentaiComicBrief> comics) {
    final statement = database.prepare(
      'INSERT OR REPLACE INTO nh_briefs (id, title, cover, language, tags) '
      'VALUES (?, ?, ?, ?, ?)',
    );
    try {
      for (final comic in comics) {
        statement.execute([
          comic.id,
          comic.title,
          comic.cover,
          comic.lang,
          jsonEncode(comic.tags),
        ]);
      }
    } finally {
      statement.dispose();
    }
  }

  Map<String, NhentaiComicBrief> readBriefs(List<String> ids) {
    if (ids.isEmpty) return {};
    final rows = database.select(
      'SELECT * FROM nh_briefs WHERE id IN (${List.filled(ids.length, '?').join(',')})',
      ids,
    );
    return {
      for (final row in rows)
        row['id'] as String: NhentaiComicBrief(
          row['title'] as String,
          row['cover'] as String,
          row['id'] as String,
          row['language'] as String,
          List<String>.from(jsonDecode(row['tags'] as String)),
        ),
    };
  }

  /// A failed refresh may update its error, but never replace a complete board.
  void commit({
    required String language,
    required String ranking,
    required DateTime startedAt,
    required DateTime finishedAt,
    required List<NhentaiComicBrief> comics,
    required bool complete,
    bool reachedEnd = false,
    String? error,
  }) {
    final date = rankingDateKey(startedAt);
    final old = read(date, language, ranking);
    database.execute('BEGIN IMMEDIATE');
    try {
      saveBriefs(comics);
      if (!complete &&
          old != null &&
          (old.complete || old.ids.length > comics.length)) {
        database.execute(
          'UPDATE nh_rankings SET last_error = ?, last_attempt_at = ? '
          'WHERE date = ? AND language = ? AND ranking = ?',
          [error, finishedAt.toIso8601String(), date, language, ranking],
        );
      } else {
        database.execute('''INSERT OR REPLACE INTO nh_rankings
          (date, language, ranking, ids, started_at, captured_at, timezone_offset,
           complete, reached_end, last_error, last_attempt_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''', [
          date,
          language,
          ranking,
          jsonEncode(comics.map((c) => c.id).toList()),
          startedAt.toIso8601String(),
          finishedAt.toIso8601String(),
          startedAt.timeZoneOffset.inMinutes,
          complete ? 1 : 0,
          reachedEnd ? 1 : 0,
          error,
          finishedAt.toIso8601String(),
        ]);
      }
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }

  void close() => database.dispose();
}
