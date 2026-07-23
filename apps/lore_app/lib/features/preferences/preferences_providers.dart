import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lore_application/lore_application.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_platform_adapters/lore_platform_adapters.dart';

final appPreferencesRepositoryProvider = Provider<AppPreferencesRepository>((
  ref,
) {
  return SharedPreferencesAppPreferencesRepository();
});

final appPreferencesServiceProvider = Provider<AppPreferencesService>((ref) {
  return AppPreferencesService(
    repository: ref.watch(appPreferencesRepositoryProvider),
  );
});

/// 应用级偏好的唯一可观察来源。
///
/// 采用 [AsyncNotifierProvider]：首次加载异步读取落库值，之后每次设置变更
/// 在本进程内同步广播。偏好只在本应用内修改，无需跨进程 stream。
final appPreferencesProvider =
    AsyncNotifierProvider<PreferencesController, AppPreferences>(
      PreferencesController.new,
    );

final class PreferencesController extends AsyncNotifier<AppPreferences> {
  @override
  Future<AppPreferences> build() async {
    return ref.read(appPreferencesServiceProvider).loadOrDefault();
  }

  Future<void> setThemeMode(AppThemeMode mode) =>
      _update((current) => current.copyWith(themeMode: mode));
  Future<void> setEditorLineHeight(double value) =>
      _update((current) => current.copyWith(editorLineHeight: value));
  Future<void> setEditorFontSize(double value) =>
      _update((current) => current.copyWith(editorFontSize: value));
  Future<void> setEditorContentWidth(double value) =>
      _update((current) => current.copyWith(editorContentWidth: value));
  Future<void> setEditorFontFamily(AppFontFamily value) =>
      _update((current) => current.copyWith(editorFontFamily: value));
  Future<void> setDailyWordGoal(int value) =>
      _update((current) => current.copyWith(dailyWordGoal: value));
  Future<void> setFindMatchCase(bool value) =>
      _update((current) => current.copyWith(findMatchCase: value));
  Future<void> setFindUseRegex(bool value) =>
      _update((current) => current.copyWith(findUseRegex: value));
  Future<void> setTypewriterMode(bool value) =>
      _update((current) => current.copyWith(typewriterMode: value));
  Future<void> setFocusMode(bool value) =>
      _update((current) => current.copyWith(focusMode: value));
  Future<void> setFirstLineIndent(bool value) =>
      _update((current) => current.copyWith(firstLineIndent: value));
  Future<void> setParagraphSpacing(double value) =>
      _update((current) => current.copyWith(paragraphSpacing: value));
  Future<void> setGridLineMode(GridLineMode value) =>
      _update((current) => current.copyWith(gridLineMode: value));
  Future<void> setHighlightPalette(List<int> value) =>
      _update((current) => current.copyWith(highlightPalette: value));
  Future<void> setKeybinding(ShortcutAction action, KeyCombination combo) =>
      _update(
        (current) => current.copyWith(
          keybindings: current.keybindings.withBinding(action, combo),
        ),
      );
  Future<void> clearKeybinding(ShortcutAction action) => _update(
    (current) => current.copyWith(
      keybindings: current.keybindings.withoutBinding(action),
    ),
  );
  Future<void> resetKeybindings() =>
      _update((current) => current.copyWith(keybindings: Keybindings.defaults));
  Future<void> setBackgroundMode(AppBackgroundMode value) => _update((current) {
    if (value == AppBackgroundMode.image &&
        current.backgroundImagePaths.isEmpty) {
      return current;
    }
    return current.copyWith(backgroundMode: value);
  });
  Future<void> addBackgroundImages(List<String> values) => _update((current) {
    if (values.isEmpty) {
      return current;
    }
    return current.copyWith(
      backgroundMode: AppBackgroundMode.image,
      backgroundImagePaths: [...current.backgroundImagePaths, ...values],
      backgroundImagePath: values.last,
    );
  });
  Future<void> selectBackgroundImage(String value) => _update((current) {
    if (!current.backgroundImagePaths.contains(value)) {
      return current;
    }
    return current.copyWith(
      backgroundMode: AppBackgroundMode.image,
      backgroundImagePath: value,
    );
  });
  Future<void> removeBackgroundImage(String value) => _update((current) {
    final remaining = current.backgroundImagePaths
        .where((path) => path != value)
        .toList();
    final deletingSelected = current.backgroundImagePath == value;
    final nextSelection = deletingSelected
        ? (remaining.isEmpty ? null : remaining.first)
        : current.backgroundImagePath;
    return current.copyWith(
      backgroundMode: remaining.isEmpty
          ? AppBackgroundMode.theme
          : current.backgroundMode,
      backgroundImagePaths: remaining,
      backgroundImagePath: nextSelection,
      clearBackgroundImagePath: nextSelection == null,
    );
  });
  Future<void> setBackgroundOpacity(double value) =>
      _update((current) => current.copyWith(backgroundOpacity: value));
  Future<void> setBackgroundImageDimness(double value) =>
      _update((current) => current.copyWith(backgroundImageDimness: value));

  Future<void> _update(AppPreferences Function(AppPreferences) apply) async {
    final service = ref.read(appPreferencesServiceProvider);
    final current = state.value ?? AppPreferences.defaults();
    final next = await service.update(current, apply);
    state = AsyncData(next);
  }
}
