/// IP 主库页：角色卡、场景库、世界观设定、集数列表、前情回顾。
///
/// spec 9.4 / 9.5 / 9.6 / 9.7。这一页是「跨集一致性」的控制台——角色长相、
/// 场景、剧情记忆都在这里定，看板只消费不定义。
library;

import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../services/ai_config_store.dart';
import '../../../theme/app_theme.dart';
import '../../ai_video_studio/models/studio_models.dart';
import '../../ai_video_studio/services/ai_constraint_engine.dart';
import '../../ai_video_studio/services/studio_project_manager.dart';
import '../../reader/models/reader_models.dart';
import '../../reader/services/tts_engine.dart';
import 'studio_shell.dart';

class SeriesPage extends StatefulWidget {
  const SeriesPage({super.key, required this.session});

  final StudioSession session;

  @override
  State<SeriesPage> createState() => _SeriesPageState();
}

class _SeriesPageState extends State<SeriesPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final series = widget.session.series;
    if (series == null) {
      return const Center(child: Text('未选择剧集'));
    }
    return Column(
      children: [
        _buildTabs(context),
        const Divider(height: 1),
        Expanded(
          child: switch (_tab) {
            0 => _CharactersTab(series: series),
            1 => _ScenesTab(series: series),
            2 => _WorldviewTab(series: series, session: widget.session),
            _ => _EpisodesTab(series: series, session: widget.session),
          },
        ),
      ],
    );
  }

  Widget _buildTabs(BuildContext context) {
    const labels = ['角色卡', '场景库', '世界观', '集数与前情'];
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _TabButton(
                label: labels[i],
                selected: _tab == i,
                onTap: () => setState(() => _tab = i),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: selected ? context.bgSelected : null,
        foregroundColor: selected ? context.accentText : context.textSecondary,
      ),
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}

/// 角色卡列表 + 编辑。
class _CharactersTab extends StatefulWidget {
  const _CharactersTab({required this.series});

  final StudioSeries series;

  @override
  State<_CharactersTab> createState() => _CharactersTabState();
}

