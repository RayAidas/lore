import 'dart:async';
import 'dart:convert';

import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences-backed, device-local writing statistics.
///
/// Each novel is stored under a library-scoped key so overview totals never
/// combine unrelated libraries. Values are daily net character deltas.
final class SharedPreferencesWritingProgressRepository
    implements WritingProgressRepository {
  SharedPreferencesWritingProgressRepository();

  static const _keyPrefix = 'lore.writing.progress.';
  static const _schemaVersion = 2;

  final Map<String, Future<void>> _pending = {};

  String _key(LibraryId libraryId, NovelId novelId) =>
      '$_keyPrefix${libraryId.value}.${novelId.value}';

  String _legacyKey(NovelId novelId) => '$_keyPrefix${novelId.value}';

  String _libraryPrefix(LibraryId libraryId) =>
      '$_keyPrefix${libraryId.value}.';

  @override
  Future<Map<WritingDay, int>> loadDailyDeltas(
    LibraryId libraryId,
    NovelId novelId, {
    required WritingDay fromInclusive,
    required WritingDay toInclusive,
  }) async {
    if (fromInclusive.compareTo(toInclusive) > 0) return const {};
    final counts = await _readOrMigrateCounts(libraryId, novelId);
    return _withinRange(counts, fromInclusive, toInclusive);
  }

  @override
  Future<Map<WritingDay, int>> loadLibraryDailyDeltas(
    LibraryId libraryId, {
    required WritingDay fromInclusive,
    required WritingDay toInclusive,
  }) async {
    if (fromInclusive.compareTo(toInclusive) > 0) return const {};
    final preferences = await SharedPreferences.getInstance();
    final total = <WritingDay, int>{};
    for (final key in preferences.getKeys()) {
      Map<WritingDay, int>? counts;
      if (key.startsWith(_libraryPrefix(libraryId))) {
        counts = await _readCounts(key);
      }
      if (counts == null) continue;
      for (final entry in _withinRange(
        counts,
        fromInclusive,
        toInclusive,
      ).entries) {
        total.update(
          entry.key,
          (value) => value + entry.value,
          ifAbsent: () => entry.value,
        );
      }
    }
    return total;
  }

  @override
  Future<void> addDelta(
    LibraryId libraryId,
    NovelId novelId,
    WritingDay day,
    int delta,
  ) async {
    if (delta == 0) return;
    final key = _key(libraryId, novelId);
    final previous = _pending[key] ?? Future<void>.value();
    final current = _enqueueWrite(previous, libraryId, novelId, day, delta);
    _pending[key] = current;
    try {
      await current;
    } finally {
      if (identical(_pending[key], current)) _pending.remove(key);
    }
  }

  Future<void> _enqueueWrite(
    Future<void> previous,
    LibraryId libraryId,
    NovelId novelId,
    WritingDay day,
    int delta,
  ) async {
    await previous.catchError((Object _) {});
    final key = _key(libraryId, novelId);
    final counts = await _readOrMigrateCounts(libraryId, novelId);
    counts.update(day, (value) => value + delta, ifAbsent: () => delta);
    await _writeCounts(key, counts);
  }

  @override
  Future<void> pruneBefore(
    LibraryId libraryId,
    WritingDay cutoffExclusive,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    for (final key in preferences.getKeys()) {
      if (!key.startsWith(_libraryPrefix(libraryId))) continue;
      final counts = await _readCounts(key);
      counts.removeWhere((day, _) => day.compareTo(cutoffExclusive) < 0);
      await _writeCounts(key, counts);
    }
  }

  Map<WritingDay, int> _withinRange(
    Map<WritingDay, int> counts,
    WritingDay fromInclusive,
    WritingDay toInclusive,
  ) => Map.unmodifiable({
    for (final entry in counts.entries)
      if (entry.key.compareTo(fromInclusive) >= 0 &&
          entry.key.compareTo(toInclusive) <= 0)
        entry.key: entry.value,
  });

  Future<Map<WritingDay, int>> _readCounts(String key) async {
    final preferences = await SharedPreferences.getInstance();
    return _decode(preferences.getString(key), 'dailyDeltas', _schemaVersion);
  }

  Future<Map<WritingDay, int>> _readOrMigrateCounts(
    LibraryId libraryId,
    NovelId novelId,
  ) async {
    final key = _key(libraryId, novelId);
    final preferences = await SharedPreferences.getInstance();
    if (preferences.containsKey(key)) {
      return _decode(preferences.getString(key), 'dailyDeltas', _schemaVersion);
    }
    final legacy = await _readLegacyCounts(_legacyKey(novelId));
    if (legacy.isNotEmpty) {
      await _writeCounts(key, legacy);
    }
    return legacy;
  }

  Future<Map<WritingDay, int>> _readLegacyCounts(String key) async {
    final preferences = await SharedPreferences.getInstance();
    return _decode(preferences.getString(key), 'counts', 1);
  }

  Map<WritingDay, int> _decode(String? encoded, String field, int version) {
    if (encoded == null) return <WritingDay, int>{};
    try {
      final value = jsonDecode(encoded);
      if (value is! Map<String, Object?> || value['schemaVersion'] != version) {
        return <WritingDay, int>{};
      }
      final raw = value[field];
      if (raw is! Map<String, Object?>) return <WritingDay, int>{};
      final result = <WritingDay, int>{};
      raw.forEach((day, count) {
        if (count is! int) return;
        try {
          result[WritingDay.parse(day)] = count;
        } on FormatException {
          // Ignore malformed individual keys while retaining valid entries.
        }
      });
      return result;
    } on FormatException {
      return <WritingDay, int>{};
    }
  }

  Future<void> _writeCounts(String key, Map<WritingDay, int> counts) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = <String, int>{
      for (final entry in counts.entries)
        entry.key.toIso8601String(): entry.value,
    };
    await preferences.setString(
      key,
      jsonEncode({'schemaVersion': _schemaVersion, 'dailyDeltas': encoded}),
    );
  }
}
