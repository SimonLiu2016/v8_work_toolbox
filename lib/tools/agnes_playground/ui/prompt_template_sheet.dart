import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme.dart';
import '../models/playground_models.dart';
import '../models/prompt_template_models.dart';
import '../services/prompt_template_store.dart';

/// 提示词效果库对话框/选择抽屉。
class PromptTemplateSheet extends StatefulWidget {
  const PromptTemplateSheet({
    super.key,
    this.initialChannel,
    this.currentModel,
    required this.onSelectTemplate,
  });

  final PlaygroundChannel? initialChannel;
  final String? currentModel;
  final ValueChanged<VisualPromptTemplate> onSelectTemplate;

  static Future<void> show(
    BuildContext context, {
    PlaygroundChannel? initialChannel,
    String? currentModel,
    required ValueChanged<VisualPromptTemplate> onSelectTemplate,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => PromptTemplateSheet(
        initialChannel: initialChannel,
        currentModel: currentModel,
        onSelectTemplate: onSelectTemplate,
      ),
    );
  }

  @override
  State<PromptTemplateSheet> createState() => _PromptTemplateSheetState();
}

class _PromptTemplateSheetState extends State<PromptTemplateSheet> {
  final _store = PromptTemplateStore.instance;
  final _searchCtrl = TextEditingController();

  String _selectedCategory = 'all'; // all or TemplateMajorCategory.id
  PlaygroundChannel? _filterChannel;
  VisualPromptTemplate? _selectedTemplate;

