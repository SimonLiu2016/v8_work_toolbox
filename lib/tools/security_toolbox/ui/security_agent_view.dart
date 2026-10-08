/// Security Agent 面板：自然语言输入 + 审批 + 步骤进度 + 思考日志 + 预设工作流。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../components/markdown_view.dart';
import '../../../theme/app_theme.dart';
import '../models/security_enums.dart';
import '../models/security_models.dart';
import '../services/security_agent_executor.dart';
import '../services/security_agent_service.dart';
import '../services/security_pipeline_service.dart';
import '../services/security_session_controller.dart';
import 'widgets.dart';

class SecurityAgentView extends StatefulWidget {
  final SecuritySessionController controller;

  const SecurityAgentView({super.key, required this.controller});

  @override
  State<SecurityAgentView> createState() => _SecurityAgentViewState();
}

class _SecurityAgentViewState extends State<SecurityAgentView> {
  final _taskController = TextEditingController();
  String? _currentSessionId;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _consumeIntentIfNeeded();
    _syncWithSession(force: true);
  }

  void _onControllerChanged() {
    _consumeIntentIfNeeded();
    _syncWithSession();
    if (mounted) setState(() {});
  }

  void _consumeIntentIfNeeded() {
    final intent = widget.controller.pendingIntent;
    if (intent != null && intent.targetTab == 'agent') {
      widget.controller.consumeIntent();
      if (intent.initialPrompt != null && intent.initialPrompt!.isNotEmpty) {
        _taskController.text = intent.initialPrompt!;
      } else if (intent.targetAsset != null) {
        final a = intent.targetAsset!;
        final ports = a.openPorts.map((p) => '${p['port']}/${p['service'] ?? ''}').join(', ');
        _taskController.text = '对目标主机 ${a.address}${ports.isNotEmpty ? " (开放服务: $ports)" : ""} 展开深入安全性核查与合规评估';
      }
      if (mounted) setState(() {});
    }
  }

  void _syncWithSession({bool force = false}) {
    final current = widget.controller.current;
    final currentId = current?.id;
    if (!force && currentId == _currentSessionId) return;
    _currentSessionId = currentId;
    SecurityAgentService.instance.switchSession(currentId);
    final taskText = SecurityAgentService.instance.resolveDefaultTask(current);
    if (_taskController.text != taskText) {
      _taskController.text = taskText;
    }
  }

  @override
  void didUpdateWidget(SecurityAgentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    _syncWithSession();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _taskController.dispose();
    super.dispose();
  }

  Future<void> _start(String task) async {
    if (task.trim().isEmpty) return;
    final agent = SecurityAgentService.instance;
    final currentSession = widget.controller.current;
    agent.reset(currentSession?.id);
    final context = widget.controller.sessionContextJson();
    try {
      await agent.run(
        task: task,
        sessionId: currentSession?.id,
        sessionContext: context,
        onApproval: (tool, args) => _confirm(tool, args),
        // 真实执行层在 service 侧（SecurityAgentExecutor），UI 只负责接线与
        // 审批弹窗。每个工具的结果都会写回会话资产/发现物/时间线。
        executeTool: (name, args) =>
            runAgentTool(widget.controller, name, args),
      );
    } catch (e) {
      widget.controller.log('Agent 执行失败: $e');
    }
  }

  Future<bool> _confirm(String tool, Map<String, dynamic> args) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.bgCard,
        title: Text('高影响操作审批', style: context.fontTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Agent 请求执行：$tool', style: context.fontBody),
            const SizedBox(height: AppTheme.space8),
            Text('参数：$args', style: context.fontCaption),
            const SizedBox(height: AppTheme.space8),
            Text(
              '该操作可能对目标造成实际影响，请确认已获得授权。',
              style: context.fontCaption.copyWith(color: context.warningSolid),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('跳过'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认执行'),
          ),
        ],
      ),
    );
    SecurityAgentService.instance.resolveApproval(ok ?? false);
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Security Agent',
          subtitle: '自然语言驱动 · ReAct 循环 · 高影响操作人工审批',
        ),
        Expanded(
          child: ListView(
            children: [
              _buildTaskCard(context),
              const SizedBox(height: AppTheme.space12),
              _buildPresets(context),
              const SizedBox(height: AppTheme.space12),
              StreamBuilder<AgentRunState>(
                stream: SecurityAgentService.instance.stateStream,
                initialData: SecurityAgentService.instance.state,
                builder: (context, snapshot) => _buildProgress(context),
              ),
              const SizedBox(height: AppTheme.space12),
              StreamBuilder<AgentStep>(
                stream: SecurityAgentService.instance.stepStream,
                builder: (context, snapshot) => _buildSteps(context),
              ),
              const SizedBox(height: AppTheme.space12),
              StreamBuilder<AgentRunState>(
                stream: SecurityAgentService.instance.stateStream,
                initialData: SecurityAgentService.instance.state,
                builder: (context, snapshot) => _buildFinalReport(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTaskCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.space12),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _taskController,
            onChanged: (text) {
              final currentId = widget.controller.current?.id;
              SecurityAgentService.instance.setTaskDraft(currentId, text);
            },
            decoration: const InputDecoration(
              labelText: '描述渗透目标',
              hintText: '扫描 192.168.1.0/24，找出所有可利用漏洞',
            ),
            style: context.fontBody,
            maxLines: 2,
          ),
          const SizedBox(height: AppTheme.space8),
          Row(
            children: [
              if (SecurityPipelineService.instance.isRunning)
                SmallActionButton(
                  label: '停止流水线',
                  icon: Icons.stop_rounded,
                  onPressed: () {
                    SecurityPipelineService.instance.cancel();
                    setState(() {});
                  },
                )
              else
                SmallActionButton(
                  label: '启动 Agent',
                  icon: Icons.play_arrow_rounded,
                  primary: true,
                  onPressed: () => _start(_taskController.text),
                ),
              const SizedBox(width: AppTheme.space8),
              SmallActionButton(
                label: '重置',
                icon: Icons.restore_rounded,
                onPressed: () {
                  final currentId = widget.controller.current?.id;
                  SecurityAgentService.instance.reset(currentId, true);
                  _syncWithSession(force: true);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresets(BuildContext context) {
    final session = widget.controller.current;
    if (session == null) return const SizedBox.shrink();
    final target = session.scope.isNotEmpty ? session.scope.first : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('一键预设工作流', style: context.fontTitle),
        const SizedBox(height: AppTheme.space8),
        Wrap(
          spacing: AppTheme.space8,
          runSpacing: AppTheme.space8,
          children: [
            if (session.isLan)
              SmallActionButton(
                label: 'LAN 一键渗透',
                icon: Icons.router_outlined,
                primary: true,
                onPressed: target.isEmpty || SecurityPipelineService.instance.isRunning
                    ? null
                    : () {
                        final activeSession = widget.controller.current;
                        final activeTarget =
                            activeSession?.scope.isNotEmpty == true
                                ? activeSession!.scope.first
                                : target;
                        final taskText = lanOneClickTask(activeTarget);
                        _taskController.text = taskText;
                        SecurityAgentService.instance
                            .setTaskDraft(activeSession?.id, taskText);
                        SecurityPipelineService.instance.runLanPipeline(
                          controller: widget.controller,
                          targetCidr: activeTarget,
                        );
                      },
              ),
            if (!session.isLan)
              SmallActionButton(
                label: 'Web 一键侦察',
                icon: Icons.language_outlined,
                primary: true,
                onPressed: target.isEmpty || SecurityPipelineService.instance.isRunning
                    ? null
                    : () {
                        final activeSession = widget.controller.current;
                        final activeTarget =
                            activeSession?.scope.isNotEmpty == true
                                ? activeSession!.scope.first
                                : target;
                        final taskText = webOneClickTask(activeTarget);
                        _taskController.text = taskText;
                        SecurityAgentService.instance
                            .setTaskDraft(activeSession?.id, taskText);
                        SecurityPipelineService.instance.runWebPipeline(
                          controller: widget.controller,
                          domain: activeTarget,
                        );
                      },
              ),
            // 一键全量评估：基础侦察 + AI 研判循环
            SmallActionButton(
              label: SecurityPipelineService.instance.isRunning ? '■ 停止' : '⚡ 全量评估',
              icon: SecurityPipelineService.instance.isRunning
                  ? Icons.stop_rounded
                  : Icons.auto_awesome_rounded,
              primary: !SecurityPipelineService.instance.isRunning,
              onPressed: target.isEmpty
                  ? null
                  : () {
                      if (SecurityPipelineService.instance.isRunning) {
                        SecurityPipelineService.instance.cancel();
                        setState(() {});
                        return;
                      }
                      final activeSession = widget.controller.current;
                      if (activeSession == null) return;
                      final activeTarget =
                          activeSession.scope.isNotEmpty
                              ? activeSession.scope.first
                              : target;
                      AdaptiveAgentPipeline.run(
                        controller: widget.controller,
                        target: activeTarget,
                        isLan: activeSession.isLan,
                      );
                      setState(() {});
                    },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProgress(BuildContext context) {
    final service = SecurityAgentService.instance;
    final state = service.state;
    final currentTool = service.currentTool;
    final stepsCount = service.steps.length;

    final String statusText;
    if (state == AgentRunState.running) {
      if (currentTool != null) {
        statusText = '步骤 ${stepsCount + 1} · 正在执行 $currentTool…';
      } else {
        statusText = '步骤 ${stepsCount + 1} · 模型思考与决策中…';
      }
    } else if (state == AgentRunState.paused) {
      statusText = '步骤 ${stepsCount + 1} · 等待人工审批操作';
    } else if (state == AgentRunState.done) {
      statusText = stepsCount > 0 ? '共完成 $stepsCount 个步骤 · 已完成' : '已完成';
    } else if (state == AgentRunState.failed) {
      statusText = '执行失败: ${service.lastError ?? "未知错误"}';
    } else {
      statusText = '空闲';
    }

    final color = switch (state) {
      AgentRunState.running => context.accentText,
      AgentRunState.paused => context.warningSolid,
      AgentRunState.done => context.successSolid,
      AgentRunState.failed => context.errorSolid,
      _ => context.textTertiary,
    };

    return Row(
      children: [
        if (state == AgentRunState.running)
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        if (state == AgentRunState.running)
          const SizedBox(width: AppTheme.space8),
        Text(statusText, style: context.fontCaption.copyWith(color: color)),
      ],
    );
  }

  Widget _buildSteps(BuildContext context) {
    final steps = SecurityAgentService.instance.steps;
    if (steps.isEmpty) {
      return const EmptyState(
        message: '启动 Agent 后，这里会实时展示它的决策与工具调用',
        icon: Icons.psychology_outlined,
      );
    }
    return Container(
      padding: const EdgeInsets.all(AppTheme.space12),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Agent 思考日志', style: context.fontTitle),
          const SizedBox(height: AppTheme.space8),
          for (final step in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                formatStep(step),
                style: AppTheme.fontCaption.copyWith(
                  fontFamily: 'Menlo',
                  color: step.approved
                      ? (step.isError ? context.errorSolid : context.textSecondary)
                      : context.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFinalReport(BuildContext context) {
    final report = SecurityAgentService.instance.finalReport;
    if (report == null || report.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(AppTheme.space12),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 16, color: context.accentText),
              const SizedBox(width: 6),
              Text('Agent 综合分析与防御加固建议', style: context.fontTitle),
              const Spacer(),
              SmallActionButton(
                label: '重新分析',
                icon: Icons.refresh_rounded,
                onPressed: () async {
                  final session = widget.controller.current;
                  if (session == null) return;
                  SecurityAgentService.instance.addThinking('重新请求 AI 生成防御加固建议…');
                  final rep = await SecurityAgentService.instance.generateDefensiveReport(
                    session: session,
                    assets: widget.controller.assetList,
                    findings: widget.controller.findingList,
                  );
                  SecurityAgentService.instance.updateFinalReport(rep);
                  if (mounted) setState(() {});
                },
              ),
              const SizedBox(width: AppTheme.space8),
              SmallActionButton(
                label: '复制建议',
                icon: Icons.copy_rounded,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: report));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已复制防御加固建议到剪贴板'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space8),
          AppMarkdownView(
            data: report,
            selectable: true,
          ),
          _buildActionableNextSteps(context),
        ],
      ),
    );
  }

  Widget _buildActionableNextSteps(BuildContext context) {
    final actions = _resolveNextActions();
    if (actions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppTheme.space12),
        const Divider(height: 1),
        const SizedBox(height: AppTheme.space12),
        Row(
          children: [
            Icon(Icons.play_circle_outline_rounded, size: 16, color: context.accentText),
            const SizedBox(width: 6),
            Text('推荐下一步行动 (Next Actions)', style: context.fontTitle),
          ],
        ),
        const SizedBox(height: AppTheme.space8),
        for (final action in actions)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: context.bgWindow,
              borderRadius: AppTheme.borderRadiusSmall,
              border: Border.all(color: context.borderSubtle),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        action.title,
                        style: context.fontBody.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        action.description,
                        style: context.fontCaption,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  ),
                  onPressed: () {
                    widget.controller.navigateToTab(
                      action.intent.targetTab,
                      intent: action.intent,
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(action.actionLabel, style: const TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_rounded, size: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  List<AgentNextAction> _resolveNextActions() {
    final actions = <AgentNextAction>[];
    final findings = widget.controller.findingList;
    final assets = widget.controller.assetList;

    // 1. 若有高危漏洞，优先推荐验证利用
    for (final f in findings) {
      if (actions.length >= 2) break;
      if (f.severityLevel == Severity.critical || f.severityLevel == Severity.high) {
        PentestAsset? matchedAsset;
        if (f.assetId != null) {
          for (final a in assets) {
            if (a.id == f.assetId) {
              matchedAsset = a;
              break;
            }
          }
        }
        matchedAsset ??= assets.isNotEmpty ? assets.first : null;

        actions.add(
          AgentNextAction(
            title: '验证脆弱点: ${f.title}',
            description: '针对 ${f.cveId ?? f.title} 转入 Exploit 模块进行 PoC 检索与验证',
            actionLabel: '利用验证',
            intent: NavigationIntent(
              targetTab: 'exploit',
              targetAsset: matchedAsset,
              targetFinding: f,
              initialQuery: f.cveId ?? f.title,
            ),
          ),
        );
      }
    }

    // 2. 若有资产，推荐漏洞扫描
    if (assets.isNotEmpty && actions.length < 3) {
      final targetAsset = assets.first;
      actions.add(
        AgentNextAction(
          title: '全面漏洞扫描: ${targetAsset.address}',
          description: '针对已识别资产使用 Nuclei 模板库执行脆弱性扫描',
          actionLabel: '漏洞扫描',
          intent: NavigationIntent(
            targetTab: 'vuln',
            targetAsset: targetAsset,
          ),
        ),
      );
    }

    // 3. 推荐定制脚本
    if (actions.length < 3) {
      actions.add(
        AgentNextAction(
          title: '生成安全加固或复测脚本',
          description: '结合当前评估结果自动生成针对性加固与验证脚本',
          actionLabel: '定制脚本',
          intent: NavigationIntent(
            targetTab: 'script',
            initialPrompt: '依据当前安全评估报告，编写针对目标资产的安全配置加固与合规复测脚本',
          ),
        ),
      );
    }

    return actions;
  }
}
