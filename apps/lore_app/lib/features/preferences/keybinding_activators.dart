import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lore_domain/lore_domain.dart';

import 'preferences_providers.dart';

/// 把领域层的 [KeyCombination] 解析为 Flutter 的 [SingleActivator]。
///
/// domain 不依赖 Flutter，故转换在 app 层完成。[LogicalKeyboardKey] 用 keyId
/// 构造，与录制时捕获的 `event.logicalKey` 同源，匹配可靠。
SingleActivator activatorFor(KeyCombination combo) => SingleActivator(
  LogicalKeyboardKey(combo.logicalKeyId),
  control: combo.control,
  alt: combo.alt,
  shift: combo.shift,
  meta: combo.meta,
);

/// 用户配置的快捷键映射解析为 [SingleActivator]，供工作区 [CallbackShortcuts]
/// 消费。当 [AppPreferences.keybindings] 变更（用户改键）时自动重建，改键即时
/// 生效，无需重启。
final keybindingActivatorsProvider =
    Provider<Map<ShortcutAction, SingleActivator>>((ref) {
      final prefs =
          ref.watch(appPreferencesProvider).value ?? AppPreferences.defaults();
      return {
        for (final entry in prefs.keybindings.bindings.entries)
          entry.key: activatorFor(entry.value),
      };
    });
