import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../theme/app_theme.dart';
import '../database/ops_database.dart';
import '../models/ops_models.dart';
import '../services/ops_ai_helper.dart';
import '../services/report_generator.dart';

class OpsReportEditorView extends StatefulWidget {
  final Report? initialReport;
  final VoidCallback? onInitialReportConsumed;
  final Function(String html, String subject) onSendEmail;

  const OpsReportEditorView({
    super.key,
    this.initialReport,
    this.onInitialReportConsumed,
    required this.onSendEmail,
  });

  @override
  State<OpsReportEditorView> createState() => _OpsReportEditorViewState();
}

class _OpsReportEditorViewState extends State<OpsReportEditorView> {
  List<Report> _reports = [];
  Report? _currentReport;
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  bool _aiLoading = false;
  bool _loading = true;

  Report? _pendingInitialReport;

  @override
  void initState() {
    super.initState();
    _pendingInitialReport = widget.initialReport;
    _initData();
  }

  Future<void> _initData() async {
    final list = await OpsDatabase.instance.listReports();
    if (mounted) {
      setState(() {
        _reports = list;
        if (_pendingInitialReport != null) {
          _currentReport = _pendingInitialReport;
          _pendingInitialReport = null; // 消费后置空，避免后续刷新再次强刷
          widget.onInitialReportConsumed?.call();
        } else if (_currentReport != null) {
          final existing = list.where((r) => r.id == _currentReport!.id).firstOrNull;
          if (existing != null) {
            _currentReport = existing;
          }
        } else if (list.isNotEmpty) {
          _currentReport = list.first;
        }
        _syncControllers();
        _loading = false;
      });
    }
  }

  void _syncControllers() {
    if (_currentReport != null) {
      _titleCtrl.text = _currentReport!.title;
      if (_currentReport!.sections.isNotEmpty) {
        _contentCtrl.text = _currentReport!.sections
            .map((s) => '### ${s.title}\n\n${s.content}')
            .join('\n\n');
      }
    } else {
      _titleCtrl.clear();
      _contentCtrl.clear();
    }
  }

