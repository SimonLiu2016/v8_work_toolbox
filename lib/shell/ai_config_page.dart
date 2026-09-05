import 'package:flutter/material.dart';
import '../components/app_components.dart';
import '../services/ai_config_store.dart';
import '../services/ai_service.dart';
import '../services/keychain_service.dart';
import '../theme/app_theme.dart';

class AiConfigPage extends StatefulWidget {
  const AiConfigPage({super.key});

  @override
  State<AiConfigPage> createState() => _AiConfigPageState();
}

class _AiConfigPageState extends State<AiConfigPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final store = AiConfigStore.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.bgContent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部标题与 Tab 栏
          Padding(
            padding: const EdgeInsets.fromLTRB(AppTheme.space24, 38 + AppTheme.space8, AppTheme.space24, AppTheme.space8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('AI 基础设施配置', style: AppTheme.fontHeadline),
                const SizedBox(height: AppTheme.space4),
                Text(
                  '配置多协议模型供应商、全局能力槽位与外部 MCP 服务。凭证由 macOS Keychain 安全保护。',
                  style: AppTheme.fontCaption.copyWith(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: AppTheme.space16),
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: AppTheme.accentLight,
                  unselectedLabelColor: AppTheme.textSecondary,
                  indicatorColor: AppTheme.accent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: AppTheme.borderSubtle,
                  tabs: const [
                    Tab(icon: Icon(Icons.business_outlined, size: 16), text: '模型供应商'),
                    Tab(icon: Icon(Icons.hub_outlined, size: 16), text: '默认能力槽位'),
                    Tab(icon: Icon(Icons.cable_outlined, size: 16), text: '外部 MCP 客户端'),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.borderSubtle),

          // Tab 内容展示
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildProvidersTab(),
                _buildSlotsTab(),
                _buildMcpTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1: 供应商列表
  // ---------------------------------------------------------------------------
  Widget _buildProvidersTab() {
    final providers = store.providers;

    return ListView(
      padding: const EdgeInsets.all(AppTheme.space24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('已配置的供应商 (${providers.length})', style: AppTheme.fontTitle),
            AppButton.primary(
              label: '添加供应商',
              icon: Icons.add,
              onPressed: () => _showAddOrEditProviderDialog(),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.space16),
        if (providers.isEmpty)
          AppCard(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.space24),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.smart_toy_outlined, size: 36, color: AppTheme.textTertiary),
                    const SizedBox(height: AppTheme.space12),
                    Text('暂未配置任何 AI 供应商', style: AppTheme.fontBody.copyWith(color: AppTheme.textSecondary)),
                    const SizedBox(height: AppTheme.space8),
                    Text('支持接入 OpenAI、DeepSeek、Ollama、Anthropic、Gemini 等兼容端点。', style: AppTheme.fontCaption.copyWith(color: AppTheme.textTertiary)),
                  ],
                ),
              ),
            ),
          )
        else
          ...providers.map((p) => _buildProviderCard(p)),
      ],
    );
  }

  Widget _buildProviderCard(AiProviderConfig p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.space12),
      child: AppCard(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.psychology_alt_outlined, size: 20, color: AppTheme.accentLight),
                  const SizedBox(width: AppTheme.space8),
                  Text(p.name, style: AppTheme.fontTitle),
                  const SizedBox(width: AppTheme.space8),
                  AppBadge(label: p.protocol.label),
                  const Spacer(),
                  AppButton.ghost(
                    label: '测试连接',
                    icon: Icons.bolt,
                    onPressed: () => _testProvider(p),
                  ),
                  const SizedBox(width: AppTheme.space6),
                  AppButton.secondary(
                    label: '编辑',
                    icon: Icons.edit_outlined,
                    onPressed: () => _showAddOrEditProviderDialog(provider: p),
                  ),
                  const SizedBox(width: AppTheme.space6),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 16, color: AppTheme.error),
                    tooltip: '删除供应商',
                    onPressed: () => _deleteProvider(p),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.space8),
              Text('API 地址: ${p.baseUrl}', style: AppTheme.fontCaption.copyWith(color: AppTheme.textSecondary)),
              if (p.textModels.isNotEmpty) ...[
                const SizedBox(height: AppTheme.space8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: p.textModels.take(8).map((m) => AppBadge(label: m)).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: 默认槽位映射
  // ---------------------------------------------------------------------------
  Widget _buildSlotsTab() {
    final slots = [
      {'key': 'text', 'label': '文本补全 / 对话 (Text)', 'desc': '用于代码解释、文本生成、规则重写等'},
      {'key': 'multimodal', 'label': '视觉多模态 (Multimodal)', 'desc': '用于图标理解、设计稿提取分析等'},
      {'key': 'tts', 'label': '文本转语音 (TTS)', 'desc': '用于语音合成与播报'},
      {'key': 'stt', 'label': '语音识别 (STT)', 'desc': '用于音频转文字与语音输入'},
    ];

    return ListView(
      padding: const EdgeInsets.all(AppTheme.space24),
      children: [
        Text('全局能力槽位绑定', style: AppTheme.fontTitle),
        const SizedBox(height: AppTheme.space4),
        Text('所有业务工具在调用 AI 能力时，将默认自动路由至此绑定的供应商与模型。', style: AppTheme.fontCaption.copyWith(color: AppTheme.textSecondary)),
        const SizedBox(height: AppTheme.space16),
        ...slots.map((s) => _buildSlotCard(s['key']!, s['label']!, s['desc']!)),
      ],
    );
  }

  Widget _buildSlotCard(String slotKey, String label, String desc) {
    final binding = store.slotBindings[slotKey] ?? {'providerId': '', 'model': ''};
    final currentProviderId = binding['providerId'] ?? '';
    final currentModel = binding['model'] ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.space12),
      child: AppCard(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.space16),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppTheme.fontBody.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: AppTheme.space2),
                    Text(desc, style: AppTheme.fontCaption.copyWith(color: AppTheme.textTertiary)),
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.space16),
              // 供应商选择
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  initialValue: currentProviderId.isEmpty ? null : currentProviderId,
                  decoration: const InputDecoration(labelText: '供应商'),
                  items: store.providers.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      store.setSlotBinding(slotKey, val, '');
                      setState(() {});
                    }
                  },
                ),
              ),
              const SizedBox(width: AppTheme.space12),
              // 模型选择
              Expanded(
                flex: 3,
                child: Builder(builder: (context) {
                  final provider = store.providers.firstWhere((p) => p.id == currentProviderId, orElse: () => const AiProviderConfig(id: '', name: '', protocol: AiProtocolType.openai, baseUrl: '', keychainKeyId: ''));
                  final models = provider.textModels;

                  return DropdownButtonFormField<String>(
                    initialValue: models.contains(currentModel) ? currentModel : null,
                    decoration: const InputDecoration(labelText: '模型'),
                    items: models.map((m) => DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        store.setSlotBinding(slotKey, currentProviderId, val);
                        setState(() {});
                      }
                    },
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 3: 外部 MCP 客户端
  // ---------------------------------------------------------------------------
  Widget _buildMcpTab() {
    final clients = store.mcpClients;

    return ListView(
      padding: const EdgeInsets.all(AppTheme.space24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('外部第三方 MCP 服务 (${clients.length})', style: AppTheme.fontTitle),
            AppButton.primary(
              label: '添加 MCP 服务',
              icon: Icons.add,
              onPressed: () => _showAddOrEditMcpDialog(),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.space16),
        if (clients.isEmpty)
          AppCard(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.space24),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.cable_outlined, size: 36, color: AppTheme.textTertiary),
                    const SizedBox(height: AppTheme.space12),
                    Text('暂未配置外部 MCP 客户端', style: AppTheme.fontBody.copyWith(color: AppTheme.textSecondary)),
                    const SizedBox(height: AppTheme.space8),
                    Text('可配置已运行的第三方 Model Context Protocol 服务的连接端点或命令行调用。', style: AppTheme.fontCaption.copyWith(color: AppTheme.textTertiary)),
                  ],
                ),
              ),
            ),
          )
        else
          ...clients.map((c) => Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.space12),
            child: AppCard(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.space16),
                child: Row(
                  children: [
                    const Icon(Icons.settings_input_component_outlined, size: 20, color: AppTheme.accentLight),
                    const SizedBox(width: AppTheme.space8),
                    Text(c.name, style: AppTheme.fontTitle),
                    const SizedBox(width: AppTheme.space8),
                    AppBadge(label: c.transport.toUpperCase()),
                    const SizedBox(width: AppTheme.space16),
                    Expanded(
                      child: Text(
                        c.endpointOrCommand,
                        style: AppTheme.fontCaption.copyWith(color: AppTheme.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 16, color: AppTheme.error),
                      onPressed: () async {
                        await store.deleteMcpClient(c.id);
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            ),
          )),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 弹窗与交互逻辑
  // ---------------------------------------------------------------------------
  void _showAddOrEditProviderDialog({AiProviderConfig? provider}) {
    final isEditing = provider != null;
    final nameCtrl = TextEditingController(text: provider?.name ?? '');
    final urlCtrl = TextEditingController(text: provider?.baseUrl ?? 'https://api.openai.com/v1');
    final keyCtrl = TextEditingController();
    final modelsCtrl = TextEditingController(text: provider?.textModels.join(', ') ?? '');
    AiProtocolType protocol = provider?.protocol ?? AiProtocolType.openai;
    bool isDetecting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          title: Row(
            children: [
              Text(isEditing ? '编辑 AI 供应商' : '添加 AI 供应商', style: AppTheme.fontTitle),
              if (isEditing) ...[
                const SizedBox(width: AppTheme.space8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.15),
                    borderRadius: AppTheme.borderRadiusSmall,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shield_outlined, size: 12, color: AppTheme.success),
                      SizedBox(width: 4),
                      Text('已加密存储', style: TextStyle(fontSize: 11, color: AppTheme.success)),
                    ],
                  ),
                ),
              ],
            ],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 快速预设模板
                  const Text('快速填充预设:', style: AppTheme.fontCaption),
                  const SizedBox(height: AppTheme.space8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.bolt, size: 14, color: AppTheme.accent),
                        label: const Text('DeepSeek', style: TextStyle(fontSize: 11)),
                        onPressed: () {
                          setDialogState(() {
                            nameCtrl.text = 'DeepSeek';
                            protocol = AiProtocolType.openai;
                            urlCtrl.text = 'https://api.deepseek.com/v1';
                            modelsCtrl.text = 'deepseek-chat, deepseek-reasoner';
                          });
                        },
                      ),
                      ActionChip(
                        label: const Text('OpenAI', style: TextStyle(fontSize: 11)),
                        onPressed: () {
                          setDialogState(() {
                            nameCtrl.text = 'OpenAI';
                            protocol = AiProtocolType.openai;
                            urlCtrl.text = 'https://api.openai.com/v1';
                            modelsCtrl.text = 'gpt-4o, gpt-4o-mini';
                          });
                        },
                      ),
                      ActionChip(
                        label: const Text('Claude', style: TextStyle(fontSize: 11)),
                        onPressed: () {
                          setDialogState(() {
                            nameCtrl.text = 'Anthropic Claude';
                            protocol = AiProtocolType.anthropic;
                            urlCtrl.text = 'https://api.anthropic.com';
                            modelsCtrl.text = 'claude-3-7-sonnet-20250219, claude-3-5-sonnet-20241022, claude-3-5-haiku-20241022';
                          });
                        },
                      ),
                      ActionChip(
                        label: const Text('Gemini', style: TextStyle(fontSize: 11)),
                        onPressed: () {
                          setDialogState(() {
                            nameCtrl.text = 'Google Gemini';
                            protocol = AiProtocolType.gemini;
                            urlCtrl.text = 'https://generativelanguage.googleapis.com';
                            modelsCtrl.text = 'gemini-2.5-pro, gemini-2.5-flash, gemini-2.0-flash';
                          });
                        },
                      ),
                      ActionChip(
                        label: const Text('Ollama(本地)', style: TextStyle(fontSize: 11)),
                        onPressed: () {
                          setDialogState(() {
                            nameCtrl.text = 'Ollama 本地';
                            protocol = AiProtocolType.openai;
                            urlCtrl.text = 'http://localhost:11434/v1';
                            modelsCtrl.text = 'qwen2.5:latest, llama3.1:latest';
                          });
                        },
                      ),
                      ActionChip(
                        label: const Text('硅基流动', style: TextStyle(fontSize: 11)),
                        onPressed: () {
                          setDialogState(() {
                            nameCtrl.text = '硅基流动 (SiliconFlow)';
                            protocol = AiProtocolType.openai;
                            urlCtrl.text = 'https://api.siliconflow.cn/v1';
                            modelsCtrl.text = 'deepseek-ai/DeepSeek-V3, deepseek-ai/DeepSeek-R1';
                          });
                        },
                      ),
                    ],
                  ),
                  const Divider(height: AppTheme.space24),
                  AppTextField(controller: nameCtrl, label: '供应商名称', hintText: '如 OpenAI / DeepSeek / Ollama'),
                  const SizedBox(height: AppTheme.space12),
                  DropdownButtonFormField<AiProtocolType>(
                    initialValue: protocol,
                    decoration: const InputDecoration(labelText: '协议类型'),
                    items: AiProtocolType.values.map((p) => DropdownMenuItem(value: p, child: Text(p.label))).toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => protocol = val);
                    },
                  ),
                  const SizedBox(height: AppTheme.space12),
                  AppTextField(controller: urlCtrl, label: 'API Base URL', hintText: 'https://api.openai.com/v1'),
                  const SizedBox(height: AppTheme.space12),
                  AppTextField(
                    controller: keyCtrl,
                    label: isEditing ? 'API Key (已安全保存，若不修改请留空)' : 'API Key',
                    hintText: isEditing ? '留空则保持原有密钥不变' : 'sk-...',
                    obscureText: true,
                  ),
                  const SizedBox(height: AppTheme.space12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('支持的模型 (逗号分隔)', style: AppTheme.fontCaption),
                      if (isDetecting)
                        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        TextButton.icon(
                          icon: const Icon(Icons.auto_awesome, size: 14),
                          label: const Text('自动探测发现', style: TextStyle(fontSize: 12)),
                          onPressed: () async {
                            setDialogState(() => isDetecting = true);
                            try {
                              String keyToUse = keyCtrl.text.trim();
                              if (keyToUse.isEmpty && provider != null) {
                                keyToUse = await KeychainService.instance.readSecret(provider.keychainKeyId) ?? '';
                              }

                              if (keyToUse.isEmpty && !urlCtrl.text.contains('localhost') && !urlCtrl.text.contains('127.0.0.1')) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                      content: Text('请先输入 API Key 再进行自动探测'),
                                      backgroundColor: AppTheme.warning,
                                    ),
                                  );
                                }
                                return;
                              }

                              final tempProv = AiProviderConfig(
                                id: provider?.id ?? 'temp_${DateTime.now().millisecondsSinceEpoch}',
                                name: nameCtrl.text.trim().isEmpty ? '临时供应商' : nameCtrl.text.trim(),
                                protocol: protocol,
                                baseUrl: urlCtrl.text.trim(),
                                keychainKeyId: provider?.keychainKeyId ?? 'temp',
                              );
                              final found = await AiService.instance.discoverModels(tempProv, apiKey: keyToUse.isNotEmpty ? keyToUse : null);
                              setDialogState(() {
                                modelsCtrl.text = found.join(', ');
                              });
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: Text('✓ 成功探测到 ${found.length} 个可用模型！'),
                                    backgroundColor: AppTheme.success,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: Text('探测失败: $e'),
                                    backgroundColor: AppTheme.error,
                                    duration: const Duration(seconds: 6),
                                  ),
                                );
                              }
                            } finally {
                              setDialogState(() => isDetecting = false);
                            }
                          },
                        ),
                    ],
                  ),
                  AppTextField(controller: modelsCtrl, maxLines: 2, hintText: '如 gpt-4o, gpt-4o-mini'),
                ],
              ),
            ),
          ),
          actions: [
            AppButton.ghost(label: '取消', onPressed: () => Navigator.pop(ctx)),
            AppButton.primary(
              label: '保存',
              onPressed: () async {
                final id = provider?.id ?? 'provider_${DateTime.now().millisecondsSinceEpoch}';
                final keyId = provider?.keychainKeyId ?? 'key_$id';
                final models = modelsCtrl.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

                final newProv = AiProviderConfig(
                  id: id,
                  name: nameCtrl.text.trim().isEmpty ? '未命名供应商' : nameCtrl.text.trim(),
                  protocol: protocol,
                  baseUrl: urlCtrl.text.trim(),
                  keychainKeyId: keyId,
                  textModels: models,
                );

                await store.saveProvider(newProv, apiKey: keyCtrl.text.trim().isEmpty ? null : keyCtrl.text.trim());
                if (ctx.mounted) Navigator.pop(ctx);
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAddOrEditMcpDialog() {
    final nameCtrl = TextEditingController();
    final endCtrl = TextEditingController();
    String transport = 'stdio';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          title: const Text('添加外部 MCP 客户端', style: AppTheme.fontTitle),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextField(controller: nameCtrl, label: '服务名称', hintText: '如 Filesystem / Memory'),
                const SizedBox(height: AppTheme.space12),
                DropdownButtonFormField<String>(
                  initialValue: transport,
                  decoration: const InputDecoration(labelText: '通信方式'),
                  items: const [
                    DropdownMenuItem(value: 'stdio', child: Text('标准输入输出 (stdio)')),
                    DropdownMenuItem(value: 'sse', child: Text('Server-Sent Events (SSE / HTTP)')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => transport = val);
                  },
                ),
                const SizedBox(height: AppTheme.space12),
                AppTextField(controller: endCtrl, label: transport == 'stdio' ? '启动命令 / 脚本' : '服务 URL', hintText: transport == 'stdio' ? 'npx -y @mcp/server-filesystem' : 'http://localhost:8000/sse'),
              ],
            ),
          ),
          actions: [
            AppButton.ghost(label: '取消', onPressed: () => Navigator.pop(ctx)),
            AppButton.primary(
              label: '保存',
              onPressed: () async {
                final id = 'mcp_${DateTime.now().millisecondsSinceEpoch}';
                final client = McpClientConfig(
                  id: id,
                  name: nameCtrl.text.trim().isEmpty ? '未命名服务' : nameCtrl.text.trim(),
                  transport: transport,
                  endpointOrCommand: endCtrl.text.trim(),
                );
                await store.saveMcpClient(client);
                if (ctx.mounted) Navigator.pop(ctx);
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  void _testProvider(AiProviderConfig p) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('正在测试与供应商连接...')));
    try {
      final models = await AiService.instance.discoverModels(p);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text(models.isNotEmpty ? '✓ 连接成功，正常探测到 ${models.length} 个模型！' : '✕ 连接成功但未返回可用模型'),
          backgroundColor: models.isNotEmpty ? AppTheme.success : AppTheme.warning,
        ),
      );
    } catch (e) {
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text('✕ 连接失败: $e'),
          backgroundColor: AppTheme.error,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  void _deleteProvider(AiProviderConfig p) async {
    await store.deleteProvider(p.id);
    setState(() {});
  }
}
