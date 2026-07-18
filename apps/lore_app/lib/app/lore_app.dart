import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lore_domain/lore_domain.dart';
import 'package:lore_ui/lore_ui.dart';

import '../features/library/library_page.dart';
import '../features/preferences/preferences_providers.dart';

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
        // MaterialApp.themeMode 仅支持 system/light/dark 三态；
        // sepia 作为亮色变体，用 theme: 直接指向 LoreTheme.sepia() + ThemeMode.light 表达。
        final (theme, themeMode) = switch (prefs.themeMode) {
          AppThemeMode.system => (LoreTheme.light(), ThemeMode.system),
          AppThemeMode.light => (LoreTheme.light(), ThemeMode.light),
          AppThemeMode.sepia => (LoreTheme.sepia(), ThemeMode.light),
          AppThemeMode.dark => (LoreTheme.dark(), ThemeMode.dark),
        };
        return _materialApp(
          theme: theme,
          themeMode: themeMode,
          home: const LibraryPage(),
        );
      },
    );
  }

  MaterialApp _materialApp({
    required ThemeData theme,
    required ThemeMode themeMode,
    required Widget home,
  }) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Lore',
      theme: theme,
      darkTheme: LoreTheme.dark(),
      themeMode: themeMode,
      home: home,
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
