import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../models/studio_models.dart';
import '../services/studio_preset_store.dart';

/// 美学风格与时代题材预设管理中心。
///
/// 支持查看 8 大体系 35 套工业级美学预设与时代题材预设、
/// 编辑正负向提示词词库、新增自定义预设，以及一键恢复出厂预设。
class StudioPresetManagementDialog extends StatefulWidget {
  const StudioPresetManagementDialog({
    super.key,
    this.initialTab = 0,
    this.initialStyleId,
    this.initialEraId,
    this.initialTemplateId,
  });

  final int initialTab;
  final String? initialStyleId;
  final String? initialEraId;
  final String? initialTemplateId;

  static Future<void> show(
    BuildContext context, {
    int initialTab = 0,
    String? initialStyleId,
    String? initialEraId,
    String? initialTemplateId,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => StudioPresetManagementDialog(
        initialTab: initialTab,
        initialStyleId: initialStyleId,
        initialEraId: initialEraId,
        initialTemplateId: initialTemplateId,
      ),
    );
  }

  @override
  State<StudioPresetManagementDialog> createState() =>
      _StudioPresetManagementDialogState();
}

class _StudioPresetManagementDialogState
    extends State<StudioPresetManagementDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _store = StudioPresetStore.instance;

  // --- 风格 Tab 状态 ---
  String? _selectedStyleId;
  String _styleCategoryFilter = '全部';
  String _styleSearchKeyword = '';
  final _styleNameCtrl = TextEditingController();
  final _styleCatCtrl = TextEditingController();
  final _styleDescCtrl = TextEditingController();
  final _stylePositiveCtrl = TextEditingController();
  final _styleNegativeCtrl = TextEditingController();
  final _styleRatioCtrl = TextEditingController(text: '16:9');
  bool _isCreatingNewStyle = false;

  // --- 时代 Tab 状态 ---
  String? _selectedEraId;
  String _eraSearchKeyword = '';
  final _eraIdCtrl = TextEditingController();
  final _eraLabelCtrl = TextEditingController();
  final _eraDescCtrl = TextEditingController();
  final _eraCostumeCtrl = TextEditingController();
  final _eraEnvCtrl = TextEditingController();
  final _eraPropCtrl = TextEditingController();
  final _eraNegativeCtrl = TextEditingController();
  bool _isCreatingNewEra = false;

  // --- 提示词与规则 Tab 状态 ---
  String? _selectedTemplateId;
  String _templateCategoryFilter = '全部';
  String _templateSearchKeyword = '';
  final _templateContentCtrl = TextEditingController();
  bool _showTemplateDefaultDiff = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );

    // 初始选中风格
    final styles = _store.styles;
    if (styles.isNotEmpty) {
      final initial = widget.initialStyleId != null
          ? _store.getStyleById(widget.initialStyleId) ?? styles.first
          : styles.first;
      _selectStyle(initial);
    }

    // 初始选中题材
    final eras = _store.eras;
    if (eras.isNotEmpty) {
      final initial = widget.initialEraId != null
          ? _store.getEraById(widget.initialEraId) ?? eras.first
          : eras.first;
      _selectEra(initial);
    }

    // 初始选中提示词模板
    final templates = _store.templates;
    if (templates.isNotEmpty) {
      final initial = widget.initialTemplateId != null
          ? _store.getTemplateById(widget.initialTemplateId!) ?? templates.first
          : templates.first;
      _selectTemplate(initial);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _styleNameCtrl.dispose();
    _styleCatCtrl.dispose();
    _styleDescCtrl.dispose();
    _stylePositiveCtrl.dispose();
    _styleNegativeCtrl.dispose();
    _styleRatioCtrl.dispose();
    _eraIdCtrl.dispose();
    _eraLabelCtrl.dispose();
    _eraDescCtrl.dispose();
    _eraCostumeCtrl.dispose();
    _eraEnvCtrl.dispose();
    _eraPropCtrl.dispose();
    _eraNegativeCtrl.dispose();
    _templateContentCtrl.dispose();
    super.dispose();
  }

  void _selectStyle(AestheticStyle style) {
    setState(() {
      _isCreatingNewStyle = false;
      _selectedStyleId = style.id;
      _styleNameCtrl.text = style.nameZh;
      _styleCatCtrl.text = style.category;
      _styleDescCtrl.text = style.descriptionZh;
      _stylePositiveCtrl.text = style.positiveAnchor;
      _styleNegativeCtrl.text = style.negativeBan;
      _styleRatioCtrl.text = style.defaultRatio;
    });
  }

  void _startCreateNewStyle() {
    setState(() {
      _isCreatingNewStyle = true;
      _selectedStyleId = null;
      _styleNameCtrl.clear();
      _styleCatCtrl.text = '自定义风格';
      _styleDescCtrl.clear();
      _stylePositiveCtrl.clear();
      _styleNegativeCtrl.clear();
      _styleRatioCtrl.text = '16:9';
    });
  }

  void _selectEra(VisualEraGenre era) {
    setState(() {
      _isCreatingNewEra = false;
      _selectedEraId = era.id;
      _eraIdCtrl.text = era.id;
      _eraLabelCtrl.text = era.labelZh;
      _eraDescCtrl.text = era.descriptionZh;
      _eraCostumeCtrl.text = era.costumeAnchor;
      _eraEnvCtrl.text = era.environmentAnchor;
      _eraPropCtrl.text = era.propMaterialAnchor;
      _eraNegativeCtrl.text = era.negativeBans;
    });
  }

  void _startCreateNewEra() {
    setState(() {
      _isCreatingNewEra = true;
      _selectedEraId = null;
      _eraIdCtrl.clear();
      _eraLabelCtrl.clear();
      _eraDescCtrl.clear();
      _eraCostumeCtrl.clear();
      _eraEnvCtrl.clear();
      _eraPropCtrl.clear();
      _eraNegativeCtrl.clear();
    });
  }

  Future<void> _saveCurrentStyle() async {
    final name = _styleNameCtrl.text.trim();
    if (name.isEmpty) {
      _showToast('风格中文名称不能为空');
      return;
    }

    final id = _isCreatingNewStyle
        ? 'custom_style_${DateTime.now().millisecondsSinceEpoch}'
        : (_selectedStyleId ?? 'custom_style_${DateTime.now().millisecondsSinceEpoch}');

    final updated = AestheticStyle(
      id: id,
      category: _styleCatCtrl.text.trim().isEmpty ? '自定义风格' : _styleCatCtrl.text.trim(),
      nameZh: name,
      descriptionZh: _styleDescCtrl.text.trim(),
      positiveAnchor: _stylePositiveCtrl.text.trim(),
      negativeBan: _styleNegativeCtrl.text.trim(),
      defaultRatio: _styleRatioCtrl.text.trim().isEmpty ? '16:9' : _styleRatioCtrl.text.trim(),
      isBuiltin: !_isCreatingNewStyle && (_store.getStyleById(id)?.isBuiltin ?? false),
    );

    await _store.saveStyle(updated);
    _selectStyle(updated);
    _showToast('风格预设已保存');
  }

  Future<void> _deleteCurrentStyle() async {
    if (_selectedStyleId == null) return;
    final style = _store.getStyleById(_selectedStyleId);
    if (style == null || style.isBuiltin) {
      _showToast('内置出厂预设不可删除');
      return;
    }

    final confirm = await _showConfirmDialog(
      title: '删除自定义风格',
      content: '确定要删除自定义风格「${style.nameZh}」吗？',
    );
    if (confirm != true) return;

    await _store.deleteStyle(_selectedStyleId!);
    final remaining = _store.styles;
    if (remaining.isNotEmpty) {
      _selectStyle(remaining.first);
    }
    _showToast('已删除风格预设');
  }

  Future<void> _resetStyles() async {
    final confirm = await _showConfirmDialog(
      title: '恢复风格出厂预设',
      content: '确定要恢复所有 35 套工业级美学风格出厂设置吗？这将重置对内置风格的修改，并保留自定义风格。',
    );
    if (confirm != true) return;

    await _store.resetStylesToDefault();
    final styles = _store.styles;
    if (styles.isNotEmpty) {
      _selectStyle(styles.first);
    }
    _showToast('已恢复出厂风格预设');
  }

  Future<void> _saveCurrentEra() async {
    final id = _eraIdCtrl.text.trim().toLowerCase();
    final label = _eraLabelCtrl.text.trim();
    if (id.isEmpty || label.isEmpty) {
      _showToast('题材 ID 与中文名称不能为空');
      return;
    }

    final updated = VisualEraGenre(
      id: id,
      labelZh: label,
      descriptionZh: _eraDescCtrl.text.trim(),
      costumeAnchor: _eraCostumeCtrl.text.trim(),
      environmentAnchor: _eraEnvCtrl.text.trim(),
      propMaterialAnchor: _eraPropCtrl.text.trim(),
      negativeBans: _eraNegativeCtrl.text.trim(),
      isBuiltin: !_isCreatingNewEra && (_store.getEraById(id)?.isBuiltin ?? false),
    );

    await _store.saveEra(updated);
    _selectEra(updated);
    _showToast('时代题材预设已保存');
  }

  Future<void> _deleteCurrentEra() async {
    if (_selectedEraId == null) return;
    final era = _store.getEraById(_selectedEraId);
    if (era == null || era.isBuiltin) {
      _showToast('内置时代题材不可删除');
      return;
    }

    final confirm = await _showConfirmDialog(
      title: '删除自定义题材',
      content: '确定要删除自定义题材「${era.labelZh}」吗？',
    );
    if (confirm != true) return;

    await _store.deleteEra(_selectedEraId!);
    final remaining = _store.eras;
    if (remaining.isNotEmpty) {
      _selectEra(remaining.first);
    }
    _showToast('已删除题材预设');
  }

  Future<void> _resetEras() async {
    final confirm = await _showConfirmDialog(
      title: '恢复题材出厂预设',
      content: '确定要恢复时代题材出厂设置吗？这将重置对内置题材的修改。',
    );
    if (confirm != true) return;

    await _store.resetErasToDefault();
    final eras = _store.eras;
    if (eras.isNotEmpty) {
      _selectEra(eras.first);
    }
    _showToast('已恢复出厂题材预设');
  }

  // --- 提示词模板操作方法 ---

  void _selectTemplate(StudioPromptTemplate template) {
    setState(() {
      _selectedTemplateId = template.id;
      _templateContentCtrl.text = template.content;
      _showTemplateDefaultDiff = false;
    });
  }

  Future<void> _saveTemplate() async {
    if (_selectedTemplateId == null) return;
    final current = _store.getTemplateById(_selectedTemplateId!);
    if (current == null) return;

    final updated = current.copyWith(
      content: _templateContentCtrl.text.trim(),
      updatedAt: DateTime.now(),
    );

    await _store.saveTemplate(updated);
    setState(() {});
    _showToast('提示词与规则「${current.name}」已保存并即时生效');
  }

  Future<void> _resetCurrentTemplate() async {
    if (_selectedTemplateId == null) return;
    final current = _store.getTemplateById(_selectedTemplateId!);
    if (current == null) return;

    final confirm = await _showConfirmDialog(
      title: '恢复提示词出厂默认',
      content: '确定要将「${current.name}」恢复为出厂预置规则吗？您所做的自定义修改将被替换。',
    );
    if (confirm != true) return;

    await _store.resetTemplateToDefault(_selectedTemplateId!);
    final refreshed = _store.getTemplateById(_selectedTemplateId!);
    if (refreshed != null) {
      _selectTemplate(refreshed);
    }
    _showToast('「${current.name}」已恢复出厂默认');
  }

  Future<void> _resetAllTemplates() async {
    final confirm = await _showConfirmDialog(
      title: '恢复全部提示词出厂预置',
      content: '确定要将所有系统提示词与排版规则恢复为出厂默认吗？全部自定义修改都将重置。',
    );
    if (confirm != true) return;

    await _store.resetAllTemplatesToDefault();
    final templates = _store.templates;
    if (templates.isNotEmpty) {
      final initial = _selectedTemplateId != null
          ? _store.getTemplateById(_selectedTemplateId!) ?? templates.first
          : templates.first;
      _selectTemplate(initial);
    }
    _showToast('全部系统提示词已恢复出厂默认');
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String content,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.bgCard,
        title: Text(title, style: TextStyle(color: ctx.textPrimary)),
        content: Text(content, style: TextStyle(color: ctx.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: TextStyle(color: ctx.textTertiary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ctx.errorSolid,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 1080,
          maxHeight: 760,
          minWidth: 840,
          minHeight: 600,
        ),
        child: Column(
          children: [
            _buildHeader(context),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildStylesTab(context),
                  _buildErasTab(context),
                  _buildTemplatesTab(context),
                ],
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
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: context.accentSolid.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.tune_outlined, color: context.accentText, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '短视频工坊·预设与系统规则管理中心',
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                      ),
                      child: const Text(
                        '工业级正负向锁 & 5大系统提示词',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '全局持久化预设管理中心：支持风格正负向防崩词、题材环境、三视图/场景/道具/拆镜规则自定义与恢复出厂',
                  style: TextStyle(color: context.textTertiary, fontSize: 12),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 460,
            child: TabBar(
              controller: _tabController,
              labelColor: context.accentText,
              unselectedLabelColor: context.textSecondary,
              indicatorColor: context.accentSolid,
              tabs: [
                Tab(text: '美学风格 (${_store.styles.length})'),
                Tab(text: '时代题材 (${_store.eras.length})'),
                Tab(text: '系统提示词 (${_store.templates.length})'),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: Icon(Icons.close, color: context.textTertiary, size: 20),
            tooltip: '关闭',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 美学风格 Tab 视图
  // ==========================================
  Widget _buildStylesTab(BuildContext context) {
    final allStyles = _store.styles;
    final categories = ['全部', ..._store.stylesByCategory.keys];

    final filteredStyles = allStyles.where((s) {
      if (_styleCategoryFilter != '全部' && s.category != _styleCategoryFilter) {
        return false;
      }
      if (_styleSearchKeyword.trim().isNotEmpty) {
        final kw = _styleSearchKeyword.trim().toLowerCase();
        return s.nameZh.toLowerCase().contains(kw) ||
            s.descriptionZh.toLowerCase().contains(kw) ||
            s.positiveAnchor.toLowerCase().contains(kw);
      }
      return true;
    }).toList();

    return Row(
      children: [
        // 左侧风格列表
        SizedBox(
          width: 330,
          child: Column(
            children: [
              // 搜索与分类栏
              Container(
                padding: const EdgeInsets.all(12),
                color: context.bgCard,
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: '搜索风格名称/关键词…',
                        hintStyle: TextStyle(color: context.textTertiary, fontSize: 12),
                        prefixIcon: const Icon(Icons.search, size: 16),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: context.borderSubtle),
                        ),
                      ),
                      style: TextStyle(color: context.textPrimary, fontSize: 12),
                      onChanged: (val) => setState(() => _styleSearchKeyword = val),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final cat in categories)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(cat, style: const TextStyle(fontSize: 11)),
                                selected: _styleCategoryFilter == cat,
                                onSelected: (sel) {
                                  if (sel) setState(() => _styleCategoryFilter = cat);
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // 风格项目列表
              Expanded(
                child: ListView.separated(
                  itemCount: filteredStyles.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, idx) {
                    final s = filteredStyles[idx];
                    final isSelected = !_isCreatingNewStyle && s.id == _selectedStyleId;
                    return ListTile(
                      dense: true,
                      selected: isSelected,
                      selectedTileColor: context.accentSubtle,
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.nameZh,
                              style: TextStyle(
                                color: isSelected ? context.accentText : context.textPrimary,
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: context.bgCard,
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(color: context.borderSubtle),
                            ),
                            child: Text(
                              s.defaultRatio,
                              style: TextStyle(color: context.textTertiary, fontSize: 10),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        '${s.category} · ${s.descriptionZh}',
                        style: TextStyle(color: context.textTertiary, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: s.isBuiltin
                          ? Icon(Icons.lock_outline, size: 14, color: context.textTertiary)
                          : Icon(Icons.edit_note, size: 16, color: context.accentText),
                      onTap: () => _selectStyle(s),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              // 底部工具栏
              Container(
                padding: const EdgeInsets.all(10),
                color: context.bgCard,
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('新增自定义风格', style: TextStyle(fontSize: 12)),
                        onPressed: _startCreateNewStyle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.restore, size: 18),
                      tooltip: '恢复出厂风格预设',
                      onPressed: _resetStyles,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // 右侧风格详情与编辑面板
        Expanded(
          child: _buildStyleDetailEditor(context),
        ),
      ],
    );
  }

  Widget _buildStyleDetailEditor(BuildContext context) {
    final currentStyle = _selectedStyleId != null ? _store.getStyleById(_selectedStyleId) : null;
    final isBuiltin = currentStyle?.isBuiltin ?? false;

    return Container(
      color: context.bgCard,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _isCreatingNewStyle
                    ? '新增自定义美学风格'
                    : '美学风格详情：${_styleNameCtrl.text}',
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 10),
              if (!_isCreatingNewStyle)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isBuiltin
                        ? Colors.blueGrey.withValues(alpha: 0.15)
                        : Colors.purple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isBuiltin ? '出厂内置预设' : '用户自定义',
                    style: TextStyle(
                      color: isBuiltin ? Colors.blueGrey : Colors.purple,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const Spacer(),
              if (!_isCreatingNewStyle && !isBuiltin)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                  tooltip: '删除此自定义风格',
                  onPressed: _deleteCurrentStyle,
                ),
              ElevatedButton.icon(
                icon: const Icon(Icons.save, size: 16),
                label: const Text('保存预设'),
                onPressed: _saveCurrentStyle,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: _buildTextField(
                          controller: _styleNameCtrl,
                          label: '风格名称 (中文)',
                          hint: '如：UE5 3D国漫·东方玄幻',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          controller: _styleCatCtrl,
                          label: '体系分类',
                          hint: '如：东方国风 / 日系二次元',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          controller: _styleRatioCtrl,
                          label: '推荐比例',
                          hint: '如：16:9 / 9:16',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _styleDescCtrl,
                    label: '风格特色说明与推荐应用',
                    hint: '简要说明适用故事场景、光影材质特色与色彩基调',
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(Icons.check_circle_outline, color: Colors.green, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '正向风格锁提示词 (Positive Anchor)',
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _buildTextField(
                    controller: _stylePositiveCtrl,
                    label: '',
                    hint: '包含工业级画质基线、次世代材质、粒子体积光与电影级构图…',
                    maxLines: 4,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(Icons.block, color: Colors.redAccent, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '美学专属负向排他违禁词 (Negative Ban)',
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _buildTextField(
                    controller: _styleNegativeCtrl,
                    label: '',
                    hint: '排斥与此画风相冲突的表现形式（如3D排斥2D手绘、写实排斥卡通漫画等）…',
                    maxLines: 4,
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.bgCard,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.borderSubtle),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '底模通用防崩词（生成时自动装配于第 3 层）',
                          style: TextStyle(
                            color: context.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AestheticStyle.universalNegativeBrief,
                          style: TextStyle(color: context.textTertiary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 时代题材 Tab 视图
  // ==========================================
  Widget _buildErasTab(BuildContext context) {
    final allEras = _store.eras;
    final filteredEras = allEras.where((e) {
      if (_eraSearchKeyword.trim().isNotEmpty) {
        final kw = _eraSearchKeyword.trim().toLowerCase();
        return e.labelZh.toLowerCase().contains(kw) ||
            e.id.toLowerCase().contains(kw) ||
            e.descriptionZh.toLowerCase().contains(kw);
      }
      return true;
    }).toList();

    return Row(
      children: [
        // 左侧题材列表
        SizedBox(
          width: 320,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                color: context.bgCard,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: '搜索题材名称/ID…',
                    hintStyle: TextStyle(color: context.textTertiary, fontSize: 12),
                    prefixIcon: const Icon(Icons.search, size: 16),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: context.borderSubtle),
                    ),
                  ),
                  style: TextStyle(color: context.textPrimary, fontSize: 12),
                  onChanged: (val) => setState(() => _eraSearchKeyword = val),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount: filteredEras.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, idx) {
                    final era = filteredEras[idx];
                    final isSelected = !_isCreatingNewEra && era.id == _selectedEraId;
                    return ListTile(
                      dense: true,
                      selected: isSelected,
                      selectedTileColor: context.accentSubtle,
                      title: Text(
                        era.labelZh,
                        style: TextStyle(
                          color: isSelected ? context.accentText : context.textPrimary,
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        'ID: ${era.id} · ${era.descriptionZh}',
                        style: TextStyle(color: context.textTertiary, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: era.isBuiltin
                          ? Icon(Icons.lock_outline, size: 14, color: context.textTertiary)
                          : Icon(Icons.edit_note, size: 16, color: context.accentText),
                      onTap: () => _selectEra(era),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Container(
                padding: const EdgeInsets.all(10),
                color: context.bgCard,
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('新增自定义题材', style: TextStyle(fontSize: 12)),
                        onPressed: _startCreateNewEra,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.restore, size: 18),
                      tooltip: '恢复出厂题材预设',
                      onPressed: _resetEras,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // 右侧题材详情与编辑面板
        Expanded(
          child: _buildEraDetailEditor(context),
        ),
      ],
    );
  }

  Widget _buildEraDetailEditor(BuildContext context) {
    final currentEra = _selectedEraId != null ? _store.getEraById(_selectedEraId) : null;
    final isBuiltin = currentEra?.isBuiltin ?? false;

    return Container(
      color: context.bgCard,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _isCreatingNewEra
                    ? '新增自定义时代题材'
                    : '时代题材详情：${_eraLabelCtrl.text}',
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 10),
              if (!_isCreatingNewEra)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isBuiltin
                        ? Colors.blueGrey.withValues(alpha: 0.15)
                        : Colors.teal.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isBuiltin ? '出厂内置题材' : '用户自定义',
                    style: TextStyle(
                      color: isBuiltin ? Colors.blueGrey : Colors.teal,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const Spacer(),
              if (!_isCreatingNewEra && !isBuiltin)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                  tooltip: '删除此自定义题材',
                  onPressed: _deleteCurrentEra,
                ),
              ElevatedButton.icon(
                icon: const Icon(Icons.save, size: 16),
                label: const Text('保存题材'),
                onPressed: _saveCurrentEra,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: _eraIdCtrl,
                          label: '题材 ID (英文字母/下划线)',
                          hint: '如：republic_spy / ancient_palace',
                          readOnly: !_isCreatingNewEra && isBuiltin,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          controller: _eraLabelCtrl,
                          label: '题材名称 (中文)',
                          hint: '如：民国谍战 / 宫廷权谋',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _eraDescCtrl,
                    label: '题材时代背景与视觉特色说明',
                    hint: '描述时代服装风貌、历史特征与环境调性',
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  _buildTextField(
                    controller: _eraCostumeCtrl,
                    label: '时代服饰材质正向锚点 (Costume Anchor)',
                    hint: '如：qipao, cheongsam, trench coat, fedora hat, wool suit',
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _eraEnvCtrl,
                    label: '时代空间建筑与光影锚点 (Environment Anchor)',
                    hint: '如：1930s Shanghai street, French concession, gas lamps, brick alleys',
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _eraPropCtrl,
                    label: '时代标志道具与器物锚点 (Prop Anchor)',
                    hint: '如：revolver, vintage telephone, telegraph, pocket watch, leather suitcase',
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(Icons.shield_outlined, color: Colors.redAccent, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '时代负向排他违禁词 (Negative Bans - 杜绝时空穿帮)',
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _buildTextField(
                    controller: _eraNegativeCtrl,
                    label: '',
                    hint: '严禁出现的后世或前代穿越冲突物品（如现代手机、羽绒服、高铁、高楼大厦等）…',
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 系统提示词与规则 Tab 视图 (spec: studio-prompt-templates)
  // ==========================================
  Widget _buildTemplatesTab(BuildContext context) {
    final allTemplates = _store.templates;
    const categories = ['全部', '资产生成规范', '导演调度规范'];

    final filteredTemplates = allTemplates.where((t) {
      if (_templateCategoryFilter != '全部' &&
          t.category != _templateCategoryFilter) {
        return false;
      }
      if (_templateSearchKeyword.trim().isNotEmpty) {
        final kw = _templateSearchKeyword.trim().toLowerCase();
        return t.name.toLowerCase().contains(kw) ||
            t.id.toLowerCase().contains(kw) ||
            t.description.toLowerCase().contains(kw) ||
            t.content.toLowerCase().contains(kw);
      }
      return true;
    }).toList();

    final currentTemplate = _selectedTemplateId != null
        ? _store.getTemplateById(_selectedTemplateId!)
        : null;

    return Row(
      children: [
        // 左侧模板导航列表
        SizedBox(
          width: 340,
          child: Column(
            children: [
              // 搜索与分类
              Container(
                padding: const EdgeInsets.all(12),
                color: context.bgCard,
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: '搜索提示词名称/关键词…',
                        hintStyle: TextStyle(
                            color: context.textTertiary, fontSize: 12),
                        prefixIcon: const Icon(Icons.search, size: 16),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: context.borderSubtle),
                        ),
                      ),
                      style:
                          TextStyle(color: context.textPrimary, fontSize: 12),
                      onChanged: (val) =>
                          setState(() => _templateSearchKeyword = val),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final cat in categories)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(cat,
                                    style: const TextStyle(fontSize: 11)),
                                selected: _templateCategoryFilter == cat,
                                onSelected: (sel) {
                                  if (sel) {
                                    setState(
                                        () => _templateCategoryFilter = cat);
                                  }
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // 模板列表
              Expanded(
                child: ListView.separated(
                  itemCount: filteredTemplates.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, idx) {
                    final t = filteredTemplates[idx];
                    final isSelected = t.id == _selectedTemplateId;
                    return ListTile(
                      dense: true,
                      selected: isSelected,
                      selectedTileColor: context.accentSubtle,
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              t.name,
                              style: TextStyle(
                                color: isSelected
                                    ? context.accentText
                                    : context.textPrimary,
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (t.isModifiedFromDefault)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                    color:
                                        Colors.orange.withValues(alpha: 0.4)),
                              ),
                              child: const Text(
                                '已自定义',
                                style: TextStyle(
                                    color: Colors.orange, fontSize: 10),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: context.bgContent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '出厂默认',
                                style: TextStyle(
                                    color: context.textTertiary, fontSize: 10),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        t.description,
                        style: TextStyle(
                            color: context.textTertiary, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _selectTemplate(t),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              // 底部恢复全部出厂按钮
              Container(
                padding: const EdgeInsets.all(12),
                color: context.bgCard,
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.textSecondary,
                      side: BorderSide(color: context.borderSubtle),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.restore, size: 16),
                    label: const Text('恢复全部提示词出厂默认',
                        style: TextStyle(fontSize: 12)),
                    onPressed: _resetAllTemplates,
                  ),
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // 右侧模板编辑器
        Expanded(
          child: currentTemplate == null
              ? Center(
                  child: Text(
                    '请从左侧选择需要查看或编辑的系统提示词模板',
                    style: TextStyle(color: context.textTertiary, fontSize: 13),
                  ),
                )
              : Container(
                  color: context.bgContent,
                  child: Column(
                    children: [
                      // 编辑器顶部操作栏
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        color: context.bgCard,
                        child: Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      currentTemplate.name,
                                      style: TextStyle(
                                        color: context.textPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: context.accentSubtle,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        currentTemplate.category,
                                        style: TextStyle(
                                          color: context.accentText,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'ID: ${currentTemplate.id}',
                                      style: TextStyle(
                                        color: context.textTertiary,
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '出厂内置核心规范 · 支持编辑并即时生效',
                                  style: TextStyle(
                                      color: context.textTertiary, fontSize: 11),
                                ),
                              ],
                            ),
                            const Spacer(),
                            if (currentTemplate.isModifiedFromDefault) ...[
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.orange,
                                ),
                                icon: const Icon(Icons.replay, size: 16),
                                label: const Text('恢复此项默认',
                                    style: TextStyle(fontSize: 12)),
                                onPressed: _resetCurrentTemplate,
                              ),
                              const SizedBox(width: 10),
                            ],
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: context.accentSolid,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                              ),
                              icon: const Icon(Icons.save_outlined, size: 16),
                              label: const Text('保存生效',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold)),
                              onPressed: _saveTemplate,
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      // 编辑器表单内容
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 规范定位与占位说明卡片
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: context.bgCard,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: context.borderSubtle),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.info_outline,
                                        color: context.accentText, size: 18),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '规范目的与作用域',
                                            style: TextStyle(
                                              color: context.textPrimary,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            currentTemplate.description,
                                            style: TextStyle(
                                              color: context.textSecondary,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              // 提示词模板正文
                              Row(
                                children: [
                                  Text(
                                    '系统提示词与规则正文（纯中文自然语言）',
                                    style: TextStyle(
                                      color: context.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '对齐 Agnes 纯中文规范 · 保存后全局生图即时读取',
                                    style: TextStyle(
                                      color: context.textTertiary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _templateContentCtrl,
                                maxLines: null,
                                minLines: 12,
                                style: TextStyle(
                                  color: context.textPrimary,
                                  fontSize: 13,
                                  height: 1.5,
                                  fontFamily: 'monospace',
                                ),
                                decoration: InputDecoration(
                                  hintText: '输入该系统提示词或排版规则的模板内容…',
                                  hintStyle: TextStyle(
                                      color: context.textTertiary, fontSize: 12),
                                  filled: true,
                                  fillColor: context.bgCard,
                                  contentPadding: const EdgeInsets.all(14),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide:
                                        BorderSide(color: context.borderSubtle),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide:
                                        BorderSide(color: context.borderSubtle),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              // 出厂默认对比与查看折叠区
                              if (currentTemplate.isModifiedFromDefault) ...[
                                Container(
                                  decoration: BoxDecoration(
                                    color: context.bgCard,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: context.borderSubtle),
                                  ),
                                  child: Column(
                                    children: [
                                      ListTile(
                                        dense: true,
                                        leading: const Icon(
                                            Icons.compare_arrows,
                                            size: 18),
                                        title: const Text('查看出厂预置内容',
                                            style: TextStyle(fontSize: 12)),
                                        trailing: Icon(
                                          _showTemplateDefaultDiff
                                              ? Icons.expand_less
                                              : Icons.expand_more,
                                          size: 18,
                                        ),
                                        onTap: () => setState(() =>
                                            _showTemplateDefaultDiff =
                                                !_showTemplateDefaultDiff),
                                      ),
                                      if (_showTemplateDefaultDiff) ...[
                                        const Divider(height: 1),
                                        Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              SelectableText(
                                                currentTemplate.defaultContent,
                                                style: TextStyle(
                                                  color: context.textSecondary,
                                                  fontSize: 12,
                                                  height: 1.4,
                                                  fontFamily: 'monospace',
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              Align(
                                                alignment:
                                                    Alignment.centerRight,
                                                child: TextButton.icon(
                                                  icon: const Icon(
                                                      Icons.content_copy,
                                                      size: 14),
                                                  label: const Text(
                                                      '填入出厂预置内容',
                                                      style: TextStyle(
                                                          fontSize: 11)),
                                                  onPressed: () {
                                                    setState(() {
                                                      _templateContentCtrl.text =
                                                          currentTemplate
                                                              .defaultContent;
                                                    });
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    bool readOnly = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[
          Text(
            label,
            style: TextStyle(
              color: context.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
        ],
        TextField(
          controller: controller,
          maxLines: maxLines,
          readOnly: readOnly,
          style: TextStyle(color: context.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: context.textTertiary, fontSize: 12),
            isDense: true,
            filled: readOnly,
            fillColor: readOnly ? context.bgCard.withValues(alpha: 0.5) : null,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
      ],
    );
  }
}
