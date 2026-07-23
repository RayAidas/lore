/// 用户可配置的快捷键动作与按键组合的领域模型。
///
/// 与 Flutter 解耦：只存原始数据（[KeyCombination.logicalKeyId] 对应 Flutter
/// `LogicalKeyboardKey.keyId`），由 app 层在运行时解析为 `ShortcutActivator`、
/// 在设置 UI 里格式化为显示文本。编辑器内部快捷键（undo/redo/copy/cut/paste/
/// selectAll）当前硬编码在 `lore_editor`，未纳入可配置范围；如需开放，在
/// [ShortcutAction] 追加项即可，模型与持久化无需改动。
library;

/// 一个按键组合的不可变描述：主键 + 四个修饰键。
///
/// 值相等用于冲突检测——两个动作绑到完全相同的组合视为冲突。录入时若用户只
/// 按下修饰键而没有主键，应由录制控件在 `KeyEvent` 层拒绝；本模型不表达
/// 「仅修饰键」这种无效状态。
final class KeyCombination {
  const KeyCombination({
    required this.logicalKeyId,
    this.meta = false,
    this.control = false,
    this.alt = false,
    this.shift = false,
  });

  /// Flutter `LogicalKeyboardKey.keyId`。字母为小写 ASCII（a–z → 0x61–0x7A），
  /// 数字为 0x30–0x39，标点/回车各有定值。逻辑键码跨平台稳定，单设备本地
  /// 存储无需担心跨端同步。
  final int logicalKeyId;

  /// macOS Command（显示 ⌘）。
  final bool meta;

  /// Windows/Linux Control（显示 ⌃）。
  final bool control;

  /// Alt / Option（显示 ⌥）。
  final bool alt;

  /// Shift（显示 ⇧）。
  final bool shift;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KeyCombination &&
          other.logicalKeyId == logicalKeyId &&
          other.meta == meta &&
          other.control == control &&
          other.alt == alt &&
          other.shift == shift;

  @override
  int get hashCode => Object.hash(logicalKeyId, meta, control, alt, shift);
}

/// 可由用户自定义的快捷键动作。
///
/// 序列化用枚举名 [.name]；反序列化遇到未知动作名时跳过（前向兼容：旧版 app
/// 读到新版新增的动作不崩，新版 app 读到已废弃的动作忽略）。
enum ShortcutAction {
  save,
  closeDocument,
  find,
  findReplace,
  findNext,
  findPrevious,
  toggleTypewriter,
  toggleFullscreen,
  openNovelSearch,
  openSettings,
  toggleSplit,
  focusPrimary,
  focusSecondary,
}

/// 动作 → 按键组合 的不可变映射，承载于 [AppPreferences]。
final class Keybindings {
  const Keybindings(this.bindings);

  final Map<ShortcutAction, KeyCombination> bindings;

  /// 出厂默认：与改造前硬编码的工作区快捷键逐项一致，保证升级零行为漂移。
  /// `logicalKeyId` 取自 Flutter `LogicalKeyboardKey`，注释标出对应常量名。
  static const defaults = Keybindings({
    ShortcutAction.save: KeyCombination(logicalKeyId: 0x73, meta: true), // keyS
    ShortcutAction.closeDocument: KeyCombination(
      logicalKeyId: 0x77,
      meta: true,
    ), // keyW
    ShortcutAction.find: KeyCombination(logicalKeyId: 0x66, meta: true), // keyF
    ShortcutAction.findReplace: KeyCombination(
      logicalKeyId: 0x68,
      meta: true,
    ), // keyH
    ShortcutAction.findNext: KeyCombination(
      logicalKeyId: 0x67,
      meta: true,
    ), // keyG
    ShortcutAction.findPrevious: KeyCombination(
      logicalKeyId: 0x67,
      meta: true,
      shift: true,
    ), // Shift + keyG
    ShortcutAction.toggleTypewriter: KeyCombination(
      logicalKeyId: 0x74,
      meta: true,
      shift: true,
    ), // Shift + keyT
    ShortcutAction.toggleFullscreen: KeyCombination(
      logicalKeyId: 0x0d,
      meta: true,
      shift: true,
    ), // Shift + enter
    ShortcutAction.openNovelSearch: KeyCombination(
      logicalKeyId: 0x66,
      meta: true,
      shift: true,
    ), // Shift + keyF
    ShortcutAction.openSettings: KeyCombination(
      logicalKeyId: 0x2c,
      meta: true,
    ), // comma
    ShortcutAction.toggleSplit: KeyCombination(
      logicalKeyId: 0x5c,
      meta: true,
    ), // backslash
    ShortcutAction.focusPrimary: KeyCombination(
      logicalKeyId: 0x31,
      meta: true,
    ), // digit1
    ShortcutAction.focusSecondary: KeyCombination(
      logicalKeyId: 0x32,
      meta: true,
    ), // digit2
  });

  /// 替换单个动作的绑定，返回新映射（原对象不变）。
  Keybindings withBinding(ShortcutAction action, KeyCombination combo) =>
      Keybindings({...bindings, action: combo});

  /// 移除单个动作的绑定（未绑定的动作在 UI 显示「未设置」）。
  Keybindings withoutBinding(ShortcutAction action) =>
      Keybindings(Map<ShortcutAction, KeyCombination>.from(bindings)
        ..remove(action));
}
