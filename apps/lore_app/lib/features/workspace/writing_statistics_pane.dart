import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';

import 'workspace_controller.dart';

class WritingStatisticsPane extends StatefulWidget {
  const WritingStatisticsPane({required this.controller, super.key});

  final WorkspaceController controller;

  @override
  State<WritingStatisticsPane> createState() => _WritingStatisticsPaneState();
}

class _WritingStatisticsPaneState extends State<WritingStatisticsPane> {
  late WritingDay _month;
  WritingDay? _selectedDay;
  _StatisticsData? _data;
  bool _loading = true;
  Timer? _refreshTimer;
  int _loadGeneration = 0;

  WorkspaceController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _month = WritingDay.fromDateTime(DateTime.now()).firstDayOfMonth;
    controller.addListener(_scheduleReload);
    _reload();
  }

  @override
  void dispose() {
    controller.removeListener(_scheduleReload);
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _scheduleReload() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 350), _reload);
  }

  Future<void> _reload({WritingDay? month}) async {
    final targetMonth = month ?? _month;
    final library = controller.loadLibraryWritingStatistics(month: targetMonth);
    if (library == null) return;
    final path = controller.activeDocument?.relativePath;
    final novelId = path == null ? null : controller.novelIdForPath(path);
    final generation = ++_loadGeneration;
    try {
      final values = await Future.wait([
        library,
        if (novelId != null)
          controller.loadNovelWritingStatistics(novelId, month: targetMonth)!,
      ]);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _month = targetMonth;
        _data = _StatisticsData(
          library: values.first,
          novel: values.length == 2 ? values[1] : null,
          novelTitle: novelId == null
              ? null
              : controller.novels
                    .where((novel) => novel.metadata.id == novelId)
                    .firstOrNull
                    ?.metadata
                    .title,
        );
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
      });
    }
  }

  void _changeMonth(int delta) {
    setState(() => _selectedDay = null);
    unawaited(_reload(month: _month.addDays(delta * 32).firstDayOfMonth));
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      return _loading
          ? const Center(child: CircularProgressIndicator())
          : const Center(child: Text('无法加载写作统计'));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 28),
      children: [
        _PaneHeader(month: _month, onChangeMonth: _changeMonth),
        const SizedBox(height: 18),
        _SectionLabel(icon: Icons.auto_graph_rounded, label: '当前书库'),
        const SizedBox(height: 8),
        _StatisticsBand(statistics: data.library),
        const SizedBox(height: 22),
        _CalendarHeader(month: _month),
        const SizedBox(height: 8),
        _WritingCalendar(
          statistics: data.library,
          month: _month,
          selectedDay: _selectedDay,
          onSelected: (day) => setState(() => _selectedDay = day),
        ),
        if (_selectedDay != null) ...[
          const SizedBox(height: 10),
          _DayDetail(
            day: _selectedDay!,
            library: _deltaFor(data.library, _selectedDay!),
            novel: data.novel == null
                ? null
                : _deltaFor(data.novel!, _selectedDay!),
            novelTitle: data.novelTitle,
          ),
        ],
        if (data.novel case final novel?) ...[
          const SizedBox(height: 24),
          _SectionLabel(
            icon: Icons.menu_book_outlined,
            label: data.novelTitle == null ? '当前小说' : data.novelTitle!,
          ),
          const SizedBox(height: 8),
          _StatisticsBand(statistics: novel),
        ],
      ],
    );
  }

  int _deltaFor(WritingStatistics statistics, WritingDay day) =>
      statistics.monthDays
          .where((item) => item.day == day)
          .firstOrNull
          ?.netDelta ??
      0;
}

final class _StatisticsData {
  const _StatisticsData({
    required this.library,
    required this.novel,
    required this.novelTitle,
  });

  final WritingStatistics library;
  final WritingStatistics? novel;
  final String? novelTitle;
}

class _PaneHeader extends StatelessWidget {
  const _PaneHeader({required this.month, required this.onChangeMonth});

  final WritingDay month;
  final ValueChanged<int> onChangeMonth;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.bar_chart_rounded,
            size: 19,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('写作统计', style: Theme.of(context).textTheme.titleMedium),
              Text(
                '${month.year} 年 ${month.month} 月',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        _MonthButton(
          tooltip: '上个月',
          icon: Icons.chevron_left_rounded,
          onPressed: () => onChangeMonth(-1),
        ),
        const SizedBox(width: 2),
        _MonthButton(
          tooltip: '下个月',
          icon: Icons.chevron_right_rounded,
          onPressed: () => onChangeMonth(1),
        ),
      ],
    );
  }
}

class _MonthButton extends StatelessWidget {
  const _MonthButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(width: 30, height: 30, child: Icon(icon, size: 18)),
      ),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.labelLarge),
    ],
  );
}

