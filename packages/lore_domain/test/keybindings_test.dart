import 'package:lore_domain/lore_domain.dart';
import 'package:test/test.dart';

void main() {
  group('KeyCombination', () {
    test('value equality covers key and all modifiers', () {
      const base = KeyCombination(logicalKeyId: 0x73, meta: true);
      expect(base, const KeyCombination(logicalKeyId: 0x73, meta: true));
      expect(
        base,
        isNot(const KeyCombination(logicalKeyId: 0x73, control: true)),
      );
      expect(
        base,
        isNot(
          const KeyCombination(logicalKeyId: 0x73, meta: true, shift: true),
        ),
      );
      expect(base, isNot(const KeyCombination(logicalKeyId: 0x66, meta: true)));
    });
  });

  group('Keybindings', () {
    test('defaults cover every configurable action exactly once', () {
      final bindings = Keybindings.defaults.bindings;
      for (final action in ShortcutAction.values) {
        expect(bindings, containsPair(action, isA<KeyCombination>()));
      }
      expect(bindings, hasLength(ShortcutAction.values.length));
    });

    test('defaults match the previous hardcoded workspace shortcuts', () {
      final b = Keybindings.defaults.bindings;
      expect(
        b[ShortcutAction.save],
        const KeyCombination(logicalKeyId: 0x73, meta: true),
      );
      expect(
        b[ShortcutAction.closeDocument],
        const KeyCombination(logicalKeyId: 0x77, meta: true),
      );
      expect(
        b[ShortcutAction.findPrevious],
        const KeyCombination(logicalKeyId: 0x67, meta: true, shift: true),
      );
      expect(
        b[ShortcutAction.openSettings],
        const KeyCombination(logicalKeyId: 0x2c, meta: true),
      );
      expect(
        b[ShortcutAction.toggleFullscreen],
        const KeyCombination(
          logicalKeyId: 0x10000000d,
          meta: true,
          shift: true,
        ),
      );
    });

    test('withBinding replaces a single action without mutating source', () {
      const original = Keybindings.defaults;
      const rebound = KeyCombination(logicalKeyId: 0x51, meta: true); // keyQ
      final next = original.withBinding(ShortcutAction.save, rebound);

      expect(next.bindings[ShortcutAction.save], rebound);
      // 源对象保持出厂默认不变。
      expect(
        original.bindings[ShortcutAction.save],
        const KeyCombination(logicalKeyId: 0x73, meta: true),
      );
    });

    test('withoutBinding drops an action so it shows as unset', () {
      final next = Keybindings.defaults.withoutBinding(ShortcutAction.save);
      expect(next.bindings.containsKey(ShortcutAction.save), isFalse);
      // 其余动作不受影响。
      expect(next.bindings.containsKey(ShortcutAction.find), isTrue);
    });
  });

  group('AppPreferences keybindings', () {
    test('defaults expose the canonical keybinding map', () {
      expect(
        AppPreferences.defaults().keybindings.bindings,
        Keybindings.defaults.bindings,
      );
    });

    test('copyWith updates keybindings without touching other fields', () {
      final base = AppPreferences.defaults();
      const rebound = KeyCombination(logicalKeyId: 0x51, meta: true);
      final updated = base.copyWith(
        keybindings: base.keybindings.withBinding(ShortcutAction.save, rebound),
      );

      expect(updated.keybindings.bindings[ShortcutAction.save], rebound);
      expect(updated.themeMode, base.themeMode);
      expect(updated.editorFontSize, base.editorFontSize);
    });

    test('copyWith leaves keybindings unchanged when omitted', () {
      final base = AppPreferences.defaults().copyWith(editorFontSize: 22);
      expect(base.keybindings.bindings, Keybindings.defaults.bindings);
    });
  });
}
