import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lore_domain/lore_domain.dart';

/// 快捷键动作的本地化显示名（属表现层，故放 app 而非 domain）。
String shortcutActionLabel(ShortcutAction action) => switch (action) {
  ShortcutAction.save => '保存',
  ShortcutAction.closeDocument => '关闭文档',
  ShortcutAction.find => '查找',
  ShortcutAction.findReplace => '查找替换',
  ShortcutAction.findNext => '查找下一个',
  ShortcutAction.findPrevious => '查找上一个',
  ShortcutAction.toggleTypewriter => '切换打字机模式',
  ShortcutAction.toggleFullscreen => '切换全屏',
  ShortcutAction.openNovelSearch => '全局小说搜索',
  ShortcutAction.openSettings => '打开设置',
  ShortcutAction.toggleSplit => '切换分屏',
  ShortcutAction.focusPrimary => '聚焦主编辑区',
  ShortcutAction.focusSecondary => '聚焦副编辑区',
};

/// 动作是否仅在桌面（有物理键盘 + 支持分屏）生效。仅用于设置 UI 标注，
/// 不影响运行时门（运行时由工作区按平台能力自行判断）。
bool shortcutActionDesktopOnly(ShortcutAction action) =>
    action == ShortcutAction.toggleSplit ||
    action == ShortcutAction.focusPrimary ||
    action == ShortcutAction.focusSecondary;

/// 把逻辑键码格式化为单个键帽文本：字母转大写、可打印 ASCII 直接取字符，
/// 其余（回车、方向键、功能键）回落 `LogicalKeyboardKey.keyLabel`。
String formatKeyLabel(int logicalKeyId) {
  if (logicalKeyId >= 0x20 && logicalKeyId <= 0x7e) {
    return String.fromCharCode(logicalKeyId).toUpperCase();
  }
  final label = LogicalKeyboardKey(logicalKeyId).keyLabel;
  return label.isEmpty ? 'Key' : label;
}

/// 单个键帽：紧凑圆角小色块，高度与「未设置」文本行对齐（两者共用外层 chip
/// 容器，键帽不额外撑高 → 绑定态与未绑定态行高一致）。
class _KeyCap extends StatelessWidget {
  const _KeyCap(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1.2,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// 渲染一个按键组合为一排键帽，修饰键按 macOS HIG 顺序（⌃⌥⇧⌘）排列后接主键。
class KeyCombinationDisplay extends StatelessWidget {
  const KeyCombinationDisplay({required this.combination, super.key});

  final KeyCombination combination;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (combination.control)
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: _KeyCap('⌃'),
          ),
        if (combination.alt)
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: _KeyCap('⌥'),
          ),
        if (combination.shift)
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: _KeyCap('⇧'),
          ),
        if (combination.meta)
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: _KeyCap('⌘'),
          ),
        _KeyCap(formatKeyLabel(combination.logicalKeyId)),
      ],
    );
  }
}

/// 「按下即录」的快捷键字段：点击进入录制态，监听下一次按键组合填入；
/// 纯修饰键继续等待、Esc 取消、与其它动作冲突时不保存并提示。和主流软件一致。
class KeybindingField extends StatefulWidget {
  const KeybindingField({
    required this.action,
    required this.combination,
    required this.allBindings,
    required this.onRecorded,
    required this.onCleared,
    super.key,
  });

  final ShortcutAction action;
  final KeyCombination? combination;
  final Map<ShortcutAction, KeyCombination> allBindings;
  final ValueChanged<KeyCombination> onRecorded;
  final VoidCallback onCleared;

  @override
  State<KeybindingField> createState() => _KeybindingFieldState();
}

class _KeybindingFieldState extends State<KeybindingField> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'keybinding-recorder');
  bool _recording = false;
  ShortcutAction? _conflict;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _startRecording() {
    setState(() {
      _recording = true;
      _conflict = null;
    });
    // 下一帧请求焦点：本轮 build 把 onKeyEvent 挂上后才安全聚焦。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _stopRecording() {
    if (mounted) setState(() => _recording = false);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    // Esc 永远是「取消录制」，不作为可绑定组合。
    if (key == LogicalKeyboardKey.escape) {
      _stopRecording();
      return KeyEventResult.handled;
    }
    // 纯修饰键：吞掉但继续等主键，避免录入「仅 Shift」这类无效组合。
    // 需覆盖左/右两侧具体键——事件给的 logicalKey 是 shiftLeft/metaLeft 等，
    // 而非合成的 shift/meta。
    if (_isModifierKey(key)) {
      return KeyEventResult.handled;
    }
    final hw = HardwareKeyboard.instance;
    final combo = KeyCombination(
      logicalKeyId: key.keyId,
      meta: hw.isMetaPressed,
      control: hw.isControlPressed,
      alt: hw.isAltPressed,
      shift: hw.isShiftPressed,
    );
    final conflict = _conflictFor(combo);
    if (conflict != null) {
      setState(() => _conflict = conflict);
      _stopRecording();
    } else {
      widget.onRecorded(combo);
      _stopRecording();
    }
    return KeyEventResult.handled;
  }

  ShortcutAction? _conflictFor(KeyCombination combo) {
    for (final entry in widget.allBindings.entries) {
      if (entry.key != widget.action && entry.value == combo) {
        return entry.key;
      }
    }
    return null;
  }

  /// 判断逻辑键是否为任一修饰键（含左右两侧及合成名）。修饰键单独按下不构成
  /// 有效组合，录制时跳过继续等待主键。
  bool _isModifierKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.shift ||
      key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight ||
      key == LogicalKeyboardKey.control ||
      key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight ||
      key == LogicalKeyboardKey.alt ||
      key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight ||
      key == LogicalKeyboardKey.altGraph ||
      key == LogicalKeyboardKey.meta ||
      key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.metaRight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasCombo = widget.combination != null;

    final Color borderColor;
    if (_conflict != null) {
      borderColor = colorScheme.error;
    } else if (_recording) {
      borderColor = colorScheme.primary;
    } else {
      borderColor = colorScheme.outlineVariant;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Focus(
              focusNode: _focusNode,
              onKeyEvent: _recording ? _handleKey : null,
              onFocusChange: (focused) {
                if (!focused && _recording) _stopRecording();
              },
              child: Semantics(
                button: true,
                label: _recording
                    ? '正在录制 ${shortcutActionLabel(widget.action)} 的快捷键'
                    : '修改 ${shortcutActionLabel(widget.action)} 的快捷键',
                child: InkWell(
                  onTap: _recording ? null : _startRecording,
                  borderRadius: BorderRadius.circular(7),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh.withValues(
                        alpha: _recording ? 0.5 : 0.72,
                      ),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: borderColor,
                        width: _recording ? 1.5 : 1,
                      ),
                    ),
                    child: _recording
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.6,
                                  valueColor: AlwaysStoppedAnimation(
                                    colorScheme.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '按下快捷键…',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Esc 取消',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 10.5,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          )
                        : hasCombo
                        ? KeyCombinationDisplay(
                            combination: widget.combination!,
                          )
                        : Text(
                            '未设置',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                ),
              ),
            ),
            if (hasCombo && !_recording) ...[
              const SizedBox(width: 4),
              _ClearButton(onTap: widget.onCleared),
            ],
          ],
        ),
        if (_conflict != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 2),
            child: Text(
              '与「${shortcutActionLabel(_conflict!)}」冲突，未保存',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}

class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '清除快捷键',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 26,
            height: 26,
            child: Icon(
              Icons.close_rounded,
              size: 15,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
