/// 右侧常驻 AI 面板：安全专家系统 prompt、手动询问、自动分析推送。
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../services/security_session_controller.dart';
import 'widgets.dart';

class SecurityAiPanel extends StatefulWidget {
  final SecuritySessionController controller;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;

  const SecurityAiPanel({
    super.key,
    required this.controller,
    required this.collapsed,
    required this.onToggleCollapsed,
  });

  @override
  State<SecurityAiPanel> createState() => _SecurityAiPanelState();
}

class _SecurityAiPanelState extends State<SecurityAiPanel> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    final controller = widget.controller;
    controller.pushAiMessage('user', text);
    _inputController.clear();
    _scrollToBottom();
    try {
      final reply = await controller.askAi(text);
      controller.pushAiMessage('assistant', reply);
    } catch (e) {
      controller.pushAiMessage('assistant', '调用失败: $e');
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.collapsed ? 44 : 320,
      color: context.bgSidebar,
      child: Column(
        children: [
          // 头部：折叠开关 + 标题
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.space8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: context.borderSubtle),
                left: BorderSide(color: context.borderSubtle),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    widget.collapsed
                        ? Icons.chevron_left
                        : Icons.chevron_right,
                    size: 18,
                  ),
                  tooltip: widget.collapsed ? '展开 AI 面板' : '收起 AI 面板',
                  onPressed: widget.onToggleCollapsed,
                ),
                if (!widget.collapsed) ...[
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: context.accentText,
                  ),
                  const SizedBox(width: AppTheme.space6),
                  Text('安全助手', style: context.fontBody),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 16),
                    tooltip: '清空对话',
                    onPressed: widget.controller.clearAiMessages,
                  ),
                ],
              ],
            ),
          ),
          if (widget.collapsed)
            Expanded(
              child: RotatedBox(
                quarterTurns: 1,
                child: Center(
                  child: Text(
                    'AI 安全分析',
                    style: context.fontCaption,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) {
                  final messages = widget.controller.aiMessages;
                  if (messages.isEmpty) {
                    return EmptyState(
                      message: '扫描完成后我会自动分析；\n也可直接向我提问。',
                      icon: Icons.forum_outlined,
                    );
                  }
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(AppTheme.space12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      return _AiBubble(message: message);
                    },
                  );
                },
              ),
            ),
          if (!widget.collapsed)
            Container(
              padding: const EdgeInsets.all(AppTheme.space8),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: context.borderSubtle),
                  left: BorderSide(color: context.borderSubtle),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: '问我任何安全相关问题…',
                        isDense: true,
                        border: InputBorder.none,
                      ),
                      style: context.fontBody,
                      onSubmitted: (_) => _ask(),
                    ),
                  ),
                  const SizedBox(width: AppTheme.space6),
                  ListenableBuilder(
                    listenable: widget.controller,
                    builder: (context, _) => IconButton(
                      icon: widget.controller.aiBusy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              Icons.send_rounded,
                              size: 16,
                              color: context.accentText,
                            ),
                      onPressed: widget.controller.aiBusy ? null : _ask,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AiBubble extends StatelessWidget {
  final AiPanelMessage message;

  const _AiBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppTheme.space8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: isUser ? context.accentSubtle : context.bgCard,
          borderRadius: AppTheme.borderRadiusSmall,
          border: Border.all(
            color: isUser ? context.accentText.withAlpha(60) : context.borderSubtle,
          ),
        ),
        child: SelectableText(
          message.text,
          style: context.fontBodySecondary.copyWith(
            color: isUser ? context.textPrimary : context.textSecondary,
          ),
        ),
      ),
    );
  }
}
