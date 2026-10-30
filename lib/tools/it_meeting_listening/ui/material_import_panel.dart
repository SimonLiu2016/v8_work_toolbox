/// 会议材料排练面板。
///
/// 四步流程，每步可单独重试（design D8）：
///
/// ```
/// ① 导入材料（MD/HTML）
///   └─ ② 生成讲稿（text 槽位）
///        └─ ③ 生成剧本（text 槽位）
///             └─ ④ 合成语音（tts 槽位，逐回合）
/// ```
///
/// **为什么不用一个按钮跑完全程**：讲稿生成失败（LLM 超时）不该让用户重跑
/// 整个流程；剧本改了语音必然要重烘，但讲稿不必跟着重来。分步还让用户能在
/// ② 和 ③ 之间**停下来改讲稿**——会前要调内容，这是高频操作。
///
/// 默认收起为一行入口：上班时这个面板不该占位置，点开才显示四步。
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// 排练四步的阶段。
enum RehearsalStep {
  material('导入材料', Icons.upload_file_outlined),
  draft('生成讲稿', Icons.article_outlined),
  script('生成剧本', Icons.groups_outlined),
  audio('合成语音', Icons.graphic_eq_rounded);

  final String label;
  final IconData icon;

  const RehearsalStep(this.label, this.icon);
}

/// 一步的状态。
enum RehearsalStepStatus { idle, running, done, failed }

class _StepState {
  RehearsalStepStatus status = RehearsalStepStatus.idle;
  String? message;

  _StepState();
}

/// 材料导入与生成面板。
class MaterialImportPanel extends StatefulWidget {
  /// 执行某一步。返回 null 表示成功，非 null 是失败原因。
  ///
  /// 由宿主（页面）提供——面板不直接持有服务，方便测试注入。
  final Future<String?> Function(RehearsalStep step) onRun;

  /// 某一步是否可执行（前置未满足时置灰）。
  final bool Function(RehearsalStep step) canRun;

  /// 收起/展开。
  final bool expanded;
  final VoidCallback onToggleExpanded;

  /// 当前已导入材料的标题（未导入时为 null）。
  final String? materialTitle;

  /// 讲稿节数 / 剧本轮数 / 音频时长，用于步骤旁的状态摘要。
  final String? draftSummary;
  final String? scriptSummary;
  final String? audioSummary;

  /// 目标会议时长（分钟）。用户选 30 或 60。
  final int targetMinutes;

  /// 目标时长变更。
  final ValueChanged<int> onTargetMinutesChanged;

  const MaterialImportPanel({
    super.key,
    required this.onRun,
    required this.canRun,
    required this.expanded,
    required this.onToggleExpanded,
    this.materialTitle,
    this.draftSummary,
    this.scriptSummary,
    this.audioSummary,
    this.targetMinutes = 30,
    required this.onTargetMinutesChanged,
  });

  @override
  State<MaterialImportPanel> createState() => _MaterialImportPanelState();
}

class _MaterialImportPanelState extends State<MaterialImportPanel> {
  final _steps = {
    for (final s in RehearsalStep.values) s: _StepState(),
  };

  RehearsalStep? _running;

  Future<void> _run(RehearsalStep step) async {
    if (_running != null) return;
    setState(() {
      _running = step;
      _steps[step]!.status = RehearsalStepStatus.running;
      _steps[step]!.message = null;
    });
    final error = await widget.onRun(step);
    if (!mounted) return;
    setState(() {
      _running = null;
      _steps[step]!.status =
          error == null ? RehearsalStepStatus.done : RehearsalStepStatus.failed;
      _steps[step]!.message = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textSecondary = context.isDarkMode
        ? context.textSecondary
        : AppTheme.lightTextSecondary;
    final textPrimary =
        context.isDarkMode ? context.textPrimary : AppTheme.lightTextPrimary;
    final accent = context.accentText;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: context.borderSubtle),
        borderRadius: AppTheme.borderRadiusSmall,
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: widget.onToggleExpanded,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.campaign_outlined, size: 16, color: accent),
                  const SizedBox(width: 8),
                  Text('会议材料排练',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: textPrimary)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.materialTitle ?? '导入周会 / 临时会议材料，预听自己要讲的话',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: textSecondary),
                    ),
                  ),
                  Icon(
                    widget.expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (widget.expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTargetSelector(textPrimary, textSecondary, accent),
                  const SizedBox(height: 10),
                  for (final step in RehearsalStep.values) ...[
                    _buildStepRow(step, textPrimary, textSecondary, accent),
                    const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 目标时长选择（30 / 60 分钟）。
  ///
  /// 放在步骤外面而不是某一步里：它决定的是**剧本生成**的轮次目标，与其它
  /// 步骤无关。改它不会让已生成的产物失效——只有重新生成剧本时才生效。
  Widget _buildTargetSelector(
    Color textPrimary,
    Color textSecondary,
    Color accent,
  ) {
    return Row(
      children: [
        Text('目标时长', style: TextStyle(fontSize: 11, color: textSecondary)),
        const SizedBox(width: 10),
        for (final minutes in const [30, 60])
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text('$minutes 分钟',
                  style: TextStyle(
                    fontSize: 11,
                    color: widget.targetMinutes == minutes
                        ? accent
                        : textPrimary,
                  )),
              selected: widget.targetMinutes == minutes,
              onSelected: (_) => widget.onTargetMinutesChanged(minutes),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
      ],
    );
  }

  Widget _buildStepRow(
    RehearsalStep step,
    Color textPrimary,
    Color textSecondary,
    Color accent,
  ) {
    final state = _steps[step]!;
    final runnable = widget.canRun(step) && _running == null;
    final summary = switch (step) {
      RehearsalStep.material => widget.materialTitle,
      RehearsalStep.draft => widget.draftSummary,
      RehearsalStep.script => widget.scriptSummary,
      RehearsalStep.audio => widget.audioSummary,
    };

    return Row(
      children: [
        _buildStepBadge(step, state.status, accent, textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(step.label,
                  style: TextStyle(fontSize: 12, color: textPrimary)),
              if (state.message != null)
                Text(
                  state.message!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: state.status == RehearsalStepStatus.failed
                        ? accent
                        : textSecondary,
                  ),
                )
              else if (summary != null)
                Text(summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: textSecondary)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (state.status == RehearsalStepStatus.running)
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          OutlinedButton(
            onPressed: runnable ? () => _run(step) : null,
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              foregroundColor: accent,
            ),
            child: Text(
              _labelFor(step, state.status),
              style: const TextStyle(fontSize: 11),
            ),
          ),
      ],
    );
  }

  String _labelFor(RehearsalStep step, RehearsalStepStatus status) {
    if (status == RehearsalStepStatus.failed) return '重试';
    if (status == RehearsalStepStatus.done) {
      return step == RehearsalStep.material ? '重新导入' : '重新生成';
    }
    return step == RehearsalStep.material ? '选择文件' : '生成';
  }

  Widget _buildStepBadge(
    RehearsalStep step,
    RehearsalStepStatus status,
    Color accent,
    Color textSecondary,
  ) {
    final (IconData icon, Color color) = switch (status) {
      RehearsalStepStatus.done => (Icons.check_circle, accent),
      RehearsalStepStatus.failed => (Icons.error_outline, accent),
      RehearsalStepStatus.running => (step.icon, accent),
      RehearsalStepStatus.idle => (step.icon, textSecondary),
    };
    return Icon(icon, size: 18, color: color);
  }
}
