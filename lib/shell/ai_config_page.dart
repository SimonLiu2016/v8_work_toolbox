import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../components/app_components.dart';
import '../services/ai_config_store.dart';
import '../services/ai_service.dart';
import '../services/app_http_client.dart';
import '../services/keychain_service.dart';
import '../services/mcp_service.dart';
import '../theme/app_theme.dart';
import 'ai_log_dialog.dart';
import 'mcp_tool_inventory_view.dart';

class AiConfigPage extends StatefulWidget {
  const AiConfigPage({super.key});

  @override
  State<AiConfigPage> createState() => _AiConfigPageState();
}

class _AiConfigPageState extends State<AiConfigPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final store = AiConfigStore.instance;
  Timer? _healthRefreshTimer;
  final Map<String, bool> _mcpTesting = {};
  final Map<String, McpServerStatus?> _mcpTestResults = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // 每 10 秒刷新健康状态指示器
    _healthRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
    // 启动时检查密钥库是否曾被自愈重置（持久化标记）。若是，提示用户已存密钥需重填。
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkRebuildNotice());
  }

  void _checkRebuildNotice() async {
    final rebuilt = await KeychainService.instance.consumeRebuildNotice();
    if (rebuilt && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '密钥库此前因密钥失配被重置，已存密钥（如 API Key）需重新填入。'
            '残件备份见 ~/Library/Application Support/V8WorkToolbox/ 下的 .mismatch-* 文件。',
          ),
          backgroundColor: context.warningSolid,
          duration: Duration(seconds: 12),
        ),
      );
    }
  }

  @override
  void dispose() {
    _healthRefreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.bgContent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部标题与 Tab 栏
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space24,
              38 + AppTheme.space8,
              AppTheme.space24,
              AppTheme.space8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('AI 基础设施配置', style: AppTheme.fontHeadline),
                          SizedBox(height: AppTheme.space4),
                          Text(
                            '配置多协议模型供应商、全局能力槽位与外部 MCP 服务。凭证由 macOS Keychain 安全保护。',
                            style: AppTheme.fontCaption.copyWith(
                              color: context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppTheme.space16),
                    AppButton.secondary(
                      label: '查看调用日志',
                      icon: Icons.receipt_long_rounded,
                      onPressed: () => AiLogDialog.show(context),
                    ),
                  ],
                ),
                SizedBox(height: AppTheme.space16),
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: context.accentText,
                  unselectedLabelColor: context.textSecondary,
                  indicatorColor: context.accentSolid,
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: context.borderSubtle,
                  tabs: const [
                    Tab(
                      icon: Icon(Icons.business_outlined, size: 16),
                      text: '模型供应商',
                    ),
                    Tab(
                      icon: Icon(Icons.hub_outlined, size: 16),
                      text: '默认能力槽位',
                    ),
                    Tab(
                      icon: Icon(Icons.cable_outlined, size: 16),
                      text: '外部 MCP 客户端',
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.borderSubtle),

          // Tab 内容展示
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildProvidersTab(),
                _buildSlotsTab(),
                _buildMcpWithInventory(),
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
                    Icon(
                      Icons.smart_toy_outlined,
                      size: 36,
                      color: context.textTertiary,
                    ),
                    SizedBox(height: AppTheme.space12),
                    Text(
                      '暂未配置任何 AI 供应商',
                      style: AppTheme.fontBody.copyWith(
                        color: context.textSecondary,
                      ),
                    ),
                    SizedBox(height: AppTheme.space8),
                    Text(
                      '支持接入 OpenAI、DeepSeek、Ollama、Anthropic、Gemini 等兼容端点。',
                      style: AppTheme.fontCaption.copyWith(
                        color: context.textTertiary,
                      ),
                    ),
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
                  Icon(
                    Icons.psychology_alt_outlined,
                    size: 20,
                    color: context.accentText,
                  ),
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
                  SizedBox(width: AppTheme.space6),
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: context.errorText,
                    ),
                    tooltip: '删除供应商',
                    onPressed: () => _deleteProvider(p),
                  ),
                ],
              ),
              SizedBox(height: AppTheme.space8),
              Text(
                'API 地址: ${p.baseUrl}',
                style: AppTheme.fontCaption.copyWith(
                  color: context.textSecondary,
                ),
              ),
              if (p.textModels.isNotEmpty) ...[
                const SizedBox(height: AppTheme.space8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: p.textModels
                      .take(8)
                      .map((m) => AppBadge(label: m))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: 默认槽位映射（多候选管理 + 健康展示）
  // ---------------------------------------------------------------------------
  Widget _buildSlotsTab() {
    final slots = [
      {'key': 'text', 'label': '文本补全 / 对话 (Text)', 'desc': '用于代码解释、文本生成、规则重写等'},
      {
        'key': 'multimodal',
        'label': '视觉多模态 (Multimodal)',
        'desc': '用于图标理解、设计稿提取分析等',
      },
      {'key': 'tts', 'label': '文本转语音 (TTS)', 'desc': '用于语音合成与播报'},
      {'key': 'stt', 'label': '语音识别 (STT)', 'desc': '用于音频转文字与语音输入'},
    ];

    return ListView(
      padding: const EdgeInsets.all(AppTheme.space24),
      children: [
        Text('全局能力槽位绑定', style: AppTheme.fontTitle),
        SizedBox(height: AppTheme.space4),
        Text(
          '每个槽位支持多个候选供应商，按优先级排列。运行时自动路由至最优可用供应商，首选不可用时自动降级。',
          style: AppTheme.fontCaption.copyWith(color: context.textSecondary),
        ),
        const SizedBox(height: AppTheme.space16),
        ...slots.map((s) => _buildSlotCard(s['key']!, s['label']!, s['desc']!)),
      ],
    );
  }

  /// 计算槽位聚合健康状态: 0=空, 1=全部健康, 2=降级, 3=全部不可用
  int _getSlotHealthLevel(List<SlotCandidate> candidates) {
    if (candidates.isEmpty) return 0;
    int healthyCount = 0;
    for (final c in candidates) {
      if (AiService.instance.getProviderHealth(c.providerId)?.isHealthy !=
          false) {
        healthyCount++;
      }
    }
    if (healthyCount == candidates.length) return 1;
    if (healthyCount > 0) return 2;
    return 3;
  }

  Color _healthColor(BuildContext context, int level) {
    switch (level) {
      case 1:
        return context.successSolid;
      case 2:
        return context.warningSolid;
      case 3:
        return context.errorSolid;
      default:
        return context.textTertiary;
    }
  }

  String _healthLabel(int level) {
    switch (level) {
      case 1:
        return '全部健康';
      case 2:
        return '已降级';
      case 3:
        return '全部不可用';
      default:
        return '未配置';
    }
  }

  Widget _buildSlotCard(String slotKey, String label, String desc) {
    final candidates = store.slotBindings[slotKey] ?? <SlotCandidate>[];
    final healthLevel = _getSlotHealthLevel(candidates);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.space16),
      child: AppCard(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行：槽位名称 + 健康指示器 + 添加按钮
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              label,
                              style: AppTheme.fontBody.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: AppTheme.space8),
                            // 聚合健康指示器
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _healthColor(
                                  context,
                                  healthLevel,
                                ).withValues(alpha: 0.15),
                                borderRadius: AppTheme.borderRadiusSmall,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: _healthColor(context, healthLevel),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _healthLabel(healthLevel),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: _healthColor(context, healthLevel),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: AppTheme.space2),
                        Text(
                          desc,
                          style: AppTheme.fontCaption.copyWith(
                            color: context.textTertiary,
                          ),
                        ),
                        // 降级/不可用时显示额外信息
                        if (healthLevel == 2) ...[
                          const SizedBox(height: AppTheme.space4),
                          Builder(
                            builder: (_) {
                              // 找到当前活跃的供应商（第一个健康的）
                              for (final c in candidates) {
                                final health = AiService.instance
                                    .getProviderHealth(c.providerId);
                                if (health?.isHealthy != false) {
                                  final provider = store.providers
                                      .cast<AiProviderConfig?>()
                                      .firstWhere(
                                        (p) => p!.id == c.providerId,
                                        orElse: () => null,
                                      );
                                  return Text(
                                    '当前活跃: ${provider?.name ?? c.providerId}',
                                    style: AppTheme.fontCaption.copyWith(
                                      color: context.warningText,
                                    ),
                                  );
                                }
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ],
                        if (healthLevel == 3) ...[
                          SizedBox(height: AppTheme.space4),
                          Text(
                            '请检查供应商配置或网络连接',
                            style: AppTheme.fontCaption.copyWith(
                              color: context.errorText,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  AppButton.secondary(
                    label: '添加候选',
                    icon: Icons.add,
                    onPressed: () => _showAddCandidateDialog(slotKey),
                  ),
                ],
              ),
              // 候选列表
              if (candidates.isNotEmpty) ...[
                SizedBox(height: AppTheme.space12),
                Divider(height: 1, color: context.borderSubtle),
                const SizedBox(height: AppTheme.space8),
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: candidates.length,
                  onReorder: (oldIndex, newIndex) async {
                    await store.reorderSlotCandidates(
                      slotKey,
                      oldIndex,
                      newIndex,
                    );
                    setState(() {});
                  },
                  proxyDecorator: (child, index, animation) {
                    return Material(
                      color: Colors.transparent,
                      elevation: 4,
                      child: child,
                    );
                  },
                  itemBuilder: (context, index) {
                    final candidate = candidates[index];
                    final provider = store.providers
                        .cast<AiProviderConfig?>()
                        .firstWhere(
                          (p) => p!.id == candidate.providerId,
                          orElse: () => null,
                        );
                    final providerName = provider?.name ?? '未知供应商';
                    final health = AiService.instance.getProviderHealth(
                      candidate.providerId,
                    );
                    final isHealthy = health?.isHealthy != false;
                    final candidateHealthColor = isHealthy
                        ? context.successSolid
                        : context.errorSolid;

                    return Container(
                      key: ValueKey(
                        '${slotKey}_${candidate.providerId}_${candidate.model}_$index',
                      ),
                      margin: const EdgeInsets.only(bottom: AppTheme.space4),
                      padding: EdgeInsets.symmetric(
                        horizontal: AppTheme.space12,
                        vertical: AppTheme.space8,
                      ),
                      decoration: BoxDecoration(
                        color: context.bgSidebar,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: context.borderSubtle,
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          // 拖拽手柄
                          ReorderableDragStartListener(
                            index: index,
                            child: Icon(
                              Icons.drag_indicator,
                              size: 16,
                              color: context.textTertiary,
                            ),
                          ),
                          const SizedBox(width: AppTheme.space8),
                          // 优先级编号
                          Container(
                            width: 22,
                            height: 22,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: context.accentText.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: context.accentText,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppTheme.space12),
                          // 健康指示圆点
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: candidateHealthColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: AppTheme.space8),
                          // 供应商名称
                          Text(
                            providerName,
                            style: AppTheme.fontBody.copyWith(fontSize: 13),
                          ),
                          const SizedBox(width: AppTheme.space8),
                          // 模型名
                          Expanded(
                            child: Text(
                              candidate.model.isEmpty
                                  ? '(未指定模型)'
                                  : candidate.model,
                              style: AppTheme.fontCaption.copyWith(
                                color: context.textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // 不健康时显示错误摘要
                          if (!isHealthy && health?.lastError != null)
                            Tooltip(
                              message: health!.lastError!,
                              child: Icon(
                                Icons.warning_amber_rounded,
                                size: 14,
                                color: context.warningText,
                              ),
                            ),
                          const SizedBox(width: AppTheme.space4),
                          // 删除按钮
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              size: 14,
                              color: context.textTertiary,
                            ),
                            tooltip: '移除候选',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              maxWidth: 24,
                              maxHeight: 24,
                            ),
                            onPressed: () async {
                              await store.removeSlotCandidate(slotKey, index);
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ] else ...[
                SizedBox(height: AppTheme.space12),
                Center(
                  child: Text(
                    '暂无候选供应商，点击"添加候选"配置',
                    style: AppTheme.fontCaption.copyWith(
                      color: context.textTertiary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 添加候选弹窗：选择供应商 → 选择模型
  void _showAddCandidateDialog(String slotKey) {
    String? selectedProviderId;
    String? selectedModel;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final providers = store.providers;
          List<String> availableModels = [];
          if (selectedProviderId != null) {
            final provider = providers.firstWhere(
              (p) => p.id == selectedProviderId,
              orElse: () => const AiProviderConfig(
                id: '',
                name: '',
                protocol: AiProtocolType.openai,
                baseUrl: '',
                keychainKeyId: '',
              ),
            );
            availableModels = provider.textModels;
          }

          return AlertDialog(
            backgroundColor: context.bgCard,
            title: const Text('添加槽位候选', style: AppTheme.fontTitle),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedProviderId,
                    decoration: const InputDecoration(labelText: '选择供应商'),
                    items: providers
                        .map(
                          (p) => DropdownMenuItem(
                            value: p.id,
                            child: Text(p.name),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      setDialogState(() {
                        selectedProviderId = val;
                        selectedModel = null;
                      });
                    },
                  ),
                  const SizedBox(height: AppTheme.space12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedModel,
                    decoration: const InputDecoration(labelText: '选择模型'),
                    items: availableModels
                        .map(
                          (m) => DropdownMenuItem(
                            value: m,
                            child: Text(m, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      setDialogState(() => selectedModel = val);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              AppButton.ghost(label: '取消', onPressed: () => Navigator.pop(ctx)),
              AppButton.primary(
                label: '添加',
                onPressed: selectedProviderId != null
                    ? () async {
                        await store.addSlotCandidate(
                          slotKey,
                          selectedProviderId!,
                          selectedModel ?? '',
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        setState(() {});
                      }
                    : null,
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 3: 外部 MCP 客户端（客户端配置 + 已加载工具清单）
  // ---------------------------------------------------------------------------
  Widget _buildMcpWithInventory() {
    final clients = store.mcpClients;
    return ListView(
      padding: const EdgeInsets.all(AppTheme.space24),
      children: [
        ..._buildMcpClientCards(clients),
        // 清单由独立 widget 承担，便于 widget 测试直接驱动。
        McpToolInventoryView(clients: clients, probeResults: _mcpTestResults),
      ],
    );
  }

  List<Widget> _buildMcpClientCards(List<McpClientConfig> clients) {
    return [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('外部第三方 MCP 服务 (${clients.length})', style: AppTheme.fontTitle),
            Row(
              children: [
                AppButton.secondary(
                  label: '一键添加 Firecrawl 预置',
                  icon: Icons.auto_awesome,
                  onPressed: () async {
                    final exists = clients.any((c) => c.id == 'mcp_firecrawl');
                    if (!exists) {
                      await store.saveMcpClient(
                        McpClientConfig.firecrawlPreset(),
                      );
                      setState(() {});
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '已添加 Firecrawl 官方 MCP 预置，建议点击“测试连接”验证。',
                            ),
                            backgroundColor: context.successSolid,
                          ),
                        );
                      }
                    } else {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Firecrawl 预置已存在，无需重复添加。'),
                          ),
                        );
                      }
                    }
                  },
                ),
                const SizedBox(width: AppTheme.space12),
                AppButton.primary(
                  label: '添加 MCP 服务',
                  icon: Icons.add,
                  onPressed: () => _showAddOrEditMcpDialog(),
                ),
              ],
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
                    Icon(
                      Icons.cable_outlined,
                      size: 36,
                      color: context.textTertiary,
                    ),
                    SizedBox(height: AppTheme.space12),
                    Text(
                      '暂未配置外部 MCP 客户端',
                      style: AppTheme.fontBody.copyWith(
                        color: context.textSecondary,
                      ),
                    ),
                    SizedBox(height: AppTheme.space8),
                    Text(
                      '可配置已运行的第三方 Model Context Protocol 服务的连接端点或命令行调用。',
                      style: AppTheme.fontCaption.copyWith(
                        color: context.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ...clients.map((c) {
            final isTesting = _mcpTesting[c.id] ?? false;
            final testResult = _mcpTestResults[c.id];
            final fullCmd = [c.endpointOrCommand, ...c.args].join(' ');

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
                          Icon(
                            Icons.settings_input_component_outlined,
                            size: 20,
                            color: c.enabled
                                ? context.accentText
                                : context.textTertiary,
                          ),
                          const SizedBox(width: AppTheme.space8),
                          Text(c.name, style: AppTheme.fontTitle),
                          const SizedBox(width: AppTheme.space8),
                          AppBadge(label: c.transport.toUpperCase()),
                          const SizedBox(width: AppTheme.space8),
                          if (testResult != null) ...[
                            AppBadge(
                              label: testResult.isHealthy
                                  ? '已连通 (${testResult.toolCount} 工具)'
                                  : '连通异常',
                              color: testResult.isHealthy
                                  ? context.successSolid
                                  : context.errorSolid,
                            ),
                            if (testResult.remoteReachable != null) ...[
                              const SizedBox(width: AppTheme.space6),
                              AppBadge(
                                label: testResult.remoteReachable!
                                    ? '远端可达'
                                    : '远端不可达',
                                color: testResult.remoteReachable!
                                    ? context.successSolid
                                    : context.warningSolid,
                              ),
                            ],
                          ],
                          const Spacer(),
                          Text(
                            c.enabled ? '已启用' : '已停用',
                            style: AppTheme.fontCaption,
                          ),
                          Switch(
                            value: c.enabled,
                            activeThumbColor: context.accentText,
                            onChanged: (val) async {
                              await store.saveMcpClient(
                                c.copyWith(enabled: val),
                              );
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTheme.space8),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: context.bgContent.withAlpha(128),
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusSmall,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.terminal,
                              size: 14,
                              color: context.textTertiary,
                            ),
                            const SizedBox(width: AppTheme.space6),
                            Expanded(
                              child: Text(
                                fullCmd,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: context.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (c.env.isNotEmpty) ...[
                        const SizedBox(height: AppTheme.space6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: c.env.keys.map((k) {
                            return Chip(
                              labelPadding: EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: context.bgContent,
                              side: BorderSide.none,
                              label: Text(
                                '$k=***',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                  color: context.textTertiary,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      if (testResult != null &&
                          !testResult.isHealthy &&
                          testResult.lastError != null) ...[
                        SizedBox(height: AppTheme.space8),
                        Container(
                          padding: EdgeInsets.all(AppTheme.space8),
                          decoration: BoxDecoration(
                            color: context.errorText.withAlpha(25),
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusSmall,
                            ),
                            border: Border.all(
                              color: context.errorText.withAlpha(60),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 16,
                                color: context.errorText,
                              ),
                              SizedBox(width: AppTheme.space8),
                              Expanded(
                                child: Text(
                                  testResult.lastError!,
                                  style: AppTheme.fontCaption.copyWith(
                                    color: context.errorText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: AppTheme.space12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          AppButton.secondary(
                            label: isTesting ? '正在探测...' : '测试连接与探测工具',
                            icon: isTesting
                                ? Icons.hourglass_top
                                : Icons.bolt_outlined,
                            onPressed: isTesting
                                ? null
                                : () => _testMcpClient(c),
                          ),
                          const SizedBox(width: AppTheme.space8),
                          AppButton.ghost(
                            label: '编辑',
                            icon: Icons.edit_outlined,
                            onPressed: () => _showAddOrEditMcpDialog(client: c),
                          ),
                          SizedBox(width: AppTheme.space8),
                          IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              size: 16,
                              color: context.errorText,
                            ),
                            tooltip: '删除 MCP 服务',
                            onPressed: () async {
                              await store.deleteMcpClient(c.id);
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
    ];
  }


  // ---------------------------------------------------------------------------
  // 弹窗与交互逻辑
  // ---------------------------------------------------------------------------
  void _showAddOrEditProviderDialog({AiProviderConfig? provider}) {
    final isEditing = provider != null;
    final nameCtrl = TextEditingController(text: provider?.name ?? '');
    final urlCtrl = TextEditingController(
      text: provider?.baseUrl ?? 'https://api.openai.com/v1',
    );
    final keyCtrl = TextEditingController();
    final modelsCtrl = TextEditingController(
      text: provider?.textModels.join(', ') ?? '',
    );
    AiProtocolType protocol = provider?.protocol ?? AiProtocolType.openai;
    bool isDetecting = false;
    bool isSaving = false;

    // 密钥默认遮蔽；眼睛图标切换明暗。编辑已有供应商且字段为空时，首次点眼睛
    // 会从密钥库载入已存密钥供核对（design D4），并在保存时跳过冗余写入。
    bool keyVisible = false;
    bool keyLoadedFromStore = false;
    bool keyLoading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: context.bgCard,
          title: Row(
            children: [
              Text(
                isEditing ? '编辑 AI 供应商' : '添加 AI 供应商',
                style: AppTheme.fontTitle,
              ),
              if (isEditing) ...[
                const SizedBox(width: AppTheme.space8),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: context.successText.withValues(alpha: 0.15),
                    borderRadius: AppTheme.borderRadiusSmall,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 12,
                        color: context.successText,
                      ),
                      SizedBox(width: 4),
                      Text(
                        '已加密存储',
                        style: TextStyle(fontSize: 11, color: context.successText),
                      ),
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
                        avatar: Icon(
                          Icons.bolt,
                          size: 14,
                          color: context.accentText,
                        ),
                        label: const Text(
                          'DeepSeek',
                          style: TextStyle(fontSize: 11),
                        ),
                        onPressed: () {
                          setDialogState(() {
                            nameCtrl.text = 'DeepSeek';
                            protocol = AiProtocolType.openai;
                            urlCtrl.text = 'https://api.deepseek.com/v1';
                            modelsCtrl.text =
                                'deepseek-chat, deepseek-reasoner';
                          });
                        },
                      ),
                      ActionChip(
                        label: const Text(
                          'OpenAI',
                          style: TextStyle(fontSize: 11),
                        ),
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
                        label: const Text(
                          'Claude',
                          style: TextStyle(fontSize: 11),
                        ),
                        onPressed: () {
                          setDialogState(() {
                            nameCtrl.text = 'Anthropic Claude';
                            protocol = AiProtocolType.anthropic;
                            urlCtrl.text = 'https://api.anthropic.com';
                            modelsCtrl.text =
                                'claude-3-7-sonnet-20250219, claude-3-5-sonnet-20241022, claude-3-5-haiku-20241022';
                          });
                        },
                      ),
                      ActionChip(
                        label: const Text(
                          'Gemini',
                          style: TextStyle(fontSize: 11),
                        ),
                        onPressed: () {
                          setDialogState(() {
                            nameCtrl.text = 'Google Gemini';
                            protocol = AiProtocolType.gemini;
                            urlCtrl.text =
                                'https://generativelanguage.googleapis.com';
                            modelsCtrl.text =
                                'gemini-2.5-pro, gemini-2.5-flash, gemini-2.0-flash';
                          });
                        },
                      ),
                      ActionChip(
                        label: const Text(
                          'Ollama(本地)',
                          style: TextStyle(fontSize: 11),
                        ),
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
                        label: const Text(
                          '硅基流动',
                          style: TextStyle(fontSize: 11),
                        ),
                        onPressed: () {
                          setDialogState(() {
                            nameCtrl.text = '硅基流动 (SiliconFlow)';
                            protocol = AiProtocolType.openai;
                            urlCtrl.text = 'https://api.siliconflow.cn/v1';
                            modelsCtrl.text =
                                'deepseek-ai/DeepSeek-V3, deepseek-ai/DeepSeek-R1';
                          });
                        },
                      ),
                    ],
                  ),
                  const Divider(height: AppTheme.space24),
                  AppTextField(
                    controller: nameCtrl,
                    label: '供应商名称',
                    hintText: '如 OpenAI / DeepSeek / Ollama',
                  ),
                  const SizedBox(height: AppTheme.space12),
                  DropdownButtonFormField<AiProtocolType>(
                    initialValue: protocol,
                    decoration: const InputDecoration(labelText: '协议类型'),
                    items: AiProtocolType.values
                        .map(
                          (p) =>
                              DropdownMenuItem(value: p, child: Text(p.label)),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => protocol = val);
                    },
                  ),
                  const SizedBox(height: AppTheme.space12),
                  AppTextField(
                    controller: urlCtrl,
                    label: 'API Base URL',
                    hintText: 'https://api.openai.com/v1',
                  ),
                  const SizedBox(height: AppTheme.space12),
                  AppTextField(
                    controller: keyCtrl,
                    label: isEditing ? 'API Key (已安全保存，若不修改请留空)' : 'API Key',
                    hintText: isEditing ? '留空则保持原有密钥不变' : 'sk-...',
                    obscureText: !keyVisible,
                    suffixIcon: keyLoading
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: Icon(
                              keyVisible
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              size: 16,
                              color: context.textSecondary,
                            ),
                            tooltip: keyVisible ? '隐藏密钥' : '显示密钥',
                            onPressed: () async {
                              // 编辑态且字段为空：先把已存密钥载入输入框再显示，
                              // 否则用户点了眼睛也只看到一片空白。
                              if (!keyVisible &&
                                  isEditing &&
                                  keyCtrl.text.isEmpty &&
                                  !keyLoadedFromStore) {
                                setDialogState(() => keyLoading = true);
                                try {
                                  final stored = await KeychainService.instance
                                      .readSecret(provider!.keychainKeyId);
                                  if (stored == null || stored.isEmpty) {
                                    if (ctx.mounted) {
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '未能从密钥库载入已保存的密钥，可能已被清除',
                                          ),
                                          backgroundColor: context.warningSolid,
                                          duration: Duration(seconds: 6),
                                        ),
                                      );
                                    }
                                    return;
                                  }
                                  keyCtrl.text = stored;
                                  keyLoadedFromStore = true;
                                  setDialogState(() => keyVisible = true);
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          '已载入已保存的密钥（仅用于查看；未修改则保存时不会重复写入）',
                                        ),
                                        duration: Duration(seconds: 4),
                                      ),
                                    );
                                  }
                                } finally {
                                  if (ctx.mounted)
                                    setDialogState(() => keyLoading = false);
                                }
                                return;
                              }
                              setDialogState(() => keyVisible = !keyVisible);
                            },
                          ),
                  ),
                  const SizedBox(height: AppTheme.space12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('支持的模型 (逗号分隔)', style: AppTheme.fontCaption),
                      if (isDetecting)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        TextButton.icon(
                          icon: const Icon(Icons.auto_awesome, size: 14),
                          label: const Text(
                            '自动探测发现',
                            style: TextStyle(fontSize: 12),
                          ),
                          onPressed: () async {
                            setDialogState(() => isDetecting = true);
                            try {
                              String keyToUse = keyCtrl.text.trim();
                              if (keyToUse.isEmpty && provider != null) {
                                keyToUse =
                                    await KeychainService.instance.readSecret(
                                      provider.keychainKeyId,
                                    ) ??
                                    '';
                              }

                              if (keyToUse.isEmpty &&
                                  !urlCtrl.text.contains('localhost') &&
                                  !urlCtrl.text.contains('127.0.0.1')) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text('请先输入 API Key 再进行自动探测'),
                                      backgroundColor: context.warningSolid,
                                    ),
                                  );
                                }
                                return;
                              }

                              final tempProv = AiProviderConfig(
                                id:
                                    provider?.id ??
                                    'temp_${DateTime.now().millisecondsSinceEpoch}',
                                name: nameCtrl.text.trim().isEmpty
                                    ? '临时供应商'
                                    : nameCtrl.text.trim(),
                                protocol: protocol,
                                baseUrl: urlCtrl.text.trim(),
                                keychainKeyId:
                                    provider?.keychainKeyId ?? 'temp',
                              );
                              final found = await AiService.instance
                                  .discoverModels(
                                    tempProv,
                                    apiKey: keyToUse.isNotEmpty
                                        ? keyToUse
                                        : null,
                                  );
                              setDialogState(() {
                                modelsCtrl.text = found.join(', ');
                              });
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '✓ 成功探测到 ${found.length} 个可用模型！',
                                    ),
                                    backgroundColor: context.successSolid,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: Text('探测失败: $e'),
                                    backgroundColor: context.errorSolid,
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
                  AppTextField(
                    controller: modelsCtrl,
                    maxLines: 2,
                    hintText: '如 gpt-4o, gpt-4o-mini',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            AppButton.ghost(
              label: '取消',
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
            ),
            AppButton.primary(
              label: '保存',
              isLoading: isSaving,
              onPressed: isSaving
                  ? null
                  : () async {
                      setDialogState(() => isSaving = true);
                      try {
                        final id =
                            provider?.id ??
                            'provider_${DateTime.now().millisecondsSinceEpoch}';
                        final keyId = provider?.keychainKeyId ?? 'key_$id';
                        final models = modelsCtrl.text
                            .split(',')
                            .map((s) => s.trim())
                            .where((s) => s.isNotEmpty)
                            .toList();

                        final newProv = AiProviderConfig(
                          id: id,
                          name: nameCtrl.text.trim().isEmpty
                              ? '未命名供应商'
                              : nameCtrl.text.trim(),
                          protocol: protocol,
                          baseUrl: urlCtrl.text.trim(),
                          keychainKeyId: keyId,
                          textModels: models,
                        );

                        AiService.instance.invalidateProviderEndpoint(id);
                        // 载入已存密钥后未修改时，值与库里一致——跳过写入，避免冗余。
                        final enteredKey = keyCtrl.text.trim();
                        final skipKeyWrite =
                            keyLoadedFromStore &&
                            enteredKey ==
                                (await KeychainService.instance.readSecret(
                                      keyId,
                                    ) ??
                                    '');
                        await store.saveProvider(
                          newProv,
                          apiKey: (enteredKey.isEmpty || skipKeyWrite)
                              ? null
                              : enteredKey,
                        );
                        // 失配自愈信号：若本次保存触发了密钥库重建，告知用户其他已存密钥需重填
                        final rebuild = KeychainService.instance
                            .consumeRebuildInfo();
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (rebuild != null && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '供应商已保存。\n⚠️ 密钥库此前因密钥失配已重置，其他已存密钥（如其他供应商的 API Key）需重新填入。\n残件备份: ${rebuild.backupPath}',
                              ),
                              backgroundColor: context.warningSolid,
                              duration: const Duration(seconds: 10),
                            ),
                          );
                        }
                        setState(() {});
                      } on KeychainWriteException catch (e) {
                        // 配置已落盘，仅密钥写入失败——关闭弹窗并明确告知
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '供应商配置已保存，但 $e\n可稍后在编辑界面重新填入 API Key 保存。',
                              ),
                              backgroundColor: context.warningSolid,
                              duration: const Duration(seconds: 8),
                            ),
                          );
                          setState(() {});
                        }
                      } catch (e) {
                        // 其他异常（如密钥库 DEK 不可用）：配置亦可能未保存，留在弹窗内提示
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text('保存失败: $e'),
                              backgroundColor: context.errorSolid,
                              duration: const Duration(seconds: 8),
                            ),
                          );
                        }
                      } finally {
                        if (ctx.mounted) setDialogState(() => isSaving = false);
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  void _showAddOrEditMcpDialog({McpClientConfig? client}) {
    final isEditing = client != null;
    final nameCtrl = TextEditingController(text: client?.name ?? '');
    final cmdCtrl = TextEditingController(
      text: client?.endpointOrCommand ?? '',
    );
    final argsCtrl = TextEditingController(text: client?.args.join(' ') ?? '');
    final timeoutCtrl = TextEditingController(
      text: (client?.timeoutSeconds ?? 60).toString(),
    );

    final envSb = StringBuffer();
    if (client != null) {
      client.env.forEach((k, v) => envSb.writeln('$k=$v'));
    }
    final envCtrl = TextEditingController(text: envSb.toString().trim());
    String transport = client?.transport ?? 'stdio';

    void fillFirecrawlPreset(void Function(void Function()) setDialogState) {
      setDialogState(() {
        final preset = McpClientConfig.firecrawlPreset();
        nameCtrl.text = preset.name;
        transport = preset.transport;
        cmdCtrl.text = preset.endpointOrCommand;
        argsCtrl.text = preset.args.join(' ');
        timeoutCtrl.text = preset.timeoutSeconds.toString();
        final sb = StringBuffer();
        preset.env.forEach((k, v) => sb.writeln('$k=$v'));
        envCtrl.text = sb.toString().trim();
      });
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: context.bgCard,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isEditing ? '编辑外部 MCP 客户端' : '添加外部 MCP 客户端',
                style: AppTheme.fontTitle,
              ),
              TextButton.icon(
                icon: Icon(
                  Icons.auto_awesome,
                  size: 14,
                  color: context.accentText,
                ),
                label: Text(
                  '填入 Firecrawl 模板',
                  style: TextStyle(color: context.accentText, fontSize: 12),
                ),
                onPressed: () => fillFirecrawlPreset(setDialogState),
              ),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTextField(
                    controller: nameCtrl,
                    label: '服务名称',
                    hintText: '如 Firecrawl 爬虫与搜索 / Filesystem',
                  ),
                  const SizedBox(height: AppTheme.space12),
                  DropdownButtonFormField<String>(
                    initialValue: transport,
                    decoration: const InputDecoration(labelText: '通信方式'),
                    items: const [
                      DropdownMenuItem(
                        value: 'stdio',
                        child: Text('标准输入输出 (stdio)'),
                      ),
                      DropdownMenuItem(
                        value: 'sse',
                        child: Text('Server-Sent Events (SSE / HTTP)'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => transport = val);
                    },
                  ),
                  const SizedBox(height: AppTheme.space12),
                  AppTextField(
                    controller: cmdCtrl,
                    label: transport == 'stdio' ? '启动命令 / 可执行程序' : '服务 URL',
                    hintText: transport == 'stdio'
                        ? 'npx'
                        : 'http://localhost:8000/sse',
                  ),
                  if (transport == 'stdio') ...[
                    const SizedBox(height: AppTheme.space12),
                    AppTextField(
                      controller: argsCtrl,
                      label: '命令行参数 (以空格或逗号分隔)',
                      hintText: '-y firecrawl-mcp',
                    ),
                    const SizedBox(height: AppTheme.space12),
                    AppTextField(
                      controller: envCtrl,
                      label: '环境变量 (每行一个 KEY=VALUE)',
                      hintText:
                          'FIRECRAWL_API_URL=https://43-133-77-38.nip.io\nFIRECRAWL_API_KEY=your_token',
                      maxLines: 4,
                    ),
                  ],
                  const SizedBox(height: AppTheme.space12),
                  AppTextField(
                    controller: timeoutCtrl,
                    label: '超时时间 (秒)',
                    hintText: '60',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            AppButton.ghost(label: '取消', onPressed: () => Navigator.pop(ctx)),
            AppButton.primary(
              label: '保存',
              onPressed: () async {
                // 解析 args
                final rawArgs = argsCtrl.text.trim();
                final List<String> parsedArgs = [];
                if (rawArgs.isNotEmpty) {
                  final parts = rawArgs.contains(',')
                      ? rawArgs
                            .split(',')
                            .map((s) => s.trim())
                            .where((s) => s.isNotEmpty)
                            .toList()
                      : rawArgs
                            .split(RegExp(r'\s+'))
                            .where((s) => s.isNotEmpty)
                            .toList();
                  parsedArgs.addAll(parts);
                }

                // 解析 env
                final Map<String, String> parsedEnv = {};
                for (final line in envCtrl.text.split('\n')) {
                  final trimmed = line.trim();
                  if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
                  final eqIdx = trimmed.indexOf('=');
                  if (eqIdx > 0) {
                    final k = trimmed.substring(0, eqIdx).trim();
                    final v = trimmed.substring(eqIdx + 1).trim();
                    if (k.isNotEmpty) parsedEnv[k] = v;
                  }
                }

                final id =
                    client?.id ??
                    'mcp_${DateTime.now().millisecondsSinceEpoch}';
                final newClient = McpClientConfig(
                  id: id,
                  name: nameCtrl.text.trim().isEmpty
                      ? '未命名 MCP 服务'
                      : nameCtrl.text.trim(),
                  transport: transport,
                  endpointOrCommand: cmdCtrl.text.trim(),
                  args: parsedArgs,
                  env: parsedEnv,
                  timeoutSeconds: int.tryParse(timeoutCtrl.text.trim()) ?? 60,
                  enabled: client?.enabled ?? true,
                );

                await store.saveMcpClient(newClient);
                if (ctx.mounted) Navigator.pop(ctx);
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  void _testMcpClient(McpClientConfig c) async {
    setState(() => _mcpTesting[c.id] = true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('正在与 MCP 服务 [${c.name}] 握手并探测工具...')),
    );
    try {
      final res = await McpService.instance.testConnection(c);
      setState(() {
        _mcpTestResults[c.id] = res;
        _mcpTesting[c.id] = false;
      });
      messenger.clearSnackBars();
      if (res.isHealthy) {
        final toolNames = res.tools.take(5).map((t) => t.name).join(', ');
        final more = res.tools.length > 5 ? ' 等 ${res.tools.length} 个工具' : '';
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '✓ MCP [${c.name}] 握手成功！探测到 ${res.toolCount} 个工具: $toolNames$more',
            ),
            backgroundColor: context.successSolid,
            duration: const Duration(seconds: 6),
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text('✕ MCP [${c.name}] 连接失败: ${res.lastError}'),
            backgroundColor: context.errorSolid,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } catch (e) {
      setState(() => _mcpTesting[c.id] = false);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text('✕ 测试异常: $e'),
          backgroundColor: context.errorSolid,
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  void _testProvider(AiProviderConfig p) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('正在测试连接与真机对话 Ping...')),
    );
    try {
      await AiService.instance.testConnection(p);
      final models = await AiService.instance.discoverModels(p);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text('✓ 连接与真机对话测试均通过！已探测到 ${models.length} 个模型'),
          backgroundColor: context.successSolid,
        ),
      );
    } catch (e) {
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text('✕ 连接测试失败: $e'),
          backgroundColor: context.errorSolid,
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  void _deleteProvider(AiProviderConfig p) async {
    AiService.instance.invalidateProviderEndpoint(p.id);
    await store.deleteProvider(p.id);
    setState(() {});
  }
}