class _CharactersTabState extends State<_CharactersTab> {
  final _manager = StudioProjectManager.instance;
  List<CharacterCard> _characters = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _manager.listCharacters(widget.series.id);
    if (!mounted) return;
    setState(() => _characters = list);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Row(
            children: [
              Text(
                '常驻角色',
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.person_add_alt, size: 16),
                label: const Text('新建角色'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _characters.isEmpty
              ? Center(
                  child: Text(
                    '还没有角色卡。角色越具体，跨集长相越稳。',
                    style: TextStyle(color: context.textTertiary, fontSize: 13),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: _characters.length,
                  itemBuilder: (context, i) => _CharacterCard(
                    character: _characters[i],
                    seriesId: widget.series.id,
                    onChanged: _load,
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _create() async {
    final name = await _promptName(context, '新建角色');
    if (name == null || name.trim().isEmpty) return;
    await _manager.createCharacter(
      seriesId: widget.series.id,
      name: name.trim(),
    );
    await _load();
  }
}

class _CharacterCard extends StatefulWidget {
  const _CharacterCard({
    required this.character,
    required this.seriesId,
    required this.onChanged,
  });

  final CharacterCard character;
  final String seriesId;
  final VoidCallback onChanged;

  @override
  State<_CharacterCard> createState() => _CharacterCardState();
}

class _CharacterCardState extends State<_CharacterCard> {
  final _manager = StudioProjectManager.instance;
  bool _expanded = false;
  bool _translating = false;
  String? _translateError;

  late final TextEditingController _name;
  late final TextEditingController _descZh;
  late final TextEditingController _positive;
  late final TextEditingController _negative;
  late final TextEditingController _voice;

  @override
  void initState() {
    super.initState();
    _seriesId = widget.seriesId;
    _name = TextEditingController(text: widget.character.name);
    _descZh = TextEditingController(text: widget.character.descriptionZh);
    _positive = TextEditingController(
      text: widget.character.basePromptPositive,
    );
    _negative = TextEditingController(
      text: widget.character.basePromptNegative,
    );
    _voice = TextEditingController(text: widget.character.ttsVoiceId);
  }

  @override
  void dispose() {
    _name.dispose();
    _descZh.dispose();
    _positive.dispose();
    _negative.dispose();
    _voice.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final updated = widget.character.copyWith(
      name: _name.text.trim(),
      descriptionZh: _descZh.text,
      basePromptPositive: _positive.text.trim(),
      basePromptNegative: _negative.text.trim(),
      ttsVoiceId: _voice.text.trim(),
    );
    await _manager.saveCharacter(_seriesId, updated);
    widget.onChanged();
  }

  /// 由父级传入：角色卡自身不记录所属剧集（目录位置已经表达了）。
  late final String _seriesId;

  /// 整体替换形态列表。激活态只允许一个——两个形态同时激活时
  /// 「当前用哪张脸」是不确定的，而 Prompt 组装器会挑第一个。
  Future<void> _replaceVariations(List<CharacterVariation> next) async {
    final activeCount = next.where((v) => v.active).length;
    final normalized = activeCount > 1
        ? next.map((v) => v.active ? v.copyWith(active: false) : v).toList()
        : next;
    await _manager.saveCharacter(
      _seriesId,
      widget.character.copyWith(variations: normalized),
    );
    widget.onChanged();
  }

  Future<void> _generatePrompt() async {
    final desc = _descZh.text.trim();
    if (desc.isEmpty) return;
    setState(() {
      _translating = true;
      _translateError = null;
    });
    try {
      final result = await AiConstraintEngine.promptTranslation(
        descriptionZh: desc,
        productionType: 'drama',
      );
      if (!mounted) return;
      setState(() {
        _positive.text = result.data['prompt_positive'] as String? ?? '';
        _negative.text = result.data['prompt_negative'] as String? ?? '';
        _translating = false;
      });
    } on ConstraintParseError catch (e) {
      if (!mounted) return;
      setState(() {
        _translateError = '解析失败：${e.rawText}';
        _translating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _translateError = e.toString();
        _translating = false;
      });
    }
  }

  Future<void> _pickReference() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.single.path == null) return;
    final relative = await _manager.addCharacterReference(
      seriesId: _seriesId,
      characterId: widget.character.id,
      sourceFilePath: result.files.single.path!,
    );
    final updated = widget.character.copyWith(
      referenceImages: [...widget.character.referenceImages, relative],
    );
    await _manager.saveCharacter(_seriesId, updated);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            dense: true,
            title: Text(
              _name.text,
              style: TextStyle(color: context.textPrimary, fontSize: 14),
            ),
            subtitle: Text(
              '${widget.character.variations.length} 个形态',
              style: TextStyle(color: context.textTertiary, fontSize: 11),
            ),
            trailing: IconButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                color: context.textSecondary,
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  _Field(
                    controller: _name,
                    label: '角色名称',
                    onChanged: (_) => _save(),
                  ),
                  _Field(
                    controller: _descZh,
                    label: '中文外貌描述',
                    maxLines: 3,
                    onChanged: (_) => _save(),
                    trailing: _translating
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : TextButton.icon(
                            onPressed: _generatePrompt,
                            icon: const Icon(Icons.translate, size: 16),
                            label: const Text('生成 Prompt'),
                          ),
                  ),
                  if (_translateError != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _translateError!,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.errorText,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  _Field(
                    controller: _positive,
                    label: '英文正向 Prompt',
                    maxLines: 3,
                    onChanged: (_) => _save(),
                  ),
                  _Field(
                    controller: _negative,
                    label: '英文负向 Prompt',
                    maxLines: 2,
                    onChanged: (_) => _save(),
                  ),
                  _VoiceSelectorField(
                    controller: _voice,
                    label: 'TTS 音色',
                    onChanged: (_) => _save(),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickReference,
                        icon: const Icon(Icons.image_outlined, size: 16),
                        label: Text(
                          '基准参考图（${widget.character.referenceImages.length}）',
                        ),
                      ),
                    ],
                  ),
                  _VariationsSection(
                    variations: widget.character.variations,
                    onChange: _replaceVariations,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 形态版本列表（spec 9.6）：增删、改名、写差异词、切激活态。
///
/// 每个形态只存**相对**基础 Prompt 的差异词（spec: 角色资产卡与形态版本化），
/// 所以这里没有"完整 Prompt"输入框——只有正向/负向两栏增量。
class _VariationsSection extends StatelessWidget {
  const _VariationsSection({
    required this.variations,
    required this.onChange,
  });

  final List<CharacterVariation> variations;
  final ValueChanged<List<CharacterVariation>> onChange;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              '形态版本',
              style: TextStyle(
                color: context.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add, size: 15),
              label: const Text('新增形态'),
            ),
          ],
        ),
        Text(
          '差异词只写相对基础 Prompt 的增量，例如「战损」只需填破损与血迹。',
          style: TextStyle(color: context.textTertiary, fontSize: 11),
        ),
        const SizedBox(height: 8),
        if (variations.isEmpty)
          Text(
            '还没有形态。至少保留一个「默认」形态。',
            style: TextStyle(color: context.textTertiary, fontSize: 11),
          ),
        for (var i = 0; i < variations.length; i++)
          _VariationEditor(
            key: ValueKey(variations[i].id),
            variation: variations[i],
            canDelete: variations.length > 1,
            onChanged: (updated) => _update(i, updated),
            onDelete: () => _delete(i),
          ),
      ],
    );
  }

