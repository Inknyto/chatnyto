/// The AI providers ChatNyto can talk to, all Bring Your Own Key.
///
/// Three wire protocols cover the field: most vendors expose an
/// OpenAI-compatible `/chat/completions`, Anthropic has its Messages API,
/// and Google has generateContent. Anything else that speaks the OpenAI
/// shape works through the "OpenAI-compatible" entry by pointing it at a
/// base URL.
///
/// Model names move faster than releases of this app, so every agent stores
/// its model as free text; the lists here are only starting suggestions.
enum AiProtocol { openAiCompatible, anthropic, gemini }

class AiProvider {
  const AiProvider({
    required this.id,
    required this.name,
    required this.protocol,
    required this.baseUrl,
    required this.models,
    this.keyUrl = '',
    this.needsKey = true,
    this.note = '',
  });

  final String id;
  final String name;
  final AiProtocol protocol;
  final String baseUrl;
  final List<String> models;

  /// Where the user gets an API key.
  final String keyUrl;

  /// Local runtimes need no key.
  final bool needsKey;
  final String note;

  static const anthropic = AiProvider(
    id: 'anthropic',
    name: 'Anthropic (Claude)',
    protocol: AiProtocol.anthropic,
    baseUrl: 'https://api.anthropic.com/v1',
    keyUrl: 'https://console.anthropic.com/settings/keys',
    models: [
      'claude-fable-5',
      'claude-opus-5',
      'claude-sonnet-5',
      'claude-haiku-4-5-20251001',
    ],
  );

  static const openai = AiProvider(
    id: 'openai',
    name: 'OpenAI',
    protocol: AiProtocol.openAiCompatible,
    baseUrl: 'https://api.openai.com/v1',
    keyUrl: 'https://platform.openai.com/api-keys',
    models: ['gpt-4.1', 'gpt-4.1-mini', 'gpt-4o', 'o4-mini'],
  );

  static const gemini = AiProvider(
    id: 'gemini',
    name: 'Google Gemini',
    protocol: AiProtocol.gemini,
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    keyUrl: 'https://aistudio.google.com/apikey',
    models: ['gemini-2.5-pro', 'gemini-2.5-flash'],
  );

  static const mistral = AiProvider(
    id: 'mistral',
    name: 'Mistral',
    protocol: AiProtocol.openAiCompatible,
    baseUrl: 'https://api.mistral.ai/v1',
    keyUrl: 'https://console.mistral.ai/api-keys',
    models: ['mistral-large-latest', 'mistral-small-latest'],
  );

  static const groq = AiProvider(
    id: 'groq',
    name: 'Groq',
    protocol: AiProtocol.openAiCompatible,
    baseUrl: 'https://api.groq.com/openai/v1',
    keyUrl: 'https://console.groq.com/keys',
    models: ['llama-3.3-70b-versatile', 'llama-3.1-8b-instant'],
  );

  static const deepseek = AiProvider(
    id: 'deepseek',
    name: 'DeepSeek',
    protocol: AiProtocol.openAiCompatible,
    baseUrl: 'https://api.deepseek.com/v1',
    keyUrl: 'https://platform.deepseek.com/api_keys',
    models: ['deepseek-chat', 'deepseek-reasoner'],
  );

  static const xai = AiProvider(
    id: 'xai',
    name: 'xAI (Grok)',
    protocol: AiProtocol.openAiCompatible,
    baseUrl: 'https://api.x.ai/v1',
    keyUrl: 'https://console.x.ai',
    models: ['grok-4', 'grok-3-mini'],
  );

  static const openrouter = AiProvider(
    id: 'openrouter',
    name: 'OpenRouter',
    protocol: AiProtocol.openAiCompatible,
    baseUrl: 'https://openrouter.ai/api/v1',
    keyUrl: 'https://openrouter.ai/keys',
    models: ['anthropic/claude-sonnet-5', 'openai/gpt-4.1'],
    note: 'One key, many vendors.',
  );

  static const ollama = AiProvider(
    id: 'ollama',
    name: 'Ollama (on this network)',
    protocol: AiProtocol.openAiCompatible,
    baseUrl: 'http://localhost:11434/v1',
    needsKey: false,
    models: ['llama3.2', 'qwen2.5', 'mistral'],
    note: 'Runs on your own machine — no key, works without internet.',
  );

  static const custom = AiProvider(
    id: 'custom',
    name: 'Other (OpenAI-compatible)',
    protocol: AiProtocol.openAiCompatible,
    baseUrl: '',
    models: [],
    needsKey: false,
    note: 'Point this at any server that speaks /chat/completions.',
  );

  static const all = [
    anthropic,
    openai,
    gemini,
    mistral,
    groq,
    deepseek,
    xai,
    openrouter,
    ollama,
    custom,
  ];

  static AiProvider byId(String id) =>
      all.firstWhere((p) => p.id == id, orElse: () => custom);
}
