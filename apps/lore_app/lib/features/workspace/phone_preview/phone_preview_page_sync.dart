import 'package:flutter/widgets.dart';

/// 翻页模式下「编辑器 → 预览页号」的**单向**同步：编辑器滚动百分比映射到页号
/// `round(fraction × (N-1))`，预览跳到该页。
///
/// 单向（翻预览不反推编辑器）：连续滚动 ↔ 离散翻页双向映射会让编辑器滚动时被
/// `onPageChanged` 回推抖动，故只做编辑器→预览。页数 N 由 [pageCount] 在同步时
/// 实时读取（随正文 / 机型变化）。
class PhonePreviewPageSync {
  // 字段私有、构造公开：跨文件用 `target`/`pageCount` 具名参数传入，故不能用
  // `this._x` 初始化形式（会使参数名变私有）。
  PhonePreviewPageSync({
    required PageController target,
    required ValueGetter<int> pageCount,
  }) : _target = target, // ignore: prefer_initializing_formals
       _pageCount = pageCount; // ignore: prefer_initializing_formals

  final PageController _target;
  final ValueGetter<int> _pageCount;

  ScrollController? _source;
  bool _syncing = false;

  /// 绑定源控制器（编辑器）；传 `null` 解绑。同一实例重复绑定为 no-op。绑定后
  /// 做一次初始同步：延一帧、有限重试，等两侧挂载到位。
  void bind(ScrollController? source) {
    if (identical(source, _source)) return;
    _source?.removeListener(_syncSourceToPage);
    _source = source;
    source?.addListener(_syncSourceToPage);
    if (source != null) {
      _scheduleInitialSync(_initialSyncRetries);
    }
  }

  static const int _initialSyncRetries = 3;

  void _scheduleInitialSync(int retriesLeft) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final source = _source;
      if (source == null || !source.hasClients || !_target.hasClients) {
        if (retriesLeft > 0) _scheduleInitialSync(retriesLeft - 1);
        return;
      }
      _syncSourceToPage();
    });
  }

  void dispose() {
    _source?.removeListener(_syncSourceToPage);
    _source = null;
  }

  void _syncSourceToPage() {
    if (_syncing) return;
    final source = _source;
    if (source == null || !source.hasClients || !_target.hasClients) return;
    final sMax = source.position.maxScrollExtent;
    if (sMax <= 0) return;
    final n = _pageCount();
    if (n <= 1) return;
    final page = ((source.position.pixels / sMax) * (n - 1)).round().clamp(
      0,
      n - 1,
    );
    if (_target.page?.round() == page) return;
    _syncing = true;
    _target.jumpToPage(page);
    _syncing = false;
  }
}
