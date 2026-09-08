import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../components/app_components.dart';
import '../../../components/markdown_view.dart';
import '../../../services/mcp_service.dart';
import '../../../theme/app_theme.dart';
import '../services/ai_assistant_service.dart';
import 'scheduled_tasks_drawer.dart';

class AiAssistantPage extends StatefulWidget {
  const AiAssistantPage({super.key});

  @override
  State<AiAssistantPage> createState() => _AiAssistantPageState();
}

class _AiAssistantPageState extends State<AiAssistantPage> {
  final _service = AiAssistantService.instance;
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceUpdate);
    _service.init();
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceUpdate);
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) {
      setState(() {});
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleSend([String? presetText]) {
    final text = presetText ?? _textCtrl.text.trim();
    if (text.isEmpty || _service.isProcessing) return;
    _textCtrl.clear();
    _service.sendMessage(text);
    _focusNode.requestFocus();
  }

  void _showMcpToolsDialog() async {
    final tools = await McpService.instance.getAllTools();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Row(
          children: [
            const Icon(Icons.cable_outlined, color: AppTheme.accentLight, size: 20),
            const SizedBox(width: AppTheme.space8),
            Text('已加载的 MCP 外部工具 (${tools.length})', style: AppTheme.fontTitle),
          ],
        ),
        content: SizedBox(
          width: 580,
          height: 400,
          child: tools.isEmpty
              ? const Center(
                  child: Text('当前暂无启用的 MCP 工具，请先在 AI 设置中配置并启用。', style: TextStyle(color: AppTheme.textSecondary)),
                )
              : ListView.separated(
                  itemCount: tools.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.borderSubtle),
                  itemBuilder: (ctx, idx) {
                    final t = tools[idx];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.bolt, size: 16, color: AppTheme.accentLight),
                      title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text(
                        t.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                      trailing: AppBadge(label: t.serverName),
                    );
                  },
                ),
        ),
        actions: [
          AppButton.primary(label: '确定', onPressed: () => Navigator.pop(ctx)),
        ],
      ),
    );
  }

  void _openScheduledTasksDrawer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const ScheduledTasksDrawer(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = _service.messages;

    return Scaffold(
      backgroundColor: AppTheme.bgContent,
      body: Column(
        children: [
          // 顶部标题与功能操作栏
          _buildHeader(),

          // 聊天视口
          Expanded(
            child: messages.isEmpty ? _buildEmptyView() : _buildMessagesList(messages),
          ),

          // 底部输入栏
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.space24, vertical: AppTheme.space16),
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          const Icon(Icons.assistant_outlined, color: AppTheme.accentLight, size: 24),
          const SizedBox(width: AppTheme.space12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('AI 资讯与检索助手', style: AppTheme.fontTitle),
              Text(
                '结合全网实时爬虫与检索 MCP，探索深度情报并跟踪最新资讯',
                style: AppTheme.fontCaption.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ),
          const Spacer(),
          AppButton.secondary(
            label: 'MCP 工具清单',
            icon: Icons.cable_outlined,
            onPressed: _showMcpToolsDialog,
          ),
          const SizedBox(width: AppTheme.space8),
          AppButton.secondary(
            label: '定时资讯任务',
            icon: Icons.notifications_active_outlined,
            onPressed: _openScheduledTasksDrawer,
          ),
          const SizedBox(width: AppTheme.space8),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, size: 20, color: AppTheme.textSecondary),
            tooltip: '清空会话历史',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppTheme.bgCard,
                  title: const Text('确认清空会话', style: AppTheme.fontTitle),
                  content: const Text('清空后所有历史问答和检索记录将无法恢复。'),
                  actions: [
                    AppButton.ghost(label: '取消', onPressed: () => Navigator.pop(ctx, false)),
                    AppButton.danger(label: '清空', onPressed: () => Navigator.pop(ctx, true)),
                  ],
                ),
              );
              if (ok == true) {
                await _service.clearHistory();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.accentLight.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome, size: 48, color: AppTheme.accentLight),
            ),
            const SizedBox(height: AppTheme.space16),
            const Text('全网数据检索与智能问答', style: AppTheme.fontTitle),
            const SizedBox(height: AppTheme.space8),
            Text(
              '你可以直接提问，助手会自主选择 Firecrawl 等 MCP 工具进行实时搜索与网页抓取',
              style: AppTheme.fontBody.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: AppTheme.space24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                _buildPromptChip('🔍 搜索美联储 2026 最新利率预测与市场动态'),
                _buildPromptChip('📰 检索关于 AI Agent 智能体的最新前沿研报'),
                _buildPromptChip('🌐 抓取并解析指定网页正文内容与核心观点'),
                _buildPromptChip('📊 总结科技与大模型开源社区今日头条'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptChip(String text) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      onTap: () => _handleSend(text),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: AppTheme.borderSubtle),
        ),
        child: Text(text, style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary)),
      ),
    );
  }

  Widget _buildMessagesList(List<ChatMessage> messages) {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(AppTheme.space24),
      itemCount: messages.length,
      itemBuilder: (ctx, idx) {
        final msg = messages[idx];
        return _buildMessageBubble(msg);
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    if (msg.isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppTheme.space16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(AppTheme.space12),
                decoration: BoxDecoration(
                  color: AppTheme.accentLight.withAlpha(40),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  border: Border.all(color: AppTheme.accentLight.withAlpha(80)),
                ),
                child: SelectableText(
                  msg.content,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, height: 1.5),
                ),
              ),
            ),
            const SizedBox(width: AppTheme.space10),
            const CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.bgCard,
              child: Icon(Icons.person, size: 18, color: AppTheme.textPrimary),
            ),
          ],
        ),
      );
    }

    // Assistant bubble
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.space16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 16,
            backgroundColor: AppTheme.accentLight,
            child: Icon(Icons.smart_toy_outlined, size: 18, color: Colors.white),
          ),
          const SizedBox(width: AppTheme.space10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 工具调用徽章
                if (msg.toolCalls.isNotEmpty) ...[
                  ...msg.toolCalls.map((t) => _buildToolCallBadge(t)),
                  const SizedBox(height: AppTheme.space8),
                ],
                Container(
                  padding: const EdgeInsets.all(AppTheme.space16),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppMarkdownView(
                        data: msg.content,
                        baseStyle: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, height: 1.6),
                        // 超长回答在气泡内部滚动，避免顶高整个对话列表、淹没输入栏
                        maxHeight: MediaQuery.of(context).size.height * 0.6,
                      ),
                      const SizedBox(height: AppTheme.space8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.copy_outlined, size: 14, color: AppTheme.textTertiary),
                            tooltip: '复制回答',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: msg.content));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已复制到剪贴板')),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolCallBadge(ToolCallInfo t) {
    IconData icon;
    Color color;
    String statusText;

    switch (t.status) {
      case ToolCallStatus.running:
        icon = Icons.hourglass_top;
        color = AppTheme.warning;
        statusText = '正在调用...';
        break;
      case ToolCallStatus.success:
        icon = Icons.check_circle_outline;
        color = AppTheme.success;
        statusText = '执行成功';
        break;
      case ToolCallStatus.failed:
        icon = Icons.error_outline;
        color = AppTheme.error;
        statusText = '执行受阻';
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: AppTheme.space6),
          Text(
            '${t.toolName} ($statusText)',
            style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: color, fontWeight: FontWeight.bold),
          ),
          if (t.error != null) ...[
            const SizedBox(width: AppTheme.space8),
            Flexible(
              child: Text(
                t.error!,
                style: const TextStyle(fontSize: 11, color: AppTheme.error),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.space16),
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        border: Border(top: BorderSide(color: AppTheme.borderSubtle)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.bgContent,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: TextField(
                    controller: _textCtrl,
                    focusNode: _focusNode,
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _handleSend(),
                    style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                    decoration: const InputDecoration(
                      hintText: '输入提问或指令，Enter 发送，Shift+Enter 换行...',
                      hintStyle: TextStyle(fontSize: 13, color: AppTheme.textTertiary),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.space12),
              _service.isProcessing
                  ? const SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ),
                    )
                  : IconButton.filled(
                      icon: const Icon(Icons.send_rounded, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: AppTheme.accentLight,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(44, 44),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
                      ),
                      onPressed: () => _handleSend(),
                    ),
            ],
          ),
        ],
      ),
    );
  }
}
