/// 报告面板：聚合会话数据、AI 叙述、Markdown 预览、PDF 导出、版本管理。
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path/path.dart' as p;

import '../../../theme/app_theme.dart';
import '../../notebook/export_service.dart';
import '../models/security_enums.dart';
import '../models/security_models.dart';
import '../services/report_services.dart';
import '../services/security_session_controller.dart';
import 'widgets.dart';

class ReportView extends StatefulWidget {
  final SecuritySessionController controller;

  const ReportView({super.key, required this.controller});

  @override
  State<ReportView> createState() => _ReportViewState();
}

class _ReportViewState extends State<ReportView> {
  String _viewMode = 'technical'; // 'technical' | 'executive'
  String _executiveSummary = '';
  String _remediation = '';
  bool _generating = false;
  String _markdown = '';
  List<ReportVersionRecord> _versions = const [];

  String get _currentDisplayContent {
    if (_viewMode == 'executive') {
      final bundle = widget.controller.buildReportBundle();
      if (bundle != null && _executiveSummary.isNotEmpty) {
        return buildExecutiveMarkdownReport(
          bundle: bundle,
          executiveSummary: _executiveSummary,
          remediation: _remediation,
        );
      }
      return _executiveSummary.isNotEmpty ? _executiveSummary : _markdown;
    }
    return _markdown;
  }

  @override
  void initState() {
    super.initState();
    _loadVersions();
  }

  Future<void> _loadVersions() async {
    final versions = await widget.controller.reportVersions();
    if (!mounted) return;
    setState(() => _versions = versions);
  }

