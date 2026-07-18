import 'package:lore_domain/lore_domain.dart';

/// 应用级偏好的持久化端口。
///
/// 实现负责把 [AppPreferences] 写入可重建的本地存储（如 SharedPreferences），
/// 并通过 [watch] 暴露变更流，使设置改动能实时驱动主题与编辑器排版。
abstract interface class AppPreferencesRepository {
  Future<AppPreferences?> load();

  Future<void> save(AppPreferences preferences);

  /// 在 [save] 之后推送最新偏好；首条事件由实现决定是否立即发出当前值。
  Stream<AppPreferences> watch();
}