  Future<void> _deleteReport(Report report) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('删除报告确认', style: AppTheme.fontTitle),
        content: Text(
          '确定要删除报告「${report.title}」吗？此操作无法撤销。',
          style: AppTheme.fontBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await OpsDatabase.instance.deleteReport(report.id);
    final updatedList = await OpsDatabase.instance.listReports();

    if (!mounted) return;

    setState(() {
      _reports = updatedList;
      if (_currentReport?.id == report.id) {
        if (updatedList.isNotEmpty) {
          _currentReport = updatedList.first;
        } else {
          _currentReport = null;
        }
        _syncControllers();
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('报告已删除')),
    );
  }

  Future<void> _saveCurrentReport() async {
    if (_currentReport == null) return;
    final text = _contentCtrl.text;
    final title = _titleCtrl.text.trim().isEmpty ? _currentReport!.title : _titleCtrl.text.trim();
    final updatedReport = Report(
      id: _currentReport!.id,
      title: title,
      date: _currentReport!.date,
      sections: [
        ReportSection(
          sectionType: 'custom',
          title: title,
          content: text,
          order: 1,
        ),
      ],
      htmlContent: ReportGenerator.generateHtml(Report(
        id: _currentReport!.id,
        title: title,
        date: _currentReport!.date,
        sections: [
          ReportSection(
            sectionType: 'custom',
            title: title,
            content: text,
            order: 1,
          ),
        ],
      )),
    );

    await OpsDatabase.instance.saveReport(updatedReport);
    final list = await OpsDatabase.instance.listReports();
    if (mounted) {
      setState(() {
        _currentReport = updatedReport;
        _reports = list;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('报告已成功保存')),
      );
    }
  }

  Future<void> _runAiAnomalyAnalysis() async {
    if (_currentReport == null) return;
    setState(() => _aiLoading = true);

    try {
      final analysis = await OpsAiHelper.analyzeAnomaly(
        sectionTitle: _currentReport!.title,
        sectionContent: _contentCtrl.text,
      );

      setState(() {
        _contentCtrl.text = '${_contentCtrl.text}\n\n### 🤖 AI 智能研判与应对建议\n\n$analysis';
        _aiLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _aiLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI 研判失败: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  Future<void> _runAiSummary() async {
    if (_currentReport == null) return;
    setState(() => _aiLoading = true);

    try {
      final summary = await OpsAiHelper.generateSummary(
        reportTitle: _currentReport!.title,
        reportMarkdown: _contentCtrl.text,
      );

      setState(() {
        _contentCtrl.text = '### 🤖 AI 综合运营摘要\n\n$summary\n\n${_contentCtrl.text}';
        _aiLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _aiLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI 提炼摘要失败: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  void _sendCurrentToEmail() {
    if (_currentReport == null) return;
    final html = ReportGenerator.generateHtml(Report(
      title: _titleCtrl.text.trim(),
      date: _currentReport!.date,
      sections: [
        ReportSection(
          sectionType: 'custom',
          title: _titleCtrl.text.trim(),
          content: _contentCtrl.text,
          order: 1,
        ),
      ],
    ));

    widget.onSendEmail(html, _titleCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Padding(
      padding: const EdgeInsets.all(AppTheme.space24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧：历史报告列表
          SizedBox(
            width: 260,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('报告中心', style: AppTheme.fontTitle),
                    IconButton(
                      icon: const Icon(Icons.add, size: 20),
                      onPressed: () {
                        final now = DateTime.now();
                        final d = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
                        final newRep = Report(
                          title: '新运维日报 - $d',
                          date: d,
                          sections: [
                            ReportSection(sectionType: 'custom', title: '日常运维概览', content: '（请输入报告内容...）', order: 1),
                          ],
                        );
                        setState(() {
                          _currentReport = newRep;
                          _syncControllers();
                        });
                      },
                      tooltip: '新建报告',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      borderRadius: AppTheme.borderRadiusMedium,
                      border: Border.all(color: AppTheme.borderSubtle),
                    ),
                    child: _reports.isEmpty
                        ? const Center(child: Text('暂无历史报告', style: AppTheme.fontBodySecondary))
                        : ListView.separated(
                            itemCount: _reports.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.borderSubtle),
                            itemBuilder: (context, idx) {
                              final r = _reports[idx];
                              final isSelected = _currentReport?.id == r.id;
                              return ListTile(
                                selected: isSelected,
                                selectedTileColor: AppTheme.bgSelected,
                                leading: const Icon(Icons.article_outlined, size: 20, color: AppTheme.accent),
                                title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.fontBody),
                                subtitle: Text(r.date, style: AppTheme.fontCaption),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.error),
                                  tooltip: '删除报告',
                                  onPressed: () => _deleteReport(r),
                                ),
                                onTap: () {
                                  setState(() {
                                    _currentReport = r;
                                    _syncControllers();
                                  });
                                },
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.space24),

          // 右侧：编辑与预览双栏
          Expanded(
            child: _currentReport == null
                ? const Center(child: Text('请选择或新建一份报告', style: AppTheme.fontBodySecondary))
                : Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _titleCtrl,
                              style: AppTheme.fontHeadline,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                hintText: '报告标题...',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            icon: _aiLoading
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.psychology_alt_rounded, size: 18),
                            label: const Text('AI 异常研判'),
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.info),
                            onPressed: _aiLoading ? null : _runAiAnomalyAnalysis,
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.summarize_rounded, size: 18),
                            label: const Text('AI 提炼摘要'),
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
                            onPressed: _aiLoading ? null : _runAiSummary,
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.save_rounded, size: 18),
                            label: const Text('保存报告'),
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
                            onPressed: _saveCurrentReport,
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.send_rounded, size: 18),
                            label: const Text('发邮件'),
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warning),
                            onPressed: _sendCurrentToEmail,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Row(
                          children: [
                            // 左侧：Markdown 编辑器
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(AppTheme.space16),
                                decoration: BoxDecoration(
                                  color: AppTheme.bgCard,
                                  borderRadius: AppTheme.borderRadiusMedium,
                                  border: Border.all(color: AppTheme.borderSubtle),
                                ),
                                child: TextField(
                                  controller: _contentCtrl,
                                  maxLines: null,
                                  expands: true,
                                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    hintText: '使用 Markdown 编写报告内容...',
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppTheme.space16),

                            // 右侧：实时渲染预览
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(AppTheme.space16),
                                decoration: BoxDecoration(
                                  color: AppTheme.bgCard,
                                  borderRadius: AppTheme.borderRadiusMedium,
                                  border: Border.all(color: AppTheme.borderSubtle),
                                ),
                                child: Markdown(
                                  data: _contentCtrl.text,
                                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                                    p: AppTheme.fontBody,
                                    h1: AppTheme.fontHeadline,
                                    h2: AppTheme.fontTitle,
                                    h3: AppTheme.fontTitle.copyWith(color: AppTheme.accent),
                                  ),
                                ),
                              ),
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
}
