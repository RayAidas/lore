/// 常用大模型提供商预设：显示名 + OpenAI 兼容接口地址 + 常用模型列表。
///
/// 设置页「接口地址」下拉按提供商选择并写入 `baseUrl`；「模型」下拉按当前
/// 接口地址匹配的提供商展示对应模型列表。两者都支持「自定义…」入口手动填写。
final class LlmProvider {
  const LlmProvider({
    required this.label,
    required this.baseUrl,
    required this.models,
  });

  /// 下拉框中展示的提供商名称，如「DeepSeek」。
  final String label;

  /// OpenAI 风格 Chat Completions 接口地址（不含 `/chat/completions`）。
  final String baseUrl;

  /// 该提供商常用的模型标识列表（首个为默认模型）。
  final List<String> models;

  /// 切到该提供商时采用的默认模型。
  String get defaultModel => models.first;
}

/// 内置常用大模型提供商表。若某提供商调整了默认模型或新增模型，可在此处更新。
const List<LlmProvider> kLlmProviders = [
  LlmProvider(
    label: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com',
    models: ['deepseek-chat', 'deepseek-reasoner'],
  ),
  LlmProvider(
    label: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    models: ['gpt-4o-mini', 'gpt-4o', 'gpt-4.1', 'o3-mini'],
  ),
  LlmProvider(
    label: 'Kimi（月之暗面）',
    baseUrl: 'https://api.moonshot.cn/v1',
    models: ['kimi-k2-0711-preview', 'kimi-latest'],
  ),
  LlmProvider(
    label: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    models: ['glm-4-flash', 'glm-4-plus', 'glm-4-air', 'glm-4.5'],
  ),
  LlmProvider(
    label: '通义千问',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    models: ['qwen-plus', 'qwen-turbo', 'qwen-max', 'qwen-long'],
  ),
  LlmProvider(
    label: '硅基流动',
    baseUrl: 'https://api.siliconflow.cn/v1',
    models: [
      'deepseek-ai/DeepSeek-V3',
      'Qwen/Qwen2.5-7B-Instruct',
      'meta-llama/Llama-3.3-70B-Instruct',
      'THUDM/GLM-4-9B-Chat',
    ],
  ),
  LlmProvider(
    label: '文心一言',
    baseUrl: 'https://qianfan.baidubce.com/v2',
    models: ['ernie-4.0-8k', 'ernie-4.0-turbo-8k', 'ernie-3.5-8k'],
  ),
  LlmProvider(
    label: 'Ollama（本地）',
    baseUrl: 'http://localhost:11434/v1',
    models: ['qwen2.5:7b', 'qwen2.5:14b', 'qwen2.5:32b', 'llama3.2:3b'],
  ),
];