  void _add() {
    final now = DateTime.now().microsecondsSinceEpoch;
    onChange([
      ...variations,
      CharacterVariation(
        id: 'var_$now',
        name: '新形态 ${variations.length + 1}',
      ),
    ]);
  }

  void _update(int index, CharacterVariation updated) {
    final next = variations.toList();
    next[index] = updated;
    onChange(next);
  }

  void _delete(int index) {
    final next = variations.toList()..removeAt(index);
    onChange(next);
  }
}

class _VariationEditor extends StatefulWidget {
  const _VariationEditor({
    super.key,
    required this.variation,
    required this.canDelete,
    required this.onChanged,
    required this.onDelete,
  });

  final CharacterVariation variation;
  final bool canDelete;
  final ValueChanged<CharacterVariation> onChanged;
  final VoidCallback onDelete;

  @override
  State<_VariationEditor> createState() => _VariationEditorState();
}

class _VariationEditorState extends State<_VariationEditor> {
  late final TextEditingController _name;
  late final TextEditingController _positive;
  late final TextEditingController _negative;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.variation.name);
    _positive = TextEditingController(text: widget.variation.positiveDelta);
    _negative = TextEditingController(text: widget.variation.negativeDelta);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _positive.dispose();
    _negative.dispose();
    super.dispose();
  }

  /// 防抖保存：每敲一个字写一次盘太碎，而形态差异词常常是一整句。
  void _scheduleEmit() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _emit);
  }

  void _emit() {
    widget.onChanged(widget.variation.copyWith(
      name: _name.text.trim().isEmpty ? '未命名形态' : _name.text.trim(),
      positiveDelta: _positive.text.trim(),
      negativeDelta: _negative.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.bgInput,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(
          color: widget.variation.active
              ? context.accentText
              : context.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _name.text.isEmpty ? '未命名形态' : _name.text,
                  style: TextStyle(
                    color: widget.variation.active
                        ? context.accentText
                        : context.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text('激活', style: TextStyle(
                color: context.textTertiary, fontSize: 11)),
              Switch(
                value: widget.variation.active,
                onChanged: (v) =>
                    widget.onChanged(widget.variation.copyWith(active: v)),
              ),
              IconButton(
                onPressed: widget.canDelete ? widget.onDelete : null,
                icon: const Icon(Icons.delete_outline, size: 16),
                tooltip: '删除形态',
              ),
            ],
          ),
          TextField(
            controller: _name,
            onChanged: (_) => _scheduleEmit(),
            style: TextStyle(color: context.textPrimary, fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              labelText: '形态名称',
              labelStyle: TextStyle(color: context.textTertiary, fontSize: 11),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _positive,
            onChanged: (_) => _scheduleEmit(),
            maxLines: 2,
            style: TextStyle(color: context.textPrimary, fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              labelText: '正向差异词',
              hintText: '例如 torn clothes, bloodstain',
              labelStyle: TextStyle(color: context.textTertiary, fontSize: 11),
              hintStyle: TextStyle(color: context.textDisabled, fontSize: 10),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _negative,
            onChanged: (_) => _scheduleEmit(),
            maxLines: 2,
            style: TextStyle(color: context.textPrimary, fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              labelText: '负向差异词',
              hintText: '例如 clean, intact',
              labelStyle: TextStyle(color: context.textTertiary, fontSize: 11),
              hintStyle: TextStyle(color: context.textDisabled, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

/// 场景库。
/// 场景库。
class _ScenesTab extends StatefulWidget {
  const _ScenesTab({required this.series});

  final StudioSeries series;

  @override
  State<_ScenesTab> createState() => _ScenesTabState();
}

class _ScenesTabState extends State<_ScenesTab> {
  final _manager = StudioProjectManager.instance;
  List<SceneCard> _scenes = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _manager.listScenes(widget.series.id);
    if (!mounted) return;
    setState(() => _scenes = list);
  }

  void _openEditor(SceneCard scene) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => _SceneEditorSheet(
        series: widget.series,
        scene: scene,
        onSaved: _load,
        onDeleted: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Row(
            children: [
              Text(
                '场景库 (${_scenes.length})',
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Text('点击场景卡片可编辑提示词与垫图参考图', style: TextStyle(color: context.textTertiary, fontSize: 12)),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新建场景'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _scenes.isEmpty
              ? Center(
                  child: Text(
                    '还没有场景。点击右上角新建场景。',
                    style: TextStyle(color: context.textTertiary, fontSize: 13),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  itemCount: _scenes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final scene = _scenes[i];
                    return InkWell(
                      onTap: () => _openEditor(scene),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.bgCard,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: context.borderSubtle),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: context.accentSubtle,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: scene.referenceImages.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: Image.file(
                                        File(scene.referenceImages.first),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Icon(
                                          Icons.landscape_outlined,
                                          color: context.accentText,
                                          size: 20,
                                        ),
                                      ),
                                    )
                                  : Icon(
                                      Icons.landscape_outlined,
                                      color: context.accentText,
                                      size: 20,
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        scene.name,
                                        style: TextStyle(
                                          color: context.textPrimary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (scene.referenceImages.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Text(
                                          '${scene.referenceImages.length} 张参考图',
                                          style: TextStyle(color: context.textTertiary, fontSize: 11),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    scene.descriptionZh.isNotEmpty
                                        ? scene.descriptionZh
                                        : (scene.promptEn.isNotEmpty ? scene.promptEn : '暂无场景描述，点击编辑'),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: context.textSecondary, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => _openEditor(scene),
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              tooltip: '编辑场景',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _create() async {
    final name = await _promptName(context, '新建场景');
    if (name == null || name.trim().isEmpty) return;
    final created = await _manager.createScene(
      seriesId: widget.series.id,
      name: name.trim(),
    );
    await _load();
    if (mounted) _openEditor(created);
  }
}

class _SceneEditorSheet extends StatefulWidget {
  const _SceneEditorSheet({
    required this.series,
    required this.scene,
    required this.onSaved,
    required this.onDeleted,
  });

  final StudioSeries series;
  final SceneCard scene;
  final VoidCallback onSaved;
  final VoidCallback onDeleted;

  @override
  State<_SceneEditorSheet> createState() => _SceneEditorSheetState();
}

class _SceneEditorSheetState extends State<_SceneEditorSheet> {
  final _manager = StudioProjectManager.instance;
  late final TextEditingController _name;
  late final TextEditingController _descZh;
  late final TextEditingController _promptEn;
  late List<String> _refs;
  bool _translating = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.scene.name);
    _descZh = TextEditingController(text: widget.scene.descriptionZh);
    _promptEn = TextEditingController(text: widget.scene.promptEn);
    _refs = List.from(widget.scene.referenceImages);
  }

  @override
  void dispose() {
    _name.dispose();
    _descZh.dispose();
    _promptEn.dispose();
    super.dispose();
  }

  Future<void> _translatePrompt() async {
    final zh = _descZh.text.trim();
    if (zh.isEmpty) return;
    setState(() => _translating = true);
    try {
      final res = await AiConstraintEngine.promptTranslation(
        descriptionZh: zh,
        productionType: widget.series.productionType.name,
      );
      final positive = res.data['prompt_positive'] as String? ?? '';
      if (positive.isNotEmpty && mounted) {
        setState(() => _promptEn.text = positive);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成Prompt失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  Future<void> _pickRefImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;
    final paths = result.files.map((f) => f.path).whereType<String>().toList();
    setState(() => _refs.addAll(paths));
  }

  Future<void> _save() async {
    final updated = widget.scene.copyWith(
      name: _name.text.trim().isEmpty ? '未命名场景' : _name.text.trim(),
      descriptionZh: _descZh.text.trim(),
      promptEn: _promptEn.text.trim(),
      referenceImages: _refs,
    );
    await _manager.saveScene(widget.series.id, updated);
    widget.onSaved();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    await _manager.deleteScene(widget.series.id, widget.scene.id);
    widget.onDeleted();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '编辑场景资产',
                style: TextStyle(color: context.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _delete,
                style: TextButton.styleFrom(foregroundColor: context.errorText),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('删除场景'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save, size: 16),
                label: const Text('保存修改'),
              ),
              const SizedBox(width: 8),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
          const Divider(height: 20),
          Expanded(
            child: ListView(
              children: [
                TextField(
                  controller: _name,
                  style: TextStyle(color: context.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(labelText: '场景名称 (如: 总裁顶层办公室)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descZh,
                  maxLines: 3,
                  style: TextStyle(color: context.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: '中文环境与视觉描述',
                    hintText: '描述场景的光照、布局、色调与氛围',
                    suffixIcon: _translating
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : TextButton.icon(
                            onPressed: _translatePrompt,
                            icon: const Icon(Icons.translate, size: 15),
                            label: const Text('生成 Prompt'),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _promptEn,
                  maxLines: 3,
                  style: TextStyle(color: context.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: '英文生图 Prompt (注入分镜)',
                    hintText: 'e.g. luxury modern office, floor to ceiling windows, city skyline, night',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('参考图/垫图 (${_refs.length})', style: TextStyle(color: context.textPrimary, fontSize: 13)),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: _pickRefImage,
                      icon: const Icon(Icons.add_photo_alternate_outlined, size: 15),
                      label: const Text('添加参考图'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_refs.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (int i = 0; i < _refs.length; i++)
                        Stack(
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: context.borderSubtle),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.file(
                                  File(_refs[i]),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: InkWell(
                                onTap: () => setState(() => _refs.removeAt(i)),
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                                  child: const Icon(Icons.close, size: 12, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 世界观设定编辑。
class _WorldviewTab extends StatefulWidget {
  const _WorldviewTab({required this.series, required this.session});

  final StudioSeries series;
  final StudioSession session;

  @override
  State<_WorldviewTab> createState() => _WorldviewTabState();
}

class _WorldviewTabState extends State<_WorldviewTab> {
  final _manager = StudioProjectManager.instance;

  late final TextEditingController _worldview;
  late final TextEditingController _style;
  late final TextEditingController _voice;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _worldview = TextEditingController(text: widget.series.worldview);
    _style = TextEditingController(text: widget.series.styleTokens);
    _voice = TextEditingController(text: widget.series.defaultVoiceId);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _worldview.dispose();
    _style.dispose();
    _voice.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _save);
  }

  Future<void> _save() async {
    final updated = widget.series.copyWith(
      worldview: _worldview.text,
      styleTokens: _style.text,
      defaultVoiceId: _voice.text.trim(),
    );
    await _manager.saveSeries(updated);
    widget.session.select(updated);
  }

  void _applyStylePreset(String token) {
    final current = _style.text.trim();
    if (current.isEmpty) {
      _style.text = token;
    } else if (!current.contains(token)) {
      _style.text = '$current, $token';
    }
    _scheduleSave();
  }

  @override
  Widget build(BuildContext context) {
    const stylePresets = [
      (label: '电影质感', token: 'cinematic still, 35mm film, dramatic lighting, sharp focus'),
      (label: '8K超写实', token: 'photorealistic, 8k resolution, highly detailed, realistic skin texture'),
      (label: '日系动漫', token: 'anime style, Makoto Shinkai aesthetic, vibrant colors'),
      (label: '新国风水墨', token: 'traditional Chinese ink wash style, ethereal, elegant brush strokes'),
      (label: '赛博朋克', token: 'cyberpunk aesthetic, neon lighting, rainy reflections, futuristic cityscape'),
      (label: '胶片颗粒', token: 'vintage film grain, Kodak Portra 400, retro color palette'),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Field(
            controller: _worldview,
            label: '世界观设定',
            maxLines: 8,
            onChanged: (_) => _scheduleSave(),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('快捷风格标签: ', style: TextStyle(color: context.textTertiary, fontSize: 11)),
              const SizedBox(width: 4),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final p in stylePresets)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            padding: EdgeInsets.zero,
                            label: Text(p.label, style: const TextStyle(fontSize: 11)),
                            onPressed: () => _applyStylePreset(p.token),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _Field(
            controller: _style,
            label: '全局风格词（风格锁）',
            maxLines: 2,
            hint: '例如 cinematic still, film grain, teal and orange',
            onChanged: (_) => _scheduleSave(),
          ),
          _VoiceSelectorField(
            controller: _voice,
            label: '默认 TTS 音色 (优先系统 AI 音色)',
            onChanged: (_) => _scheduleSave(),
          ),
        ],
      ),
    );
  }
}

/// 集数列表 + 前情回顾。
class _EpisodesTab extends StatefulWidget {
  const _EpisodesTab({required this.series, required this.session});

  final StudioSeries series;
  final StudioSession session;

  @override
  State<_EpisodesTab> createState() => _EpisodesTabState();
}

class _EpisodesTabState extends State<_EpisodesTab> {
  final _manager = StudioProjectManager.instance;
  List<StudioEpisode> _episodes = const [];
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _manager.listEpisodes(widget.series.id);
    if (!mounted) return;
    setState(() => _episodes = list);
  }

  Future<void> _createEpisode() async {
    setState(() => _creating = true);
    try {
      final res = await _manager.createEpisode(seriesId: widget.series.id);
      await _load();
      widget.session.select(widget.series);
      widget.session.selectEpisode(res.episode);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已新建第 ${res.episode.index} 集: ${res.episode.title}')),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _deleteEpisode(StudioEpisode ep) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.bgCard,
        title: Text('删除第 ${ep.index} 集', style: TextStyle(color: context.textPrimary)),
        content: Text('确定删除《${ep.title}》吗？该集的所有分镜与素材都将被清理。', style: TextStyle(color: context.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: context.errorText),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _manager.deleteEpisode(widget.series.id, ep.id);
    if (widget.session.episode?.id == ep.id) {
      widget.session.selectEpisode(null);
    }
    await _load();
  }

  Future<void> _extractAiSummary(StudioEpisode ep) async {
    if (ep.shots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本集暂无分镜，无法提炼前情')),
      );
      return;
    }
    try {
      final res = await AiConstraintEngine.episodeSummary(
        synopsis: ep.synopsis,
        shotsSummary: ep.shots.map((s) => '${s.number}. ${s.actionZh}').join('\n'),
      );
      final summary = res.data['summary'] as String? ?? '';
      final hook = res.data['hook'] as String? ?? '';
      await _manager.upsertEpisodeMemory(
        seriesId: widget.series.id,
        episodeId: ep.id,
        title: ep.title,
        summary: summary,
        hook: hook,
        shotCount: ep.shots.length,
      );
      widget.session.select(_manager.readSeries(widget.series.id));
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('第 ${ep.index} 集前情摘要已提炼并更新')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI 提炼失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final memories = widget.session.series?.memories ??
        _manager.readSeries(widget.series.id)?.memories ??
        const [];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Text(
              '分集列表 (${_episodes.length} 集)',
              style: TextStyle(
                color: context.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _creating ? null : _createEpisode,
              icon: _creating
                  ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add, size: 16),
              label: Text(_creating ? '新建中…' : '新建第 ${_episodes.length + 1} 集'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_episodes.isEmpty)
          Text(
            '还没有分集。点击右上角新建第一集。',
            style: TextStyle(color: context.textTertiary, fontSize: 12),
          ),
        for (final ep in _episodes)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: widget.session.episode?.id == ep.id ? context.bgSelected : context.bgCard,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: widget.session.episode?.id == ep.id ? context.accentText : context.borderSubtle,
              ),
            ),
            child: ListTile(
              dense: true,
              selected: widget.session.episode?.id == ep.id,
              title: Text(
                '第 ${ep.index} 集: ${ep.title}',
                style: TextStyle(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                '${ep.shots.length} 个分镜 ${ep.synopsis.isNotEmpty ? '· ${ep.synopsis}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.textTertiary, fontSize: 11),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 16),
                    tooltip: '删除此集',
                    onPressed: () => _deleteEpisode(ep),
                  ),
                ],
              ),
              onTap: () => widget.session.selectEpisode(ep),
            ),
          ),
        const SizedBox(height: 24),
        Text(
          '各集前情回顾（跨集连续剧记忆库）',
          style: TextStyle(
            color: context.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '每一集落盘后自动提炼，也可在此手动编辑。后续集数生成分镜时将自动注入。',
          style: TextStyle(color: context.textTertiary, fontSize: 11),
        ),
        const SizedBox(height: 10),
        if (_episodes.isEmpty)
          Text(
            '创建分集后将在此按顺序展示各集剧情回顾。',
            style: TextStyle(color: context.textTertiary, fontSize: 12),
          )
        else
          for (final ep in _episodes) ...[
            _buildEpisodeMemoryItem(ep, memories.where((m) => m.episodeId == ep.id).firstOrNull),
          ],
      ],
    );
  }

  Widget _buildEpisodeMemoryItem(StudioEpisode ep, EpisodeMemory? memory) {
    if (memory != null) {
      return _MemoryEditor(seriesId: widget.series.id, memory: memory);
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('第 ${ep.index} 集: ${ep.title}', style: TextStyle(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text('暂无前情记忆。已有 ${ep.shots.length} 个分镜。', style: TextStyle(color: context.textTertiary, fontSize: 11)),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => _extractAiSummary(ep),
            icon: const Icon(Icons.auto_awesome, size: 14),
            label: const Text('AI 提炼前情', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _MemoryEditor extends StatefulWidget {
  const _MemoryEditor({required this.seriesId, required this.memory});

  final String seriesId;
  final EpisodeMemory memory;

  @override
  State<_MemoryEditor> createState() => _MemoryEditorState();
}

class _MemoryEditorState extends State<_MemoryEditor> {
  final _manager = StudioProjectManager.instance;
  late final TextEditingController _summary;
  late final TextEditingController _hook;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _summary = TextEditingController(text: widget.memory.summary);
    _hook = TextEditingController(text: widget.memory.hook);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _summary.dispose();
    _hook.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _save);
  }

  Future<void> _save() async {
    await _manager.upsertEpisodeMemory(
      seriesId: widget.seriesId,
      episodeId: widget.memory.episodeId,
      summary: _summary.text,
      hook: _hook.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.memory.title,
            style: TextStyle(color: context.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _summary,
            maxLines: 3,
            onChanged: (_) => _scheduleSave(),
            style: TextStyle(color: context.textPrimary, fontSize: 12),
            decoration: InputDecoration(
              labelText: '剧情摘要',
              labelStyle: TextStyle(color: context.textTertiary, fontSize: 11),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _hook,
            maxLines: 2,
            onChanged: (_) => _scheduleSave(),
            style: TextStyle(color: context.textPrimary, fontSize: 12),
            decoration: InputDecoration(
              labelText: '末尾钩子',
              labelStyle: TextStyle(color: context.textTertiary, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.hint,
    this.onChanged,
    this.trailing,
  });

  final TextEditingController controller;
  final String label;
  final int maxLines;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        onChanged: onChanged,
        style: TextStyle(color: context.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(color: context.textTertiary, fontSize: 12),
          hintStyle: TextStyle(color: context.textDisabled, fontSize: 11),
          suffixIcon: trailing,
        ),
      ),
    );
  }
}

Future<String?> _promptName(BuildContext context, String title) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: context.bgCard,
      title: Text(title, style: TextStyle(color: context.textPrimary)),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: TextStyle(color: context.textPrimary),
        decoration: InputDecoration(
          labelText: '名称',
          labelStyle: TextStyle(color: context.textSecondary),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('确定'),
        ),
      ],
    ),
  );
}

class _VoiceSelectorField extends StatefulWidget {
  const _VoiceSelectorField({
    required this.controller,
    required this.label,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onChanged;

  @override
  State<_VoiceSelectorField> createState() => _VoiceSelectorFieldState();
}

class _VoiceSelectorFieldState extends State<_VoiceSelectorField> {
  AudioPlayer? _player;
  bool _isPlaying = false;
  bool _isAuditioning = false;
  bool _customMode = false;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  List<TtsVoiceOption> _buildOptions() {
    final options = <TtsVoiceOption>[];
    final store = AiConfigStore.instance;
    final ttsBindings = store.slotBindings['tts'] ?? [];
    final providers = store.providers.where((p) => p.enabled).toList();

    for (final cand in ttsBindings) {
      final p = providers.cast<AiProviderConfig?>().firstWhere(
        (item) => item?.id == cand.providerId,
        orElse: () => null,
      );
      if (p != null) {
        for (final v in TtsVoiceOption.defaultOpenAiVoices) {
          options.add(TtsVoiceOption(
            id: v.id,
            name: '${p.name} · ${v.name}',
            language: v.language,
            gender: v.gender,
            mode: TtsMode.customAi,
            description: '系统 AI [${p.name}] 绑定音色',
          ));
        }
        break;
      }
    }
    options.addAll(TtsVoiceOption.defaultEdgeVoices);
    return options;
  }

  Future<void> _audition() async {
    if (_isAuditioning || _isPlaying) {
      await _player?.stop();
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _isAuditioning = false;
        });
      }
      return;
    }

    final voiceId = widget.controller.text.trim();
    final effectiveVoice = voiceId.isEmpty ? 'zh-CN-XiaoxiaoNeural' : voiceId;
    final isEdge = effectiveVoice.contains('Neural') ||
        effectiveVoice.startsWith('zh-') ||
        effectiveVoice.startsWith('en-');

    setState(() => _isAuditioning = true);
    try {
      final TtsEngine engine =
          isEdge ? EdgeTtsEngine() : TtsEngineFactory.createEngine(TtsMode.customAi);
      final config = TtsSynthesisConfig(
        mode: isEdge ? TtsMode.edge : TtsMode.customAi,
        voiceId: effectiveVoice,
        useSystemAiConfig: true,
      );
      final bytes = await engine.synthesize(
        '你好，这是当前选择的语音音色试听效果。',
        config,
      );
      if (!mounted) return;
      _player ??= AudioPlayer();
      _player!.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _isPlaying = false);
      });
      await _player!.play(BytesSource(bytes));
      if (mounted) {
        setState(() {
          _isAuditioning = false;
          _isPlaying = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAuditioning = false;
          _isPlaying = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('音色试听失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final options = _buildOptions();
    final currentText = widget.controller.text.trim();
    final isMatched = options.any((opt) => opt.id == currentText);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                widget.label,
                style: TextStyle(color: context.textTertiary, fontSize: 12),
              ),
              const Spacer(),
              InkWell(
                onTap: () {
                  setState(() => _customMode = !_customMode);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    _customMode ? '切换预设选择' : '自定义 ID',
                    style: TextStyle(
                      color: primaryColor,
                      fontSize: 11,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _customMode
                    ? TextField(
                        controller: widget.controller,
                        onChanged: widget.onChanged,
                        style: TextStyle(color: context.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: '输入音色标识，如 zh-CN-YunxiNeural 或 alloy',
                          hintStyle: TextStyle(color: context.textDisabled, fontSize: 11),
                          isDense: true,
                        ),
                      )
                    : DropdownButtonFormField<String>(
                        initialValue: isMatched ? currentText : (options.isNotEmpty ? options.first.id : null),
                        dropdownColor: context.bgCard,
                        style: TextStyle(color: context.textPrimary, fontSize: 12),
                        isExpanded: true,
                        decoration: const InputDecoration(isDense: true),
                        items: options.map((opt) {
                          final isSystem = opt.mode == TtsMode.customAi;
                          return DropdownMenuItem<String>(
                            value: opt.id,
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    color: isSystem
                                        ? primaryColor.withValues(alpha: 0.15)
                                        : context.borderSubtle,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    isSystem ? '系统AI' : 'Edge',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isSystem ? primaryColor : context.textTertiary,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    opt.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: context.textPrimary, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            widget.controller.text = val;
                            widget.onChanged?.call(val);
                          }
                        },
                      ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _audition,
                icon: _isAuditioning
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _isPlaying ? Icons.stop : Icons.volume_up_outlined,
                        size: 16,
                      ),
                label: Text(_isPlaying ? '停止' : '试听'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
