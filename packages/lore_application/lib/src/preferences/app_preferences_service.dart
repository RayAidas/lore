import 'package:lore_domain/lore_domain.dart';

import '../ports/app_preferences_repository.dart';

final class AppPreferencesService {
  const AppPreferencesService({required this.repository});

  final AppPreferencesRepository repository;

  Future<AppPreferences> loadOrDefault() async {
    final loaded = await repository.load();
    return loaded ?? AppPreferences.defaults();
  }

  /// 以函数形式描述变更，落库并返回最新偏好。
  ///
  /// 通过 `apply` 接收当前偏好并返回新值，避免为每个字段重复定义 setter。
  Future<AppPreferences> update(
    AppPreferences current,
    AppPreferences Function(AppPreferences) apply,
  ) async {
    final next = apply(current);
    await repository.save(next);
    return next;
  }
}
