/// 常用大模型预设：提供商显示名 + OpenAI 兼容接口地址 + 默认模型名。
///
/// 选择预设会同时写入 `baseUrl` 与 `model`（两者配套服务才可用）；若想用预设
/// 之外的模型，走设置里的「自定义模型…」入口只改模型名、保留当前接口地址。
final class LlmPreset {
  const LlmPreset({
    required this.label,
    required this.baseUrl,
    required this.model,
  });

  /// 下拉框中展示的提供商名称，如「DeepSeek」。
  final String label;

  /// OpenAI 风格 Chat Completions 接口地址（不含 `/chat/completions`）。
  final String baseUrl;

  /// 该提供商常用的模型标识。
  final String model;
}

/// 内置常用大模型预设表。若某提供商调整了默认模型，可在此处更新条目。
const List<LlmPreset> kLlmPresets = [
  LlmPreset(
    label: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-chat',
  ),
  LlmPreset(
    label: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    model: 'gpt-4o-mini',
  ),
  LlmPreset(
    label: 'Kimi（月之暗面）',
    baseUrl: 'https://api.moonshot.cn/v1',
    model: 'kimi-k2-0711-preview',
  ),
  LlmPreset(
    label: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    model: 'glm-4-flash',
  ),
  LlmPreset(
    label: '通义千问',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    model: 'qwen-plus',
  ),
  LlmPreset(
    label: '硅基流动',
    baseUrl: 'https://api.siliconflow.cn/v1',
    model: 'deepseek-ai/DeepSeek-V3',
  ),
  LlmPreset(
    label: '文心一言',
    baseUrl: 'https://qianfan.baidubce.com/v2',
    model: 'ernie-4.0-8k',
  ),
  LlmPreset(
    label: 'Ollama（本地）',
    baseUrl: 'http://localhost:11434/v1',
    model: 'qwen2.5:7b',
  ),
];