  @override
  void initState() {
    super.initState();
    _filterChannel = widget.initialChannel;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<VisualPromptTemplate> get _filteredTemplates {
    return _store.filter(
      majorCategory: _selectedCategory == 'all' ? null : _selectedCategory,
      channel: _filterChannel,
      searchQuery: _searchCtrl.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.borderSubtle),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080, maxHeight: 720),
        child: Column(
          children: [
            _buildHeader(context),
            const Divider(height: 1),
            _buildFilterBar(context),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<List<VisualPromptTemplate>>(
                stream: _store.templatesStream,
                builder: (context, snapshot) {
                  final list = _filteredTemplates;
                  if (list.isEmpty) {
                    return _buildEmptyState(context);
                  }
                  return Row(
                    children: [
                      // 左侧卡片列表
                      Expanded(
                        flex: 5,
                        child: _buildTemplateGrid(context, list),
                      ),
                      const VerticalDivider(width: 1),
                      // 右侧详情与实测样片面板
                      Expanded(
                        flex: 6,
                        child: _buildDetailPanel(context),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, color: context.accentText, size: 20),
          const SizedBox(width: 10),
          Text(
            '视觉提示词模板效果库',
            style: TextStyle(
              color: context.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: context.bgSelected.withOpacity(0.4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${_store.templates.length} 个预置模板',
              style: TextStyle(color: context.accentText, fontSize: 11),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.close, size: 20, color: context.textSecondary),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: '关闭',
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: context.bgContent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 搜索框
              SizedBox(
                width: 240,
                height: 32,
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(fontSize: 12, color: context.textPrimary),
                  decoration: InputDecoration(
                    hintText: '搜索模板标题、关键词或标签...',
                    hintStyle: TextStyle(fontSize: 12, color: context.textTertiary),
                    prefixIcon: Icon(Icons.search, size: 16, color: context.textTertiary),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    filled: true,
                    fillColor: context.bgCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: context.borderSubtle),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: context.borderSubtle),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // 通道筛选 Chip
              Text('通道: ', style: TextStyle(color: context.textSecondary, fontSize: 12)),
              const SizedBox(width: 6),
              _buildChannelChip('全部', null),
              const SizedBox(width: 6),
              _buildChannelChip('视频', PlaygroundChannel.video),
              const SizedBox(width: 6),
              _buildChannelChip('图像', PlaygroundChannel.image),
            ],
          ),
          const SizedBox(height: 8),
          // 5 大体系分类
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildCategoryTab('全部体系', 'all'),
                for (final cat in TemplateMajorCategory.values) ...[
                  const SizedBox(width: 6),
                  _buildCategoryTab(cat.label, cat.id),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelChip(String label, PlaygroundChannel? channel) {
    final isSelected = _filterChannel == channel;
    return InkWell(
      onTap: () => setState(() => _filterChannel = channel),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? context.accentText.withOpacity(0.12) : context.bgCard,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? context.accentText : context.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? context.accentText : context.textSecondary,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryTab(String label, String id) {
    final isSelected = _selectedCategory == id;
    return InkWell(
      onTap: () => setState(() => _selectedCategory = id),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? context.accentText : context.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? context.accentText : context.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : context.textPrimary,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 48, color: context.textTertiary),
          const SizedBox(height: 12),
          Text(
            '未找到匹配的提示词模板',
            style: TextStyle(color: context.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateGrid(BuildContext context, List<VisualPromptTemplate> list) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = list[index];
        final isSelected = _selectedTemplate?.id == item.id;
        final benchmark = item.benchmarkFor(widget.currentModel ?? '');

        return InkWell(
          onTap: () => setState(() => _selectedTemplate = item),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected ? context.bgSelected.withOpacity(0.5) : context.bgCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? context.accentText : context.borderSubtle,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: item.channel == PlaygroundChannel.video
                            ? Colors.purple.withOpacity(0.15)
                            : Colors.blue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.channel.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: item.channel == PlaygroundChannel.video
                              ? Colors.purple
                              : Colors.blue,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: context.bgContent,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: context.borderSubtle),
                      ),
                      child: Text(
                        item.subcategory,
                        style: TextStyle(fontSize: 10, color: context.textSecondary),
                      ),
                    ),
                    const Spacer(),
                    if (benchmark != null) ...[
                      const Icon(Icons.star, size: 13, color: Colors.amber),
                      Text(
                        '${benchmark.qualityRating}星',
                        style: const TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  item.title,
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.promptTemplate,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.textSecondary, fontSize: 11, height: 1.4),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: item.tags.take(4).map((tag) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: context.bgContent,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        '#$tag',
                        style: TextStyle(color: context.textTertiary, fontSize: 10),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailPanel(BuildContext context) {
    final template = _selectedTemplate ??
        (_filteredTemplates.isNotEmpty ? _filteredTemplates.first : null);

    if (template == null) {
      return Center(
        child: Text(
          '请选择左侧模板查看详情与实测样片',
          style: TextStyle(color: context.textTertiary, fontSize: 13),
        ),
      );
    }

    final benchmark = template.benchmarkFor(widget.currentModel ?? '');
    final placeholders = template.placeholders;

    return Container(
      padding: const EdgeInsets.all(18),
      color: context.bgContent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '分类：${template.subcategory} • 适用通道：${template.channel.label}',
                      style: TextStyle(fontSize: 11, color: context.textSecondary),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.input, size: 14),
                label: const Text('载入到控制台', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.accentText,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onPressed: () {
                  widget.onSelectTemplate(template);
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 提示词模板
                  Row(
                    children: [
                      Text(
                        '提示词模板正文',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.copy, size: 12),
                        label: const Text('复制', style: TextStyle(fontSize: 11)),
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: template.promptTemplate));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已复制提示词模板'), duration: Duration(seconds: 1)),
                          );
                        },
                      ),
                    ],
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.bgCard,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: context.borderSubtle),
                    ),
                    child: SelectableText(
                      template.promptTemplate,
                      style: TextStyle(fontSize: 12, color: context.textPrimary, height: 1.5),
                    ),
                  ),

                  // 动态占位符
                  if (placeholders.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      '动态参数占位符（套用时需替换）：',
                      style: TextStyle(fontSize: 11, color: context.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: placeholders.map((p) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.amber.withOpacity(0.5)),
                          ),
                          child: Text(
                            '{$p}',
                            style: const TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.bold),
                          ),
                        );
                      }).toList(),
                    ),
                  ],

                  // 负向词
                  if (template.negativePrompt != null && template.negativePrompt!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      '推荐避雷/负向词 (Negative Prompt)',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: context.bgCard,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: context.borderSubtle),
                      ),
                      child: SelectableText(
                        template.negativePrompt!,
                        style: TextStyle(fontSize: 11, color: context.textSecondary),
                      ),
                    ),
                  ],

                  // 推荐参数
                  if (template.recommendedParams.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      '推荐生成参数',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      children: template.recommendedParams.entries.map((e) {
                        return Chip(
                          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                          visualDensity: VisualDensity.compact,
                          label: Text('${e.key}: ${e.value}', style: const TextStyle(fontSize: 10)),
                        );
                      }).toList(),
                    ),
                  ],

                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  // 模型特异性评测样片区
                  Row(
                    children: [
                      Icon(Icons.biotech_outlined, size: 16, color: context.accentText),
                      const SizedBox(width: 6),
                      Text(
                        '模型实测样片 (Benchmark)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: context.textPrimary),
                      ),
                      const Spacer(),
                      if (benchmark != null)
                        Text(
                          '测试模型: ${benchmark.modelName}',
                          style: TextStyle(fontSize: 11, color: context.textSecondary),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildBenchmarkView(context, template, benchmark),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenchmarkView(
    BuildContext context,
    VisualPromptTemplate template,
    TemplateModelBenchmark? benchmark,
  ) {
    if (benchmark == null || !File(benchmark.sampleMediaPath).existsSync()) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: context.bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.borderSubtle, style: BorderStyle.solid),
        ),
        child: Column(
          children: [
            Icon(Icons.video_library_outlined, size: 36, color: context.textTertiary),
            const SizedBox(height: 8),
            Text(
              '当前模型尚未沉淀实测样片',
              style: TextStyle(color: context.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              '可载入模板后在试炼场发起调用，将满意产物设为该模型的标准样例',
              style: TextStyle(color: context.textTertiary, fontSize: 11),
            ),
          ],
        ),
      );
    }

    final file = File(benchmark.sampleMediaPath);
    final isVideo = template.channel == PlaygroundChannel.video;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Row(
                children: List.generate(5, (index) {
                  return Icon(
                    index < benchmark.qualityRating ? Icons.star : Icons.star_border,
                    size: 14,
                    color: Colors.amber,
                  );
                }),
              ),
              const SizedBox(width: 8),
              if (benchmark.isRecommended)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text('官方标杆', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => _openMedia(file),
                child: const Text('系统应用查看', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: isVideo
                ? GestureDetector(
                    onTap: () => _openMedia(file),
                    child: Container(
                      height: 160,
                      width: double.infinity,
                      color: Colors.black87,
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_circle_filled, size: 40, color: Colors.white70),
                            SizedBox(height: 4),
                            Text('点击调用播放器查看实测视频', style: TextStyle(color: Colors.white70, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  )
                : GestureDetector(
                    onTap: () => _openMedia(file),
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      width: double.infinity,
                      child: Image.file(file, fit: BoxFit.contain),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _openMedia(File file) {
    if (file.existsSync()) {
      Process.run('open', [file.path]);
    }
  }
}