  Future<void> _generate() async {
    final controller = widget.controller;
    final bundle = controller.buildReportBundle();
    if (bundle == null) {
      _toast('请先创建或选择一个会话');
      return;
    }
    setState(() => _generating = true);
    controller.log('开始生成报告叙述…');
    try {
      final summary = await controller.askAi(
        buildReportSectionPrompt(bundle: bundle, section: 'executive'),
      );
      final tech = await controller.askAi(
        buildReportSectionPrompt(bundle: bundle, section: 'narrative'),
      );
      final fix = await controller.askAi(
        buildReportSectionPrompt(bundle: bundle, section: 'remediation'),
      );
      if (!mounted) return;
      setState(() {
        _executiveSummary = summary;
        _remediation = fix;
        _markdown = buildMarkdownReport(
          bundle: bundle,
          executiveSummary: summary,
          narrative: tech,
          remediation: fix,
        );
      });
      final version = nextVersion(_versions);
      await controller.saveReportVersion(
        version: version,
        content: encodeReportContent(
          executiveSummary: summary,
          narrative: tech,
          remediation: fix,
        ),
      );
      await _loadVersions();
      controller.log('报告已生成（v$version）');
    } catch (e) {
      if (!mounted) return;
      _toast('生成失败: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _exportMarkdown() async {
    final contentToExport = _currentDisplayContent;
    if (contentToExport.isEmpty) {
      _toast('请先生成报告');
      return;
    }
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择导出目录',
    );
    if (dir == null) return;
    final session = widget.controller.current;
    final suffix = _viewMode == 'executive' ? 'executive' : 'technical';
    final name = '${session?.name ?? 'pentest'}_${suffix}_report.md';
    final file = File(p.join(dir, name));
    await file.writeAsString(contentToExport);
    _toast('已导出: ${file.path}');
  }

  Future<void> _exportPdf() async {
    final bundle = widget.controller.buildReportBundle();
    if (bundle == null || _markdown.isEmpty) {
      _toast('请先生成报告');
      return;
    }
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择导出目录',
    );
    if (dir == null) return;
    try {
      final font = await ExportService.instance.loadCjkFont();
      final doc = pw.Document(
        theme: pw.ThemeData.withFont(
          base: font,
          bold: font,
          italic: font,
          boldItalic: font,
        ),
      );
      final spec = toPdfSpec(bundle, _executiveSummary);

      // 封面
      doc.addPage(
        pw.MultiPage(
          build: (context) => [
            pw.Header(level: 0, text: spec.title),
            pw.Paragraph(text: '会话类型: ${SessionType.labelOf(spec.sessionType)}'),
            pw.Paragraph(text: '目标范围: ${spec.scope.join('、')}'),
            pw.Paragraph(text: '生成日期: ${spec.generatedAt}'),
            pw.Divider(),
            pw.Header(level: 1, text: '执行摘要'),
            pw.Paragraph(text: spec.executiveSummary),
            pw.Header(level: 1, text: '漏洞发现'),
            pw.TableHelper.fromTextArray(
              context: context,
              headers: ['等级', 'CVSS', '名称', 'CVE', '状态'],
              data: [
                for (final row in spec.findingRows)
                  [row.severity, row.cvss, row.title, row.cve, row.status],
              ],
            ),
          ],
        ),
      );

      final session = widget.controller.current;
      final out = File(p.join(dir, '${session?.name ?? 'pentest'}_report.pdf'));
      await out.writeAsBytes(await doc.save());
      _toast('已导出: ${out.path}');
    } catch (e) {
      _toast('PDF 导出失败: $e');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayContent = _currentDisplayContent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: '渗透报告',
          subtitle: '聚合会话数据 · AI 叙述 · 双层格式 · PDF/Markdown 导出',
          trailing: [
            SmallActionButton(
              label: _generating ? '生成中…' : '生成报告',
              icon: Icons.auto_awesome_rounded,
              primary: true,
              onPressed: _generating ? null : _generate,
            ),
            const SizedBox(width: AppTheme.space8),
            SmallActionButton(
              label: '导出 MD',
              icon: Icons.description_outlined,
              onPressed: _exportMarkdown,
            ),
            const SizedBox(width: AppTheme.space8),
            SmallActionButton(
              label: '导出 PDF',
              icon: Icons.picture_as_pdf_outlined,
              onPressed: _exportPdf,
            ),
          ],
        ),
        Expanded(
          child: _markdown.isEmpty
              ? EmptyState(
                  message: widget.controller.current == null
                      ? '请先创建会话'
                      : '点击「生成报告」自动汇总资产、发现物与时间线',
                  icon: Icons.article_outlined,
                )
              : ListView(
                  children: [
                    _buildVersionStrip(context),
                    const SizedBox(height: AppTheme.space12),
                    _buildModeSelector(context),
                    const SizedBox(height: AppTheme.space12),
                    Container(
                      padding: const EdgeInsets.all(AppTheme.space12),
                      decoration: BoxDecoration(
                        color: context.bgCard,
                        borderRadius: AppTheme.borderRadiusSmall,
                        border: Border.all(color: context.borderSubtle),
                      ),
                      child: SelectableText(
                        displayContent,
                        style: AppTheme.fontCaption.copyWith(
                          fontFamily: 'Menlo',
                          color: context.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildModeSelector(BuildContext context) {
    return Row(
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'technical',
              label: Text('技术报告'),
              icon: Icon(Icons.code_outlined, size: 16),
            ),
            ButtonSegment(
              value: 'executive',
              label: Text('执行摘要'),
              icon: Icon(Icons.summarize_outlined, size: 16),
            ),
          ],
          selected: {_viewMode},
          onSelectionChanged: (set) => setState(() => _viewMode = set.first),
        ),
      ],
    );
  }

  Widget _buildVersionStrip(BuildContext context) {
    if (_versions.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(AppTheme.space8),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Row(
        children: [
          Text('版本历史 (${_versions.length})', style: context.fontCaption),
          const Spacer(),
          for (final version in _versions.reversed.take(5))
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: ActionChip(
                label: Text('v${version.version}'),
                onPressed: () {
                  final decoded = decodeReportContent(version.content);
                  final summary = decoded['executive_summary'] as String? ?? '';
                  final tech = decoded['narrative'] as String? ?? '';
                  final fix = decoded['remediation'] as String? ?? '';
                  final attack = decoded['attack_path'] as String?;
                  final bundle = widget.controller.buildReportBundle();
                  setState(() {
                    _executiveSummary = summary;
                    _remediation = fix;
                    if (bundle != null) {
                      _markdown = buildMarkdownReport(
                        bundle: bundle,
                        executiveSummary: summary,
                        narrative: tech,
                        remediation: fix,
                        attackPath: attack,
                      );
                    } else {
                      _markdown = [
                        '# 渗透测试报告 (v${version.version})',
                        '## 一、执行摘要\n$summary',
                        if (tech.isNotEmpty) '## 二、技术叙述\n$tech',
                        if (fix.isNotEmpty) '## 三、修复建议\n$fix',
                      ].join('\n\n');
                    }
                  });
                  _toast('已加载版本 v${version.version}');
                },
              ),
            ),
        ],
      ),
    );
  }
}
