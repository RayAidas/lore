import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_ui/lore_ui.dart';

import 'app_background.dart';
import '../features/library/library_page.dart';
import '../features/preferences/preferences_providers.dart';
import '../features/preferences/theme_options.dart';

class LoreApp extends ConsumerWidget {
  const LoreApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(appPreferencesProvider);
    return prefsAsync.when(
      loading: () => _materialApp(
        theme: LoreTheme.light(),
        themeMode: ThemeMode.system,
        home: const _Splash(),
      ),
      error: (error, stack) => _materialApp(
        theme: LoreTheme.light(),
        themeMode: ThemeMode.system,
        home: _PreferencesError(message: '$error'),
      ),
      data: (prefs) {
        final surfaceOpacity = prefs.backgroundMode == AppBackgroundMode.theme
            ? 1.0
            : prefs.backgroundOpacity;
        // system 走真·系统跟随；显式模式把 theme 与 darkTheme 都指向所选主题，
        // 让「选哪个显示哪个」（墨渊这类第二个暗色主题不会被 dark() 覆盖成夜间）。
        // 详见 [AppThemeOptions.resolveAppliedTheme]，逻辑已单测锁定。
        final applied = AppThemeOptions.resolveAppliedTheme(prefs.themeMode);
        return _materialApp(
          theme: LoreTheme.withSurfaceOpacity(applied.theme, surfaceOpacity),
          darkTheme: LoreTheme.withSurfaceOpacity(
            applied.darkTheme,
            surfaceOpacity,
          ),
          themeMode: applied.themeMode,
          home: AppBackground(preferences: prefs, child: const LibraryPage()),
        );
      },
    );
  }

  MaterialApp _materialApp({
    required ThemeData theme,
    ThemeData? darkTheme,
    required ThemeMode themeMode,
    required Widget home,
  }) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Lore',
      theme: theme,
      darkTheme: darkTheme ?? LoreTheme.dark(),
      themeMode: themeMode,
      scrollBehavior: const LoreScrollBehavior(),
      home: home,
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    // 无动画占位：避免 pumpAndSettle 在 loading 期持续等待 CircularProgressIndicator。
    return const Scaffold(body: Center(child: Text('Lore')));
  }
}

class _PreferencesError extends StatelessWidget {
  const _PreferencesError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('无法加载偏好设置：$message'),
        ),
      ),
    );
  }
}

/// 桌面平台（macOS/Windows/Linux）禁用过度滚动的弹簧回弹：到边即停（ClampingScrollPhysics），
/// 消除标签栏、正文编辑器、Markdown 预览、目录树等到顶/到底后的「超出再弹回」效果。
/// 移动端沿用平台原生手感（iOS 弹簧、Android 光晕）。
final class LoreScrollBehavior extends MaterialScrollBehavior {
  const LoreScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return switch (Theme.of(context).platform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => const ClampingScrollPhysics(),
      _ => super.getScrollPhysics(context),
    };
  }
}
