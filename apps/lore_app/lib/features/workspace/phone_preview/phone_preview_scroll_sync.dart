import 'package:flutter/widgets.dart';

/// 双向滚动同步：把两个 [ScrollController] 的滚动位置按百分比互相映射。
///
/// 用于手机预览（目标 [target]，固定）与编辑器（源 [source]，随活动文档切换）
/// 的滚动同步。两侧内容高度不同，按 `pixels / maxScrollExtent` 的百分比映射可
/// 对齐「阅读位置」而非像素。
///
/// - [bind] 切换源控制器（活动文档变化时）；传 `null` 解绑。
/// - `_syncing` 标志阻断「A 跳转 → B 监听 → B 跳转 → A 监听」的回环。
/// - 任一控制器未挂载（`hasClients` 为假）时跳过，避免访问 position 抛异常。
class PhonePreviewScrollSync {
  // 字段私有、构造公开：用 `: _target = target` 而非 `this._target` 初始化形式，
  // 否则具名参数名会变成私有的 `_target`、跨文件无法传入。
  PhonePreviewScrollSync({required ScrollController target})
    // ignore: prefer_initializing_formals
    : _target = target {
    _target.addListener(_syncTargetToSource);
  }

  /// 目标控制器（预览侧），固定不变。
  final ScrollController _target;

  /// 当前源控制器（编辑器侧），可随活动文档切换。
  ScrollController? _source;

  /// 同步进行中标志：跳转另一侧时置位，阻断回环。
  bool _syncing = false;

  /// 绑定源控制器；传 `null` 解绑。同一实例重复绑定为 no-op。绑定后做一次初始
  /// 同步：延一帧，等目标滚动视图挂载到位再按源位置对齐；若仍未挂载则有限重试，
  /// 避免「打开预览落在 0」的空同步。
  void bind(ScrollController? source) {
    if (identical(source, _source)) return;
    _source?.removeListener(_syncSourceToTarget);
    _source = source;
    source?.addListener(_syncSourceToTarget);
    if (source != null) {
      _scheduleInitialSync(_initialSyncRetries);
    }
  }

  static const int _initialSyncRetries = 3;

  void _scheduleInitialSync(int retriesLeft) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final source = _source;
      // 任一侧未挂载：可能滚动视图晚一帧才 attach，重试一次；用尽则放弃（后续
      // 用户滚动会自然校正）。
      if (source == null || !source.hasClients || !_target.hasClients) {
        if (retriesLeft > 0) _scheduleInitialSync(retriesLeft - 1);
        return;
      }
      _syncSourceToTarget();
    });
  }

  void dispose() {
    _source?.removeListener(_syncSourceToTarget);
    _target.removeListener(_syncTargetToSource);
    _source = null;
  }

  /// 源 → 目标：按滚动百分比映射。
  void _syncSourceToTarget() {
    _applySync(from: _source, to: _target);
  }

  /// 目标 → 源：按滚动百分比映射（反向）。
  void _syncTargetToSource() {
    _applySync(from: _target, to: _source);
  }

  void _applySync({
    required ScrollController? from,
    required ScrollController? to,
  }) {
    if (_syncing) return;
    if (from == null || !from.hasClients) return;
    if (to == null || !to.hasClients) return;
    final fromMax = from.position.maxScrollExtent;
    if (fromMax <= 0) return;
    final toMax = to.position.maxScrollExtent;
    if (toMax <= 0) return;
    final fraction = (from.position.pixels / fromMax).clamp(0.0, 1.0);
    _syncing = true;
    to.jumpTo(fraction * toMax);
    _syncing = false;
  }
}
