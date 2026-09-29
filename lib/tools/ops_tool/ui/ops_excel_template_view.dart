import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../database/ops_database.dart';
import '../models/ops_models.dart';
import '../services/excel_service.dart';
import '../services/template_engine.dart';

class OpsExcelTemplateView extends StatefulWidget {
  final Function(Report generatedReport) onReportGenerated;

  const OpsExcelTemplateView({super.key, required this.onReportGenerated});

  @override
  State<OpsExcelTemplateView> createState() => _OpsExcelTemplateViewState();
}

class _OpsExcelTemplateViewState extends State<OpsExcelTemplateView> {
  ExcelData? _excelData;
  int _activeSheetIdx = 0;
  List<ReportTemplate> _templates = [];
  ReportTemplate? _selectedTemplate;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    final list = await OpsDatabase.instance.loadReportTemplates();
    if (mounted) {
      setState(() {
        _templates = list;
        if (list.isNotEmpty && _selectedTemplate == null) {
          _selectedTemplate = list.first;
        }
      });
    }
  }

  Future<void> _pickExcelFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
    );
    if (result == null || result.files.single.path == null) return;

    setState(() => _loading = true);
    try {
      final path = result.files.single.path!;
      final data = await ExcelService.instance.parseFile(path);
      if (mounted) {
        setState(() {
          _excelData = data;
          _activeSheetIdx = 0;
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功解析 ${data.sheets.length} 个工作表')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Excel 解析失败: $e'), backgroundColor: context.errorSolid),
        );
      }
    }
  }

  void _showAddTemplateDialog([ReportTemplate? existing]) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final contentCtrl = TextEditingController(
      text: existing?.content ??
          '''## 销售与运营总览
本期销售额：{总销售额} 元，完成订单：{订单量} 单。
最高单笔金额：{最高客单价} 元。

## 异常与待跟进
当前处理中工单：{异常工单数} 项。
''',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.bgCard,
        title: Text(existing == null ? '新建报告模板' : '编辑报告模板', style: AppTheme.fontTitle),
        content: SizedBox(
          width: 550,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '模板名称')),
              const SizedBox(height: 12),
              TextField(
                controller: contentCtrl,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: '模板 Markdown 内容 (支持 {占位符} 与内置变量 {当前日期})',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: context.accentSolid),
            onPressed: () async {
              final item = ReportTemplate(
                id: existing?.id,
                name: nameCtrl.text.trim(),
                content: contentCtrl.text,
                rules: existing?.rules ?? const [],
              );
              await OpsDatabase.instance.saveReportTemplate(item);
              if (ctx.mounted) Navigator.pop(ctx);
              _loadTemplates();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _generateReport() {
    if (_selectedTemplate == null) return;
    final content = TemplateEngine.resolveTemplate(
      template: _selectedTemplate!.content,
      rules: _selectedTemplate!.rules,
      sheets: _excelData?.sheets,
    );

    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final report = Report(
      title: '${_selectedTemplate!.name} - $dateStr',
      date: dateStr,
      sections: [
        ReportSection(
          sectionType: 'custom',
          title: _selectedTemplate!.name,
          content: content,
          order: 1,
        ),
      ],
    );

    widget.onReportGenerated(report);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppTheme.space24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧：Excel 导入与表格预览
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Excel 数据源', style: AppTheme.fontTitle),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.file_open_outlined, size: 18),
                      label: const Text('导入 Excel 文件'),
                      style: ElevatedButton.styleFrom(backgroundColor: context.accentSolid),
                      onPressed: _loading ? null : _pickExcelFile,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_excelData != null && _excelData!.sheets.isNotEmpty)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _excelData!.sheets.asMap().entries.map((e) {
                        final idx = e.key;
                        final sheet = e.value;
                        final isSelected = _activeSheetIdx == idx;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text('${sheet.name} (${sheet.rows.length}行)'),
                            selected: isSelected,
                            selectedColor: context.accentSolid,
                            onSelected: (_) => setState(() => _activeSheetIdx = idx),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                SizedBox(height: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: context.bgCard,
                      borderRadius: AppTheme.borderRadiusMedium,
                      border: Border.all(color: context.borderSubtle),
                    ),
                    child: _loading
                        ? Center(child: CircularProgressIndicator())
                        : _excelData == null || _excelData!.sheets.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.table_chart_outlined, size: 48, color: context.textSecondary),
                                    SizedBox(height: 12),
                                    Text('未加载 Excel 文件', style: AppTheme.fontBody),
                                    SizedBox(height: 4),
                                    Text('点击上方按钮导入 .xlsx 或 .xls 文件进行解析',
                                        style: AppTheme.fontCaption.copyWith(color: context.textSecondary)),
                                  ],
                                ),
                              )
                            : _buildSheetTable(_excelData!.sheets[_activeSheetIdx]),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.space24),

          // 右侧：报告模板选择与生成
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('报告模板', style: AppTheme.fontTitle),
                    IconButton(
                      icon: Icon(Icons.add, size: 20),
                      onPressed: () => _showAddTemplateDialog(),
                      tooltip: '新建模板',
                    ),
                  ],
                ),
                SizedBox(height: 12),
                DropdownButtonFormField<ReportTemplate>(
                  value: _selectedTemplate,
                  dropdownColor: context.bgCard,
                  decoration: InputDecoration(labelText: '选择已保存的模板'),
                  items: _templates
                      .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedTemplate = v),
                ),
                SizedBox(height: 16),
                if (_selectedTemplate != null) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('模板内容预览', style: AppTheme.fontCaption.copyWith(color: context.textSecondary)),
                      IconButton(
                        icon: Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => _showAddTemplateDialog(_selectedTemplate),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.all(AppTheme.space16),
                      decoration: BoxDecoration(
                        color: context.bgCard,
                        borderRadius: AppTheme.borderRadiusMedium,
                        border: Border.all(color: context.borderSubtle),
                      ),
                      child: SingleChildScrollView(
                        child: Text(_selectedTemplate!.content, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.auto_awesome_rounded, size: 20),
                      label: const Text('根据此模板与数据生成报告'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.accentSolid,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _generateReport,
                    ),
                  ),
                ] else ...[
                  const Expanded(
                    child: Center(child: Text('请先在上方选择或新建报告模板', style: AppTheme.fontBodySecondary)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSheetTable(SheetData sheet) {
    if (sheet.headers.isEmpty && sheet.rows.isEmpty) {
      return const Center(child: Text('当前工作表为空', style: AppTheme.fontBodySecondary));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columns: sheet.headers
              .map((h) => DataColumn(label: Text(h, style: const TextStyle(fontWeight: FontWeight.bold))))
              .toList(),
          rows: sheet.rows
              .take(100)
              .map((row) => DataRow(
                    cells: sheet.headers
                        .asMap()
                        .entries
                        .map((e) => DataCell(Text(e.key < row.length ? row[e.key] : '')))
                        .toList(),
                  ))
              .toList(),
        ),
      ),
    );
  }
}