class _StatisticsBand extends StatelessWidget {
  const _StatisticsBand({required this.statistics});

  final WritingStatistics statistics;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Metric(
              label: '今日',
              value: _formatDelta(statistics.todayNetDelta),
            ),
          ),
          _VerticalRule(color: colorScheme.outlineVariant),
          Expanded(
            child: _Metric(
              label: '本周',
              value: _formatDelta(statistics.weekNetDelta),
            ),
          ),
          _VerticalRule(color: colorScheme.outlineVariant),
          Expanded(
            child: _Metric(
              label: '连续',
              value: '${statistics.currentStreakDays} 天',
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalRule extends StatelessWidget {
  const _VerticalRule({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 30, child: VerticalDivider(width: 1, color: color));
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      const SizedBox(height: 3),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader({required this.month});

  final WritingDay month;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text('每日产出', style: Theme.of(context).textTheme.labelLarge),
      const Spacer(),
      Text(
        '${month.month} 月',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}

class _WritingCalendar extends StatelessWidget {
  const _WritingCalendar({
    required this.statistics,
    required this.month,
    required this.selectedDay,
    required this.onSelected,
  });

  final WritingStatistics statistics;
  final WritingDay month;
  final WritingDay? selectedDay;
  final ValueChanged<WritingDay> onSelected;

  @override
  Widget build(BuildContext context) {
    final firstWeekday = DateTime.utc(month.year, month.month, 1).weekday;
    final values = {
      for (final item in statistics.monthDays) item.day: item.netDelta,
    };
    return Column(
      children: [
        Row(
          children: [
            for (final label in const ['一', '二', '三', '四', '五', '六', '日'])
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisExtent: 58,
          children: [
            for (var index = 1; index < firstWeekday; index++) const SizedBox(),
            for (var date = 1; date <= month.lastDayOfMonth.day; date++)
              _CalendarDay(
                day: WritingDay(month.year, month.month, date),
                delta: values[WritingDay(month.year, month.month, date)],
                selected:
                    selectedDay == WritingDay(month.year, month.month, date),
                onSelected: onSelected,
              ),
          ],
        ),
      ],
    );
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.day,
    required this.delta,
    required this.selected,
    required this.onSelected,
  });

  final WritingDay day;
  final int? delta;
  final bool selected;
  final ValueChanged<WritingDay> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final today = WritingDay.fromDateTime(DateTime.now());
    final isToday = day == today;
    final value = delta ?? 0;
    final countColor = value > 0
        ? colorScheme.primary
        : value < 0
        ? colorScheme.error
        : colorScheme.onSurfaceVariant;
    final dateColor = isToday || selected
        ? colorScheme.primary
        : colorScheme.onSurface;
    final fill = selected
        ? colorScheme.primaryContainer
        : isToday
        ? colorScheme.primaryContainer.withValues(alpha: 0.62)
        : value > 0
        ? colorScheme.primaryContainer.withValues(alpha: 0.35)
        : value < 0
        ? colorScheme.errorContainer.withValues(alpha: 0.48)
        : colorScheme.surfaceContainerLow;
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${day.month}月${day.day}日，码字 ${delta == null ? '无记录' : _formatDelta(value)}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1.5, vertical: 2),
        child: Material(
          color: fill,
          borderRadius: BorderRadius.circular(7),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onSelected(day),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${day.day}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: dateColor,
                      fontSize: 13,
                      fontWeight: isToday || selected
                          ? FontWeight.w700
                          : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          delta == null ? '-' : _formatDelta(value),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: countColor,
                                fontSize: 10,
                                fontWeight: value == 0
                                    ? FontWeight.w400
                                    : FontWeight.w700,
                              ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DayDetail extends StatelessWidget {
  const _DayDetail({
    required this.day,
    required this.library,
    required this.novel,
    required this.novelTitle,
  });

  final WritingDay day;
  final int library;
  final int? novel;
  final String? novelTitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          Text(
            '${day.month} 月 ${day.day} 日',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const Spacer(),
          Text('书库 ${_formatDelta(library)}'),
          if (novel != null) ...[
            const SizedBox(width: 10),
            Text('${novelTitle ?? '小说'} ${_formatDelta(novel!)}'),
          ],
        ],
      ),
    );
  }
}

String _formatDelta(int value) {
  final sign = value > 0
      ? '+'
      : value < 0
      ? '-'
      : '';
  final abs = value.abs();
  if (abs >= 10000) return '$sign${(abs / 10000).toStringAsFixed(1)}w';
  if (abs >= 1000) return '$sign${(abs / 1000).toStringAsFixed(1)}k';
  return '$sign$abs';
}
