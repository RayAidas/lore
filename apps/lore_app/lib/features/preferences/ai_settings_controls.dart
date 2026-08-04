part of 'settings_page.dart';

/// 设置页「AI 写作助手」分组的实际内容：启用开关、接口地址、模型名、API Key。
///
/// 从 [_SettingsBodyState.build] 接收已解析的 [AgentConfigState]；写入走
/// `agentConfigProvider` 的 Controller，失败统一弹 toast（与其它设置项一致）。
final class _AiSettingsContent extends ConsumerWidget {
  const _AiSettingsContent({required this.configState});

  final AgentConfigState configState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(agentConfigProvider.notifier);
    final config = configState.config;
    final hasApiKey = configState.hasApiKey;

    ValueChanged<T> guard<T>(Future<void> Function(T) fn) => (T value) {
      fn(value).catchError((Object error, StackTrace stack) {
        debugPrint('ai settings save failed: $error\n$stack');
        if (context.mounted) {
          LoreToast.error(context, '设置保存失败，请重试');
        }
      });
    };
    void guardVoid(Future<void> Function() fn) {
      fn().catchError((Object error, StackTrace stack) {
        debugPrint('ai settings save failed: $error\n$stack');
        if (context.mounted) {
          LoreToast.error(context, '设置保存失败，请重试');
        }
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingRow(
          label: '启用',
          subtitle: '关闭时不发起任何模型请求',
          trailing: _CompactSwitch(
            value: config.enabled,
            onChanged: guard(controller.setEnabled),
          ),
        ),
        _SettingRow(
          label: '接口地址',
          subtitle: config.baseUrl,
          trailing: TextButton(
            onPressed: () => _editBaseUrl(context, controller, config.baseUrl),
            child: const Text('编辑'),
          ),
        ),
        _SettingRow(
          label: '模型',
          subtitle: config.model,
          trailing: TextButton(
            onPressed: () => _editModel(context, controller, config.model),
            child: const Text('编辑'),
          ),
        ),
        _SettingRow(
          label: 'API Key',
          subtitle: hasApiKey ? '已设置' : '未设置',
          trailing: hasApiKey
              ? TextButton(
                  onPressed: () => guardVoid(controller.clearApiKey),
                  child: const Text('清除'),
                )
              : TextButton(
                  onPressed: () =>
                      _editApiKey(context, controller, isReplace: false),
                  child: const Text('设置'),
                ),
        ),
        if (hasApiKey)
          _SettingRow(
            label: '更换 API Key',
            trailing: TextButton(
              onPressed: () => _editApiKey(context, controller, isReplace: true),
              child: const Text('更换'),
            ),
          ),
        const SizedBox(height: 6),
        Text(
          '调用模型时，所选文字或当前章节会发送到配置的模型服务；API Key 明文保存'
          '在应用内配置中（不加密），请勿在共享或备份环境中使用高价值 Key。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Future<void> _editBaseUrl(
    BuildContext context,
    AgentConfigController controller,
    String current,
  ) async {
    final value = await showLoreTextPromptDialog(
      context: context,
      title: '模型接口地址',
      label: 'Base URL',
      initialValue: current,
      helperText: '只需填到域名或 /v1，不要包含 /chat/completions；'
          '如 https://api.deepseek.com 或 https://api.openai.com/v1',
      confirmLabel: '保存',
    );
    if (value == null) return;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    try {
      await controller.setBaseUrl(trimmed);
    } catch (_) {
      if (context.mounted) {
        LoreToast.error(context, '设置保存失败，请重试');
      }
    }
  }

  Future<void> _editModel(
    BuildContext context,
    AgentConfigController controller,
    String current,
  ) async {
    final value = await showLoreTextPromptDialog(
      context: context,
      title: '模型',
      label: '模型名',
      initialValue: current,
      helperText: '如 gpt-4o-mini、deepseek-chat 等',
      confirmLabel: '保存',
    );
    if (value == null) return;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    try {
      await controller.setModel(trimmed);
    } catch (_) {
      if (context.mounted) {
        LoreToast.error(context, '设置保存失败，请重试');
      }
    }
  }

  /// 设置/更换 API Key。初始值留空（不把已存 Key 读回界面），只写入新值。
  Future<void> _editApiKey(
    BuildContext context,
    AgentConfigController controller, {
    required bool isReplace,
  }) async {
    final value = await showLoreTextPromptDialog(
      context: context,
      title: isReplace ? '更换 API Key' : '设置 API Key',
      label: 'API Key',
      obscureText: true,
      helperText: '明文保存在应用内配置中',
      confirmLabel: '保存',
    );
    if (value == null) return;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    try {
      await controller.setApiKey(trimmed);
    } catch (_) {
      if (context.mounted) {
        LoreToast.error(context, '设置保存失败，请重试');
      }
    }
  }
}
