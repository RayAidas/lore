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
  Future<void> setDefaultChapterFormat(ChapterFormat format) =>
      _update((current) => current.copyWith(defaultChapterFormat: format));
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

  Future<void> _update(AppPreferences Function(AppPreferences) apply) async {
    final service = ref.read(appPreferencesServiceProvider);
    final current = state.value ?? AppPreferences.defaults();
    final next = await service.update(current, apply);
    state = AsyncData(next);
  }
}
