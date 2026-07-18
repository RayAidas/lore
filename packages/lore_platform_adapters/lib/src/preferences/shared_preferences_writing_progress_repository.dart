import 'dart:async';
import 'dart:convert';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 基于 [SharedPreferences] 的设备本地写作进度持久化。
///
/// 每部小说一个 key（`lore.writing.progress.<novelId>`），值为 JSON：
/// `{"schemaVersion":1,"counts":{"<yyyy-MM-dd>":<int>}}`。日期键统一 UTC，
/// 与 [SharedPreferencesWorkspaceSessionRepository] 的容错约定一致。
///
/// [addDelta] 通过 per-key Future 链串行化，避免并发 read-modify-write
/// 后写覆盖先写、丢失字数增量（连续击键/多 tab 同时写作场景）。
final class SharedPreferencesWritingProgressRepository
    implements WritingProgressRepository {
  SharedPreferencesWritingProgressRepository();

  static const _keyPrefix = 'lore.writing.progress.';
  static const _schemaVersion = 1;

  final Map<String, Future<void>> _pending = {};

  String _key(NovelId novelId) => '$_keyPrefix${novelId.value}';

  String _dayKey(DateTime utc) {
    final y = utc.year.toString().padLeft(4, '0');
    final m = utc.month.toString().padLeft(2, '0');
    final d = utc.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  Future<int> loadToday(NovelId novelId, DateTime todayUtc) async {
    final counts = await _readCounts(_key(novelId));
    return counts[_dayKey(todayUtc)] ?? 0;
  }

  @override
  Future<void> addDelta(NovelId novelId, DateTime todayUtc, int delta) async {
    if (delta == 0) {
      return;
    }
    final key = _key(novelId);
    final day = _dayKey(todayUtc);
    // 串行化同一 key 的写入：排队等待前一次完成后再读-改-写，
    // 避免并发请求读到同一旧值、互相覆盖。
    final previous = _pending[key] ?? Future<void>.value();
    final current = _enqueueWrite(previous, key, day, delta);
    _pending[key] = current;
    try {
      await current;
    } finally {
      if (identical(_pending[key], current)) {
        _pending.remove(key);
      }
    }
  }

  Future<void> _enqueueWrite(
    Future<void> previous,
    String key,
    String day,
    int delta,
  ) async {
    // 吞掉前一次的失败，避免失败的 Future 永久阻塞队列。
    await previous.catchError((Object _) {});
    final counts = await _readCounts(key);
    counts[day] = (counts[day] ?? 0) + delta;
    await _writeCounts(key, counts);
  }

  @override
  Future<void> pruneBefore(DateTime cutoffUtc) async {
    final cutoff = _dayKey(cutoffUtc);
    final preferences = await SharedPreferences.getInstance();
    final keys = preferences.getKeys().where((k) => k.startsWith(_keyPrefix));
    for (final key in keys) {
      final counts = await _readCounts(key);
      counts.removeWhere((day, _) => day.compareTo(cutoff) < 0);
      await _writeCounts(key, counts);
    }
  }

  Future<Map<String, int>> _readCounts(String key) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(key);
    if (encoded == null) {
      return <String, int>{};
    }
    try {
      final value = jsonDecode(encoded);
      if (value is! Map<String, Object?> ||
          value['schemaVersion'] != _schemaVersion) {
        return <String, int>{};
      }
      final rawCounts = value['counts'];
      if (rawCounts is! Map<String, Object?>) {
        return <String, int>{};
      }
      final counts = <String, int>{};
      rawCounts.forEach((day, raw) {
        if (raw is int) {
          counts[day] = raw;
        }
      });
      return counts;
    } on FormatException {
      return <String, int>{};
    }
  }

  Future<void> _writeCounts(String key, Map<String, int> counts) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      key,
      jsonEncode({'schemaVersion': _schemaVersion, 'counts': counts}),
    );
  }
}
