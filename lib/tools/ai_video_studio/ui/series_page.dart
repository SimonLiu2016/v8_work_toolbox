/// IP 主库页：角色卡、场景库、世界观设定、集数列表、前情回顾。
///
/// spec 9.4 / 9.5 / 9.6 / 9.7。这一页是「跨集一致性」的控制台——角色长相、
/// 场景、剧情记忆都在这里定，看板只消费不定义。
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart' hide AssetSource;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../services/ai_config_store.dart';
import '../../../theme/app_theme.dart';
import '../../ai_video_studio/models/studio_models.dart';
import '../../ai_video_studio/services/ai_constraint_engine.dart';
import '../../ai_video_studio/services/image_gen_adapter.dart';
import '../../ai_video_studio/services/prompt_assembler.dart';
import '../../ai_video_studio/services/spherical_perspective_slicer.dart';
import '../../ai_video_studio/services/studio_project_manager.dart';
import '../../ai_video_studio/services/video_task_ledger.dart';
import '../services/asset_library.dart';
import 'asset_picker_dialog.dart';
import 'face_crop_dialog.dart';
import 'image_dimension_selector.dart';
import 'panorama_3d_viewer_dialog.dart';
import 'studio_preset_management_dialog.dart';
import '../services/studio_preset_store.dart';
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
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
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
                2 => _PropsTab(series: series),
                3 => _WorldviewTab(series: series, session: widget.session),
                _ => _EpisodesTab(series: series, session: widget.session),
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildTabs(BuildContext context) {
    const labels = ['角色卡', '场景库', '道具', '世界观', '集数与前情'];
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
                    series: widget.series,
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
    required this.series,
    required this.onChanged,
  });

  final CharacterCard character;
  final StudioSeries series;
  final VoidCallback onChanged;

  @override
  State<_CharacterCard> createState() => _CharacterCardState();
}

class _CharacterCardState extends State<_CharacterCard> {
  final _manager = StudioProjectManager.instance;
  bool _expanded = false;
  bool _generatingTurnaround = false;
  String? _turnaroundError;
  StudioImageDimensionPreset _turnaroundDimension =
      StudioImageDimensionPreset.defaultCharacterTurnaround;

  late final TextEditingController _name;
  late final TextEditingController _descZh;
  late final TextEditingController _facialZh;
  late final TextEditingController _attireZh;
  late final TextEditingController _voice;

  @override
  void initState() {
    super.initState();
    _seriesId = widget.series.id;
    _name = TextEditingController(text: widget.character.name);
    _descZh = TextEditingController(text: widget.character.descriptionZh);
    _facialZh = TextEditingController(
      text: widget.character.facialFeaturesZh.isNotEmpty
          ? widget.character.facialFeaturesZh
          : widget.character.descriptionZh,
    );
    _attireZh = TextEditingController(text: widget.character.defaultAttireZh);
    _voice = TextEditingController(text: widget.character.ttsVoiceId);
  }

  @override
  void dispose() {
    _name.dispose();
    _descZh.dispose();
    _facialZh.dispose();
    _attireZh.dispose();
    _voice.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final combinedPos = [
      if (_facialZh.text.trim().isNotEmpty) _facialZh.text.trim(),
      if (_attireZh.text.trim().isNotEmpty) _attireZh.text.trim(),
    ].join('，');

    final updated = widget.character.copyWith(
      name: _name.text.trim(),
      descriptionZh: _descZh.text.trim().isNotEmpty ? _descZh.text : _facialZh.text,
      facialFeaturesZh: _facialZh.text.trim(),
      defaultAttireZh: _attireZh.text.trim(),
      basePromptPositive: combinedPos,
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
    final nextIds = next.map((v) => v.id).toSet();
    final dir = _manager.characterDir(_seriesId, widget.character.id);
    for (final oldVar in widget.character.variations) {
      if (!nextIds.contains(oldVar.id)) {
        final path = oldVar.turnaroundPath ?? 'turnaround_${oldVar.id}.png';
        final file = File(p.join(dir.path, path));
        try {
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
    }
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

  /// 生成角色三视图（支持标准成人比例与 Q版萌系比例）。
  Future<void> _generateTurnaround([
    CharacterTurnaroundProportion proportion = CharacterTurnaroundProportion.standard,
  ]) async {
    final facial = _facialZh.text.trim();
    final attire = _attireZh.text.trim();
    final desc = _descZh.text.trim();
    final name = _name.text.trim();

    final parts = [
      if (name.isNotEmpty) name,
      if (facial.isNotEmpty) facial,
      if (attire.isNotEmpty) attire,
    ];
    final effectivePositive = parts.isNotEmpty
        ? parts.join('，')
        : (desc.isNotEmpty ? desc : name);

    if (effectivePositive.isEmpty) {
      setState(() => _turnaroundError = '请先填写角色容貌体态或服装描述');
      return;
    }
    setState(() {
      _generatingTurnaround = true;
      _turnaroundError = null;
    });
    try {
      final dir = _manager.characterDir(_seriesId, widget.character.id);
      final filename = proportion.filename;
      final out = File(p.join(dir.path, filename));
      await dir.create(recursive: true);
      final era = VisualEraGenre.fromId(widget.series.eraGenre);
      await SystemAiImageAdapter().generate(ImageGenRequest(
        prompt: CharacterTurnaroundPrompt.build(
          effectivePositive,
          styleTokens: widget.series.styleTokens,
          eraGenre: era,
          proportion: proportion,
          descriptionZh: facial.isNotEmpty ? facial : desc,
          fullDescriptionZh: desc,
        ),
        negativePrompt: CharacterTurnaroundPrompt.buildNegative(
          eraGenre: era,
          proportion: proportion,
          descriptionZh: facial.isNotEmpty ? facial : desc,
          positiveText: effectivePositive,
          styleNegativeBan: widget.series.negativeStyleTokens,
        ),
        shotNumber: 0,
        outputFile: out,
        width: _turnaroundDimension.width,
        height: _turnaroundDimension.height,
        referenceImages: const [], // 基准三视图恒以纯文本生图模式执行，阻断历史参考图或旧背景图的构图保留污染
      ));
      try {
        await FileImage(out).evict();
      } catch (_) {}

      final nextRefs = widget.character.referenceImages.contains(filename)
          ? widget.character.referenceImages
          : [...widget.character.referenceImages, filename];
      final updated = widget.character.copyWith(referenceImages: nextRefs);
      await _manager.saveCharacter(_seriesId, updated);
      widget.onChanged();
      if (!mounted) return;
      setState(() {
        _generatingTurnaround = false;
        _turnaroundError = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${proportion.labelZh}角色资产图已生成')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generatingTurnaround = false;
        _turnaroundError = e.toString();
      });
    }
  }

  /// 从当前角色的已有三视图打开交互式面部特写裁切弹窗。
  Future<void> _cropFaceAnchorFromTurnaround() async {
    final dir = _manager.characterDir(_seriesId, widget.character.id);
    final turnaroundFile = File(p.join(dir.path, 'turnaround.png'));
    if (!await turnaroundFile.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('尚未生成三视图，请先点击「生成三视图」或上传参考图')),
      );
      return;
    }
    await _cropFaceAnchorFromTurnaroundFile(turnaroundFile);
  }

  /// 使用指定的图片文件打开交互式面部特写裁切弹窗并保存。
  Future<void> _cropFaceAnchorFromTurnaroundFile(File imageFile) async {
    final cropped = await FaceCropDialog.show(
      context,
      imageFile: imageFile,
      title: '从三视图截取面部特写锚点',
    );
    if (cropped != null) {
      final saved = await _manager.saveFaceAnchorImage(
        seriesId: _seriesId,
        characterId: widget.character.id,
        faceImage: cropped,
      );
      if (saved != null) {
        widget.onChanged();
        if (!mounted) return;
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('面部特写锚点已成功截取并保存')),
        );
      }
    }
  }

  /// 用户从本地文件选取一张图片并裁切为 1:1 面部特写锚点。
  Future<void> _pickFaceAnchor() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
    );
    if (result == null || result.files.single.path == null) return;
    final file = File(result.files.single.path!);
    if (!mounted) return;
    final cropped = await FaceCropDialog.show(
      context,
      imageFile: file,
      title: '裁切外部图片为 1:1 面部特写锚点',
    );
    if (cropped != null) {
      final saved = await _manager.saveFaceAnchorImage(
        seriesId: _seriesId,
        characterId: widget.character.id,
        faceImage: cropped,
      );
      if (saved != null) {
        widget.onChanged();
        if (!mounted) return;
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('面部特写头像已保存')),
        );
      }
    }
  }

  /// 一键为当前角色创建「Q版纸人/化身」形态。
  Future<void> _addChibiVariation() async {
    final exists = widget.character.variations.any((v) =>
        v.name.contains('Q版') || v.name.contains('纸人'));
    if (exists) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已存在 Q 版相关形态')),
      );
      return;
    }
    final newVariation = CharacterVariation(
      id: 'var_chibi_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Q版化身/纸人',
      positiveDelta:
          'Q版二头身动漫风格，可爱黏土手办质感，二头身大头娃娃，圆脸大眼睛萌态',
      negativeDelta: '真实写实成人比例，高挑修长身形，八头身',
      active: false,
    );
    await _replaceVariations([...widget.character.variations, newVariation]);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已创建「Q版化身/纸人」形态，可在分镜制作中一键选用')),
    );
  }

  /// 把三视图收进资产库，归类为角色参考图。
  Future<void> _collectTurnaroundToAssets([
    CharacterTurnaroundProportion? targetProportion,
  ]) async {
    final dir = _manager.characterDir(_seriesId, widget.character.id);
    final stdFile = File(p.join(dir.path, 'turnaround.png'));
    final chibiFile = File(p.join(dir.path, 'turnaround_chibi.png'));
    final hasStd = await stdFile.exists();
    final hasChibi = await chibiFile.exists();

    if (!hasStd && !hasChibi) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('三视图文件缺失，请先生成')),
      );
      return;
    }

    if (targetProportion == null && hasStd && hasChibi) {
      if (!mounted) return;
      final selected = await showDialog<CharacterTurnaroundProportion>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('选择收进资产库的三视图'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, CharacterTurnaroundProportion.standard),
              child: const Text('● 标准比例三视图 (7~8头身)'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, CharacterTurnaroundProportion.chibi),
              child: const Text('○ Q版萌系三视图 (2.5头身)'),
            ),
          ],
        ),
      );
      if (selected == null) return;
      return _collectTurnaroundToAssets(selected);
    }

    final proportion = targetProportion ??
        (hasChibi && !hasStd
            ? CharacterTurnaroundProportion.chibi
            : CharacterTurnaroundProportion.standard);
    final file = proportion == CharacterTurnaroundProportion.chibi ? chibiFile : stdFile;
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${proportion.labelZh}三视图文件缺失，请重新生成')),
      );
      return;
    }
    try {
      final call = await VideoTaskLedger.instance.findByTargetPath(file.path);
      final era = VisualEraGenre.fromId(widget.series.eraGenre);
      final facial = _facialZh.text.trim();
      final attire = _attireZh.text.trim();
      final effectivePositive = [
        if (_name.text.trim().isNotEmpty) _name.text.trim(),
        if (facial.isNotEmpty) facial,
        if (attire.isNotEmpty) attire,
      ].join('，');
      await AssetLibrary.instance.addAsset(
        file,
        kind: AssetKind.image,
        source: AssetSource.remote,
        prompt: CharacterTurnaroundPrompt.build(
          effectivePositive.isNotEmpty ? effectivePositive : widget.character.name,
          styleTokens: widget.series.styleTokens,
          eraGenre: era,
          proportion: proportion,
          descriptionZh: facial.isNotEmpty ? facial : _descZh.text.trim(),
          fullDescriptionZh: _descZh.text.trim(),
        ),
        sourceCallId: call?.localId,
        originPath: file.path,
        category: AssetCategory.character,
        tags: [
          widget.character.name,
          '三视图',
          proportion.labelZh,
          if (era != null) era.labelZh,
        ],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${proportion.labelZh}三视图已收进资产库')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('收进资产库失败: $e')),
      );
    }
  }

  /// 从资产库选一张图当角色参考图。
  ///
  /// **复制进角色目录**，不引用资产库原文件（design 决策 1）：卡片持有副本，
  /// 之后删资产、删剧集互不影响。走 [_manager.addCharacterReference] 与手工
  /// 选文件同一条落盘路径，避免两套写入逻辑漂移。
  Future<void> _pickReferenceFromAssets() async {
    final asset = await AssetPickerDialog.show(
      context,
      kind: AssetKind.image,
      title: '选择角色参考图',
    );
    if (asset == null) return;
    if (!await asset.file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该资产文件已丢失')),
      );
      return;
    }
    final relative = await _manager.addCharacterReference(
      seriesId: _seriesId,
      characterId: widget.character.id,
      sourceFilePath: asset.path,
    );
    final updated = widget.character.copyWith(
      referenceImages: [...widget.character.referenceImages, relative],
    );
    await _manager.saveCharacter(_seriesId, updated);
    widget.onChanged();
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _Field(
                          controller: _facialZh,
                          label: '容貌体态描述 (中文面相/发型/体态)',
                          hint: '例：面如冠玉的俊美青年，剑眉入鬓，凤眼薄唇，墨发高束',
                          maxLines: 3,
                          onChanged: (_) => _save(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Field(
                          controller: _attireZh,
                          label: '默认服装装束 (中文衣着/袍服/佩饰)',
                          hint: '例：内着深青色劲装，外罩玄色巡城司狱卒袍服，腰束黑色板带',
                          maxLines: 3,
                          onChanged: (_) => _save(),
                        ),
                      ),
                    ],
                  ),
                  _VoiceSelectorField(
                    controller: _voice,
                    label: 'TTS 音色',
                    onChanged: (_) => _save(),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickReference,
                        icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
                        label: const Text('添加参考图'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _pickReferenceFromAssets,
                        icon: const Icon(Icons.photo_library_outlined, size: 16),
                        label: const Text('从资产库选择'),
                      ),
                      ImageDimensionSelector(
                        selectedPreset: _turnaroundDimension,
                        compact: true,
                        enabled: !_generatingTurnaround,
                        onChanged: (p) => setState(() => _turnaroundDimension = p),
                      ),
                      PopupMenuButton<CharacterTurnaroundProportion>(
                        tooltip: '选择三视图体态比例',
                        enabled: !_generatingTurnaround,
                        onSelected: (p) => _generateTurnaround(p),
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: CharacterTurnaroundProportion.standard,
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.accessibility_new, size: 18),
                              title: Text('标准比例 (7~8头身，默认)'),
                              subtitle: Text('成人修长身形，严格禁绝 Q 版大头', style: TextStyle(fontSize: 11)),
                            ),
                          ),
                          const PopupMenuItem(
                            value: CharacterTurnaroundProportion.chibi,
                            child: ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.face_retouching_natural, size: 18, color: Colors.pinkAccent),
                              title: Text('Q版萌系 (2.5头身)'),
                              subtitle: Text('大头小身，适用于纸人化身与内心戏', style: TextStyle(fontSize: 11)),
                            ),
                          ),
                        ],
                        child: IgnorePointer(
                          child: OutlinedButton.icon(
                            onPressed: () {},
                            icon: _generatingTurnaround
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.autofps_select, size: 16),
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_generatingTurnaround ? '三视图生成中…' : '生成三视图'),
                                const SizedBox(width: 2),
                                const Icon(Icons.arrow_drop_down, size: 16),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Builder(builder: (context) {
                        final charDir = _manager.characterDir(_seriesId, widget.character.id);
                        final hasTurnaround = File(p.join(charDir.path, 'turnaround.png')).existsSync();
                        return OutlinedButton.icon(
                          onPressed: hasTurnaround ? _cropFaceAnchorFromTurnaround : null,
                          icon: Icon(Icons.crop, size: 16, color: hasTurnaround ? Colors.amber : null),
                          label: const Text('从三视图截取面部'),
                        );
                      }),
                      OutlinedButton.icon(
                        onPressed: _pickFaceAnchor,
                        icon: const Icon(Icons.upload_file, size: 16),
                        label: const Text('更换面部头像'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _collectTurnaroundToAssets,
                        icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                        label: const Text('三视图入库'),
                      ),
                    ],
                  ),
                  Builder(builder: (context) {
                    final anchorName = widget.character.faceAnchorPath ?? 'face_anchor.png';
                    final dir = _manager.characterDir(_seriesId, widget.character.id);
                    final faceFile = File(p.join(dir.path, anchorName));
                    final hasAnchor = faceFile.existsSync();
                    if (!hasAnchor && widget.character.referenceImages.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (hasAnchor)
                              Stack(
                                children: [
                                  Tooltip(
                                    message: '面部特写锚点 (Face Anchor)\n生成形态三视图时专用参考图，彻底阻断原服装深色污染',
                                    child: InkWell(
                                      onTap: () => ImagePreviewDialog.show(
                                        context,
                                        file: faceFile,
                                        title: '面部特写锚点 - ${widget.character.name}',
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                      child: Container(
                                        width: 72,
                                        height: 72,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: Colors.amber,
                                            width: 2.0,
                                          ),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(4),
                                          child: Image.file(
                                            faceFile,
                                            key: ValueKey('${faceFile.path}_${faceFile.lastModifiedSync().millisecondsSinceEpoch}'),
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => const Center(
                                              child: Icon(Icons.face, size: 24, color: Colors.amber),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 2,
                                    left: 2,
                                    right: 2,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.shade800.withAlpha(220),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      child: const Text(
                                        '面部锚点',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 2,
                                    right: 2,
                                    child: InkWell(
                                      onTap: () async {
                                        final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text('删除面部特写锚点'),
                                            content: const Text(
                                              '确定删除该角色的面部特写锚点吗？\n删除后生成子形态将不再以该脸模为图生图参考。',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(ctx, false),
                                                child: const Text('取消'),
                                              ),
                                              FilledButton(
                                                onPressed: () => Navigator.pop(ctx, true),
                                                style: FilledButton.styleFrom(
                                                  backgroundColor: context.errorSolid,
                                                ),
                                                child: const Text('删除'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (ok == true) {
                                          await _manager.deleteFaceAnchor(
                                            seriesId: _seriesId,
                                            characterId: widget.character.id,
                                          );
                                          widget.onChanged();
                                          if (mounted) setState(() {});
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: const BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.close, size: 12, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            for (int i = 0; i < widget.character.referenceImages.length; i++)
                          Builder(builder: (context) {
                            final refName = widget.character.referenceImages[i];
                            final isTurnaround = refName == 'turnaround.png' || refName.contains('turnaround');
                            final isChibi = refName.contains('chibi');
                            final dir = _manager.characterDir(_seriesId, widget.character.id);
                            final file = File(p.join(dir.path, refName));
                            return Stack(
                              children: [
                                Tooltip(
                                  message: isChibi
                                      ? '点击查看Q版三视图大图'
                                      : (isTurnaround ? '点击查看三视图大图' : '点击查看参考图大图'),
                                  child: InkWell(
                                    onTap: () => ImagePreviewDialog.show(
                                      context,
                                      file: file,
                                      title: isChibi
                                          ? 'Q版三视图 - ${widget.character.name}'
                                          : (isTurnaround ? '标准三视图 - ${widget.character.name}' : '参考图 - ${widget.character.name}'),
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      width: 72,
                                      height: 72,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: isChibi
                                              ? Colors.pinkAccent
                                              : (isTurnaround ? context.accentText : context.borderSubtle),
                                          width: isTurnaround ? 1.5 : 1.0,
                                        ),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: Image.file(
                                          file,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => const Center(
                                            child: Icon(Icons.broken_image, size: 20),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (isTurnaround)
                                  Positioned(
                                    bottom: 2,
                                    left: 2,
                                    right: 2,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 1),
                                      decoration: BoxDecoration(
                                        color: isChibi
                                            ? Colors.pinkAccent.withAlpha(220)
                                            : context.accentText.withAlpha(220),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      child: Text(
                                        isChibi ? 'Q版三视' : '三视图',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  top: 2,
                                  right: 2,
                                  child: InkWell(
                                    onTap: () async {
                                      final ok = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('删除参考图'),
                                          content: Text('确定删除该参考图 ($refName) 吗？此操作无法撤销。'),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(ctx, false),
                                              child: const Text('取消'),
                                            ),
                                            FilledButton(
                                              onPressed: () => Navigator.pop(ctx, true),
                                              child: const Text('删除'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (ok != true) return;
                                      final nextRefs = List<String>.from(widget.character.referenceImages)..removeAt(i);
                                      try {
                                        if (await file.exists()) {
                                          await file.delete();
                                        }
                                      } catch (_) {}
                                      final updated = widget.character.copyWith(referenceImages: nextRefs);
                                      await _manager.saveCharacter(_seriesId, updated);
                                      widget.onChanged();
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.close, size: 12, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                              );
                            }),
                        ],
                      ),
                    ],
                  );
                }),
                  if (_turnaroundError != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '三视图生成失败：$_turnaroundError',
                          style: TextStyle(
                            color: context.errorText,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  if (widget.character.referenceImages.any((r) => r.contains('chibi')) &&
                      !widget.character.variations.any((v) => v.name.contains('Q版') || v.name.contains('纸人'))) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _addChibiVariation(),
                        icon: const Icon(Icons.auto_fix_high, size: 16, color: Colors.pinkAccent),
                        label: const Text('已检测到Q版三视图，点击一键转为「Q版化身/纸人」形态'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.pinkAccent,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ],
                  _VariationsSection(
                    seriesId: _seriesId,
                    series: widget.series,
                    character: widget.character,
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

/// 形态版本列表（spec 9.6）：增删、改名、写差异词、切激活态、专属三视图。
///
/// 每个形态只存**相对**基础 Prompt 的差异词（spec: 角色资产卡与形态版本化），
/// 支持独立三视图生成（以默认三视图为参考底图继承脸模）。
class _VariationsSection extends StatelessWidget {
  const _VariationsSection({
    required this.seriesId,
    required this.series,
    required this.character,
    required this.variations,
    required this.onChange,
  });

  final String seriesId;
  final StudioSeries series;
  final CharacterCard character;
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
          '差异词只写相对基础 Prompt 的增量，每个形态均可生成专属三视图（自动继承默认脸模）。',
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
            seriesId: seriesId,
            series: series,
            character: character,
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
    required this.seriesId,
    required this.series,
    required this.character,
    required this.variation,
    required this.canDelete,
    required this.onChanged,
    required this.onDelete,
  });

  final String seriesId;
  final StudioSeries series;
  final CharacterCard character;
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
  bool _generating = false;
  String? _error;
  bool _inheritBaseFace = true;
  StudioImageDimensionPreset _variationDimension =
      StudioImageDimensionPreset.defaultCharacterTurnaround;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.variation.name);
    _positive = TextEditingController(
      text: widget.variation.effectiveAttirePrompt,
    );
    _negative = TextEditingController(text: widget.variation.negativeDelta);
  }

  @override
  void didUpdateWidget(covariant _VariationEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.variation.name != widget.variation.name &&
        _name.text != widget.variation.name) {
      _name.text = widget.variation.name;
    }
    final nextAttire = widget.variation.effectiveAttirePrompt;
    if (oldWidget.variation.effectiveAttirePrompt != nextAttire &&
        _positive.text != nextAttire) {
      _positive.text = nextAttire;
    }
    if (oldWidget.variation.negativeDelta != widget.variation.negativeDelta &&
        _negative.text != widget.variation.negativeDelta) {
      _negative.text = widget.variation.negativeDelta;
    }
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
      attirePrompt: _positive.text.trim(),
      positiveDelta: _positive.text.trim(),
      negativeDelta: _negative.text.trim(),
    ));
  }

  File? _findTurnaroundFile() {
    final dir = StudioProjectManager.instance
        .characterDir(widget.seriesId, widget.character.id);
    if (widget.variation.turnaroundPath != null &&
        widget.variation.turnaroundPath!.isNotEmpty) {
      final f = File(p.join(dir.path, widget.variation.turnaroundPath!));
      if (f.existsSync()) return f;
    }
    final defaultStd =
        File(p.join(dir.path, 'turnaround_${widget.variation.id}.png'));
    if (defaultStd.existsSync()) return defaultStd;
    final defaultChibi =
        File(p.join(dir.path, 'turnaround_${widget.variation.id}_chibi.png'));
    if (defaultChibi.existsSync()) return defaultChibi;
    return null;
  }

  Future<void> _generateVariationTurnaround(
    CharacterTurnaroundProportion proportion,
  ) async {
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final dir = StudioProjectManager.instance
          .characterDir(widget.seriesId, widget.character.id);
      await dir.create(recursive: true);
      final filename = proportion == CharacterTurnaroundProportion.chibi
          ? 'turnaround_${widget.variation.id}_chibi.png'
          : 'turnaround_${widget.variation.id}.png';
      final outFile = File(p.join(dir.path, filename));

      // 提取面部特写锚点 (Face Anchor) 作为脸模一致性参考，彻底阻断原服装深色外溢
      final anchorName = widget.character.faceAnchorPath ?? 'face_anchor.png';
      final faceAnchor = File(p.join(dir.path, anchorName));
      final baseTurnaround = File(p.join(dir.path, 'turnaround.png'));
      final List<String> refImages = [];
      if (_inheritBaseFace) {
        if (await faceAnchor.exists()) {
          refImages.add(faceAnchor.path);
        } else if (await baseTurnaround.exists()) {
          refImages.add(baseTurnaround.path);
        } else if (widget.character.referenceImages.isNotEmpty) {
          final firstRef =
              File(p.join(dir.path, widget.character.referenceImages.first));
          if (await firstRef.exists()) {
            refImages.add(firstRef.path);
          }
        }
      }

      final era = VisualEraGenre.fromId(widget.series.eraGenre);
      final prompt = CharacterTurnaroundPrompt.buildForVariation(
        character: widget.character,
        variation: widget.variation,
        styleTokens: widget.series.styleTokens,
        eraGenre: era,
        proportion: proportion,
        inheritBaseFace: _inheritBaseFace,
      );
      final negative = CharacterTurnaroundPrompt.buildNegativeForVariation(
        character: widget.character,
        variation: widget.variation,
        eraGenre: era,
        proportion: proportion,
        styleNegativeBan: widget.series.negativeStyleTokens,
      );

      await SystemAiImageAdapter().generate(ImageGenRequest(
        prompt: prompt,
        negativePrompt: negative,
        shotNumber: 0,
        outputFile: outFile,
        width: _variationDimension.width,
        height: _variationDimension.height,
        referenceImages: refImages,
      ));

      try {
        await FileImage(outFile).evict();
      } catch (_) {}

      final updated = widget.variation.copyWith(turnaroundPath: filename);
      widget.onChanged(updated);

      if (!mounted) return;
      setState(() {
        _generating = false;
        _error = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('「${widget.variation.name}」三视图已生成')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _collectToAssets(File file) async {
    try {
      final call = await VideoTaskLedger.instance.findByTargetPath(file.path);
      final era = VisualEraGenre.fromId(widget.series.eraGenre);
      final isChibi =
          file.path.contains('chibi') || widget.variation.name.contains('Q版');
      final proportion = isChibi
          ? CharacterTurnaroundProportion.chibi
          : CharacterTurnaroundProportion.standard;
      await AssetLibrary.instance.addAsset(
        file,
        kind: AssetKind.image,
        source: AssetSource.remote,
        prompt: CharacterTurnaroundPrompt.buildForVariation(
          character: widget.character,
          variation: widget.variation,
          styleTokens: widget.series.styleTokens,
          eraGenre: era,
          proportion: proportion,
        ),
        sourceCallId: call?.localId,
        originPath: file.path,
        category: AssetCategory.character,
        tags: [
          widget.character.name,
          widget.variation.name,
          '三视图',
          proportion.labelZh,
          if (era != null) era.labelZh,
        ],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('「${widget.variation.name}」三视图已收进资产库')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('收进资产库失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final charDir = StudioProjectManager.instance
        .characterDir(widget.seriesId, widget.character.id);
    final anchorName = widget.character.faceAnchorPath ?? 'face_anchor.png';
    final hasFaceAnchor = File(p.join(charDir.path, anchorName)).existsSync();

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
              Text('激活',
                  style: TextStyle(color: context.textTertiary, fontSize: 11)),
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
              labelText: '形态服装/正向差异词 (全量置换默认服饰)',
              hintText: '例：“一袭素雪白衣”、“金丝龙纹暗金铠甲”',
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
              labelText: '负向差异词 (自动注入色彩对冲防溢出)',
              hintText: '例：“长胡须”、“黑袍” (若形态为白衣，系统自动在负向排除深色黑袍)',
              labelStyle: TextStyle(color: context.textTertiary, fontSize: 11),
              hintStyle: TextStyle(color: context.textDisabled, fontSize: 10),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              SizedBox(
                height: 22,
                width: 22,
                child: Checkbox(
                  value: _inheritBaseFace,
                  onChanged: (v) =>
                      setState(() => _inheritBaseFace = v ?? true),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Tooltip(
                  message: hasFaceAnchor
                      ? '已绑定面部特写锚点 (Face Anchor)：仅参考纯脸模生成，彻底置换原服装并阻断深色外溢'
                      : '开启时继承脸模底图；若基准图面部有误可取消勾选纯依文字重新生成',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '继承脸模参考图',
                        style: TextStyle(
                          fontSize: 11,
                          color: _inheritBaseFace
                              ? context.textSecondary
                              : Colors.amber,
                        ),
                      ),
                      if (hasFaceAnchor) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.amber.withAlpha(30),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.amber.withAlpha(120)),
                          ),
                          child: const Text(
                            '纯脸模锚点 · 阻断深色外溢',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.amber,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Builder(builder: (ctx) {
            final file = _findTurnaroundFile();
            if (file != null) {
              final filename = p.basename(file.path);
              final isChibi = filename.contains('chibi') ||
                  widget.variation.name.contains('Q版');
              return Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: context.bgWindow.withAlpha(120),
                  borderRadius: AppTheme.borderRadiusSmall,
                  border: Border.all(
                    color: isChibi
                        ? Colors.pinkAccent.withAlpha(100)
                        : context.borderSubtle,
                  ),
                ),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        Tooltip(
                          message: isChibi ? '点击查看Q版三视图大图' : '点击查看形态三视图大图',
                          child: InkWell(
                            onTap: () => ImagePreviewDialog.show(
                              context,
                              file: file,
                              title:
                                  '${widget.character.name}（${widget.variation.name}）三视图',
                            ),
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isChibi
                                      ? Colors.pinkAccent
                                      : context.accentText,
                                  width: 1.5,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.file(
                                  file,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Center(
                                    child: Icon(Icons.broken_image, size: 18),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 2,
                          left: 2,
                          right: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            decoration: BoxDecoration(
                              color: isChibi
                                  ? Colors.pinkAccent.withAlpha(220)
                                  : context.accentText.withAlpha(220),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              isChibi ? 'Q版三视' : '形态三视',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isChibi ? '已拥有专属Q版三视图' : '已拥有专属形态三视图',
                            style: TextStyle(
                              color: context.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '分镜选用此形态时自动路由此图',
                            style: TextStyle(
                              color: context.textTertiary,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => _collectToAssets(file),
                                icon: const Icon(Icons.bookmark_add_outlined,
                                    size: 13),
                                label: const Text('入库',
                                    style: TextStyle(fontSize: 11)),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 0),
                                ),
                              ),
                              ImageDimensionSelector(
                                selectedPreset: _variationDimension,
                                compact: true,
                                enabled: !_generating,
                                onChanged: (p) => setState(() => _variationDimension = p),
                              ),
                              PopupMenuButton<CharacterTurnaroundProportion>(
                                tooltip: '重新生成该形态三视图',
                                enabled: !_generating,
                                onSelected: (p) =>
                                    _generateVariationTurnaround(p),
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value:
                                        CharacterTurnaroundProportion.standard,
                                    child: ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      leading: Icon(Icons.accessibility_new,
                                          size: 18),
                                      title: Text('标准比例 (7~8头身，默认)'),
                                      subtitle: Text('继承角色基准脸模，装配形态差异词',
                                          style: TextStyle(fontSize: 11)),
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: CharacterTurnaroundProportion.chibi,
                                    child: ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      leading: Icon(
                                          Icons.face_retouching_natural,
                                          size: 18,
                                          color: Colors.pinkAccent),
                                      title: Text('Q版萌系 (2.5头身)'),
                                      subtitle: Text('大头小身，适用于纸人化身与内心戏',
                                          style: TextStyle(fontSize: 11)),
                                    ),
                                  ),
                                ],
                                child: IgnorePointer(
                                  child: OutlinedButton.icon(
                                    onPressed: () {},
                                    icon: _generating
                                        ? const SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2))
                                        : const Icon(Icons.refresh, size: 13),
                                    label: Text(_generating ? '生成中…' : '重绘',
                                        style: const TextStyle(fontSize: 11)),
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 0),
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () async {
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('删除形态三视图'),
                                      content: Text(
                                          '确定删除「${widget.variation.name}」的三视图吗？'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: const Text('取消'),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          child: const Text('删除'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (ok != true) return;
                                  try {
                                    if (await file.exists()) {
                                      await file.delete();
                                    }
                                  } catch (_) {}
                                  widget.onChanged(widget.variation.copyWith(
                                    turnaroundPath: null,
                                    clearTurnaroundPath: true,
                                  ));
                                },
                                icon: const Icon(Icons.delete_outline, size: 14),
                                tooltip: '删除三视图',
                                visualDensity: VisualDensity.compact,
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
            return Row(
              children: [
                ImageDimensionSelector(
                  selectedPreset: _variationDimension,
                  compact: true,
                  enabled: !_generating,
                  onChanged: (p) => setState(() => _variationDimension = p),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<CharacterTurnaroundProportion>(
                  tooltip: '选择体态比例并生成该形态三视图',
                  enabled: !_generating,
                  onSelected: (p) => _generateVariationTurnaround(p),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: CharacterTurnaroundProportion.standard,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.accessibility_new, size: 18),
                        title: Text('标准比例 (7~8头身，默认)'),
                        subtitle: Text('以默认三视图为参考底图，继承五官脸模并装配差异词',
                            style: TextStyle(fontSize: 11)),
                      ),
                    ),
                    const PopupMenuItem(
                      value: CharacterTurnaroundProportion.chibi,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.face_retouching_natural,
                            size: 18, color: Colors.pinkAccent),
                        title: Text('Q版萌系 (2.5头身)'),
                        subtitle: Text('大头小身，适用于纸人化身与内心戏',
                            style: TextStyle(fontSize: 11)),
                      ),
                    ),
                  ],
                  child: IgnorePointer(
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: _generating
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.auto_awesome, size: 14),
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_generating ? '形态三视图生成中…' : '生成该形态专属三视图',
                              style: const TextStyle(fontSize: 12)),
                          const SizedBox(width: 2),
                          const Icon(Icons.arrow_drop_down, size: 16),
                        ],
                      ),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '三视图生成失败：$_error',
                style: TextStyle(color: context.errorText, fontSize: 11),
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

  bool _batchDeconstructing = false;
  String _batchProgress = '';

  Future<void> _batchDeconstructAllScenes() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('一键全息解构全部场景'),
        content: Text(
          '将调用 AI 空间约束引擎，结合当前剧集世界观（${widget.series.eraGenre.isNotEmpty ? widget.series.eraGenre : "通用"}），为当前全部 ${_scenes.length} 个场景自动推导补全 7 个方位的纯净空间环境描述与生图 Prompt。\n\n本操作仅生成文字描述与提示词，不会消耗生图配额。是否继续？',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('开始解构')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() {
      _batchDeconstructing = true;
      _batchProgress = '准备中…';
    });

    try {
      final count = await _manager.deconstructAllScenesSpatialProfiles(
        widget.series.id,
        overwriteExisting: false,
        onProgress: (cur, tot, sName) {
          if (mounted) {
            setState(() {
              _batchProgress = '$cur/$tot $sName';
            });
          }
        },
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('全息解构完成，已为 $count 个场景建立 7 方位空间档案')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('全息解构失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _batchDeconstructing = false;
          _batchProgress = '';
        });
      }
    }
  }

  void _openEditor(SceneCard scene) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: math.min(1200.0, MediaQuery.of(context).size.width * 0.94),
      ),
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
    ).whenComplete(_load);
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
                onPressed: _scenes.isEmpty || _batchDeconstructing
                    ? null
                    : _batchDeconstructAllScenes,
                icon: _batchDeconstructing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.hub_outlined, size: 16),
                label: Text(_batchDeconstructing
                    ? (_batchProgress.isNotEmpty ? _batchProgress : '全息解构中…')
                    : '一键全息解构全部场景'),
              ),
              const SizedBox(width: 8),
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
                            scene.referenceImages.isNotEmpty
                                ? Tooltip(
                                    message: '点击查看场景大图',
                                    child: InkWell(
                                      onTap: () {
                                        final ref = scene.referenceImages.first;
                                        final dir = _manager.sceneDir(widget.series.id, scene.id);
                                        final file = File(p.isAbsolute(ref) ? ref : p.join(dir.path, ref));
                                        ImagePreviewDialog.show(
                                          context,
                                          file: file,
                                          title: '场景大图 - ${scene.name}',
                                        );
                                      },
                                      borderRadius: BorderRadius.circular(4),
                                      child: Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: context.accentSubtle,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(4),
                                          child: Image.file(
                                            File(p.isAbsolute(scene.referenceImages.first)
                                                ? scene.referenceImages.first
                                                : p.join(_manager.sceneDir(widget.series.id, scene.id).path, scene.referenceImages.first)),
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Icon(
                                              Icons.landscape_outlined,
                                              color: context.accentText,
                                              size: 20,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                : Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: context.accentSubtle,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Icon(
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
                                      if (scene.panoramaMasterPath != null && scene.panoramaMasterPath!.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withAlpha(25),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: Colors.green.withAlpha(120), width: 0.8),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.panorama_photosphere, size: 10, color: Colors.green),
                                              SizedBox(width: 3),
                                              Text(
                                                '360°全景母核',
                                                style: TextStyle(
                                                  color: Colors.green,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                      if (scene.hasSpatialDeconstruction) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: context.accentSubtle,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '7方位已就绪',
                                            style: TextStyle(
                                              color: context.accentText,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
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
  late List<String> _refs;
  late Map<String, SceneDirectionalView> _spatialViews;
  SceneDirection _activeDirection = SceneDirection.front;
  final Map<SceneDirection, TextEditingController> _directionDescControllers = {};
  final Map<SceneDirection, Set<String>> _selectedRefsPerDirection = {};

  List<String> get _baseConceptRefs =>
      _refs.where((r) => !p.basename(r).startsWith('spatial_')).toList();

  String? get _frontAnchorRef {
    final front = _spatialViews[SceneDirection.front.name];
    if (front != null && front.imagePath != null && front.imagePath!.isNotEmpty) {
      return front.imagePath;
    }
    return null;
  }

  Set<String> _getSelectedRefsForDirection(SceneDirection dir) {
    if (_selectedRefsPerDirection.containsKey(dir)) {
      return _selectedRefsPerDirection[dir]!;
    }
    if (dir == SceneDirection.front) {
      return _baseConceptRefs.toSet();
    } else {
      final front = _frontAnchorRef;
      return {
        ..._baseConceptRefs,
        if (front != null) front,
      };
    }
  }

  List<String> _resolveRefsForDirection(SceneDirection dir, String sceneDirPath) {
    final rels = _getSelectedRefsForDirection(dir);
    final resolved = <String>[];
    for (final r in rels) {
      final abs = p.isAbsolute(r) ? r : p.join(sceneDirPath, r);
      if (File(abs).existsSync()) {
        resolved.add(abs);
      }
    }
    return resolved;
  }

  bool _deconstructing = false;
  bool _generating = false;
  bool _multiGenerating = false;
  bool _generatingPanorama = false;
  bool _slicingPanorama = false;
  String? _panoramaMasterPath;
  double _panoramaYawOffset = 0.0;
  double _panoramaFov = 105.0;
  double _panoramaPitchOffset = 0.0;
  String _panoramaProgress = '';
  StudioImageDimensionPreset _sceneDimension =
      StudioImageDimensionPreset.defaultScene;
  String _multiGeneratingProgress = '';
  String _lastGeneratedPath = '';
  final Set<SceneDirection> _failedDirections = {};

  File? get _panoramaFile {
    if (_panoramaMasterPath == null || _panoramaMasterPath!.isEmpty) return null;
    final sceneDir = _manager.sceneDir(widget.series.id, widget.scene.id);
    return File(p.isAbsolute(_panoramaMasterPath!)
        ? _panoramaMasterPath!
        : p.join(sceneDir.path, _panoramaMasterPath!));
  }

  /// 集中构建当前弹窗内的最新完整 SceneCard 实例，严密防止保存时全景与校准参数丢失。
  SceneCard _buildCurrentScene({
    Map<String, SceneDirectionalView>? views,
    String? panoramaPath,
  }) {
    final effectiveViews = views ?? _spatialViews;
    final frontView = effectiveViews[SceneDirection.front.name];
    return widget.scene.copyWith(
      name: _name.text.trim().isEmpty ? '未命名场景' : _name.text.trim(),
      descriptionZh: _descZh.text.trim().isNotEmpty
          ? _descZh.text.trim()
          : (frontView?.descriptionZh ?? ''),
      referenceImages: List.from(_refs),
      spatialViews: Map.from(effectiveViews),
      panoramaMasterPath: panoramaPath ?? _panoramaMasterPath,
      panoramaYawOffset: _panoramaYawOffset,
      panoramaFov: _panoramaFov,
      panoramaPitchOffset: _panoramaPitchOffset,
      updatedAt: DateTime.now(),
    );
  }

  void _openPanorama3dViewer() {
    final pano = _panoramaFile;
    if (pano == null || !pano.existsSync()) return;

    final currentScene = _buildCurrentScene();

    Panorama3dViewerDialog.show(
      context,
      panoramaFile: pano,
      scene: currentScene,
      seriesId: widget.series.id,
      initialYawOffset: _panoramaYawOffset,
      initialFov: _panoramaFov,
      initialPitch: _panoramaPitchOffset,
      onBaselineChanged: (newYaw, newPitch, newFov) {
        setState(() {
          _panoramaYawOffset = newYaw;
          _panoramaPitchOffset = newPitch;
          _panoramaFov = newFov;
        });
      },
      onYawOffsetChanged: (newYaw) {
        setState(() {
          _panoramaYawOffset = newYaw;
        });
      },
      onReSliceRequested: () {
        _sliceAllFromPanorama();
      },
      onSnapshotSaved: (newRef) {
        setState(() {
          if (!_refs.contains(newRef)) {
            _refs.insert(0, newRef);
          }
        });
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.scene.name);
    _descZh = TextEditingController(text: widget.scene.descriptionZh);
    _refs = widget.scene.referenceImages
        .where((r) => !p.basename(r).startsWith('spatial_'))
        .toList();
    _spatialViews = Map.from(widget.scene.fullSpatialViews);
    _panoramaMasterPath = widget.scene.panoramaMasterPath;
    _panoramaYawOffset = widget.scene.panoramaYawOffset;
    _panoramaFov = widget.scene.panoramaFov;
    _panoramaPitchOffset = widget.scene.panoramaPitchOffset;

    for (final dir in SceneDirection.values) {
      final view = _spatialViews[dir.name] ?? SceneDirectionalView(direction: dir);
      _directionDescControllers[dir] = TextEditingController(text: view.descriptionZh);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _descZh.dispose();
    for (final c in _directionDescControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// AI 推演解构 7 个方位的纯物理空镜空间档案（中文）。
  Future<void> _deconstructSpatial() async {
    setState(() => _deconstructing = true);
    try {
      final baseDesc = _descZh.text.trim().isNotEmpty
          ? _descZh.text.trim()
          : widget.scene.descriptionZh;
      final result = await AiConstraintEngine.deconstructSceneSpatialProfile(
        sceneName: _name.text.trim().isNotEmpty ? _name.text.trim() : widget.scene.name,
        baseDescription: baseDesc.isNotEmpty ? baseDesc : '纯净空间场景',
        productionType: widget.series.productionType.id,
        eraGenre: widget.series.eraGenre,
        visualStyle: widget.series.styleTokens,
      );
      final currentScene = widget.scene.copyWith(spatialViews: _spatialViews);
      final parsed = AiConstraintEngine.parseSpatialViewsFromResult(
        result.data,
        baseScene: currentScene,
      );
      final sanitizedViews = <String, SceneDirectionalView>{};
      for (final entry in parsed.entries) {
        final dir = SceneDirection.fromKey(entry.key);
        _directionDescControllers[dir]?.text = entry.value.descriptionZh;
        sanitizedViews[entry.key] = entry.value;
      }
      setState(() {
        _spatialViews = sanitizedViews;
        if (_descZh.text.trim().isEmpty && sanitizedViews[SceneDirection.front.name]?.descriptionZh.isNotEmpty == true) {
          _descZh.text = sanitizedViews[SceneDirection.front.name]!.descriptionZh;
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已完成 7 方位空间全息解构推演')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('空间全息解构失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _deconstructing = false);
    }
  }

  /// 生成指定方位的纯净空镜场景图并回填。
  Future<void> _generateDirectionImage(SceneDirection dir) async {
    final desc = _directionDescControllers[dir]?.text.trim() ?? '';
    final basePrompt = desc.isNotEmpty ? desc : _descZh.text.trim();
    if (basePrompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请先为【${dir.labelZh}】填写空间描述或场景总览描述')),
      );
      return;
    }
    setState(() => _generating = true);
    try {
      final adapter = SystemAiImageAdapter();
      final sceneDir = _manager.sceneDir(widget.series.id, widget.scene.id);
      final out = File(p.join(
        sceneDir.path,
        'references',
        'spatial_${dir.key}_${DateTime.now().microsecondsSinceEpoch}.png',
      ));
      await out.parent.create(recursive: true);
      _lastGeneratedPath = out.path;

      final resolvedRefs = _resolveRefsForDirection(dir, sceneDir.path);

      final directionalPrompt = dir.formatPrompt(basePrompt);
      final stylePrompt = ScenePromptBuilder.buildPositivePrompt(
        basePrompt: directionalPrompt,
        styleTokens: widget.series.styleTokens,
        eraGenreId: widget.series.eraGenre,
      );
      final negativePrompt = ScenePromptBuilder.buildNegativePrompt(
        eraGenreId: widget.series.eraGenre,
        styleNegativeBan: widget.series.negativeStyleTokens,
      );

      await adapter.generate(ImageGenRequest(
        prompt: stylePrompt,
        negativePrompt: negativePrompt,
        shotNumber: 0,
        outputFile: out,
        width: _sceneDimension.width,
        height: _sceneDimension.height,
        referenceImages: resolvedRefs,
      ));

      final rel = p.relative(out.path, from: sceneDir.path);
      final currentView = _spatialViews[dir.name] ?? SceneDirectionalView(direction: dir);
      _spatialViews[dir.name] = currentView.copyWith(
        descriptionZh: _directionDescControllers[dir]?.text.trim(),
        imagePath: rel,
      );
      _failedDirections.remove(dir);

      final currentScene = _buildCurrentScene();
      await _manager.saveScene(widget.series.id, currentScene);

      if (mounted) {
        setState(() => _generating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已生成【${dir.labelZh}】视角图（纯净空镜）')),
        );
      }
    } catch (e) {
      _failedDirections.add(dir);
      if (mounted) {
        setState(() => _generating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成【${dir.labelZh}】视角图失败: $e')),
        );
      }
    }
  }

  /// 一键生成 360° 等矩球形全景母图（纯文生图，无参考图构图死锁）。
  Future<void> _generatePanoramaMaster() async {
    final baseDesc = _descZh.text.trim().isNotEmpty
        ? _descZh.text.trim()
        : widget.scene.name;
    if (baseDesc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写场景总览描述或场景名称')),
      );
      return;
    }

    setState(() {
      _generatingPanorama = true;
      _panoramaProgress = '正在向 AI 模型请求 360° 等矩空间全景图…';
    });

    try {
      final adapter = SystemAiImageAdapter();
      final sceneDir = _manager.sceneDir(widget.series.id, widget.scene.id);
      final panoDir = _manager.scenePanoramasDir(widget.series.id, widget.scene.id);
      await panoDir.create(recursive: true);

      final out = File(p.join(
        panoDir.path,
        'pano_master_${DateTime.now().microsecondsSinceEpoch}.png',
      ));

      final panoPrompt = ScenePromptBuilder.buildPanoramaPrompt(
        basePrompt: baseDesc,
        styleTokens: widget.series.styleTokens,
        eraGenreId: widget.series.eraGenre,
      );

      final negativePrompt = ScenePromptBuilder.buildNegativePrompt(
        eraGenreId: widget.series.eraGenre,
        styleNegativeBan: widget.series.negativeStyleTokens,
      );

      // 严格传空 referenceImages：彻底杜绝图生图构图保留带来的反打死锁
      // 采用 Agnes 原生 21:9 超宽画幅 4K 超高清分辨率（6272x2688），提供充沛的物理细节
      await adapter.generate(ImageGenRequest(
        prompt: panoPrompt,
        negativePrompt: negativePrompt,
        shotNumber: 0,
        outputFile: out,
        width: 6272,
        height: 2688,
        referenceImages: const [],
      ));

      final relPath = p.relative(out.path, from: sceneDir.path);
      setState(() {
        _panoramaMasterPath = relPath;
        _panoramaProgress = '全景图生成完毕，正在进行秒级切片…';
      });

      final updatedScene = _buildCurrentScene(panoramaPath: relPath);
      await _manager.saveScene(widget.series.id, updatedScene);

      // 自动触发一键切片填充
      await _sliceAllFromPanorama();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('360° 全景母图已就绪，已自动提取四向透视机位！')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成 360° 全景母图失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _generatingPanorama = false;
          _panoramaProgress = '';
        });
      }
    }
  }

  /// 一键无损切片：从全景母图在本地并发投影提取正/背/左/右机位。
  Future<void> _sliceAllFromPanorama() async {
    final pano = _panoramaFile;
    if (pano == null || !pano.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('全景母图文件不存在，请先生成全景母图')),
      );
      return;
    }

    setState(() {
      _slicingPanorama = true;
      _panoramaProgress = '正在进行球面极坐标虚拟相机切片 (本地毫秒级)…';
    });

    try {
      final sceneDir = _manager.sceneDir(widget.series.id, widget.scene.id);
      final refsDir = Directory(p.join(sceneDir.path, 'references'));
      await refsDir.create(recursive: true);

      final result = await SphericalPerspectiveSlicer.sliceBatchAsync(
        BatchSliceRequest(
          panoramaPath: pano.path,
          outputDir: refsDir.path,
          outputWidth: _sceneDimension.width,
          outputHeight: _sceneDimension.height,
          fovDegrees: _panoramaFov,
          yawOffset: _panoramaYawOffset,
          pitchOffset: _panoramaPitchOffset,
          directions: const [
            SceneDirection.front,
            SceneDirection.back,
            SceneDirection.left,
            SceneDirection.right,
          ],
        ),
      );

      for (final entry in result.slicedFilePaths.entries) {
        final dir = entry.key;
        final rel = p.relative(entry.value, from: sceneDir.path);
        final currentView = _spatialViews[dir.name] ?? SceneDirectionalView(direction: dir);
        _spatialViews[dir.name] = currentView.copyWith(imagePath: rel);
        _failedDirections.remove(dir);
      }

      final updatedScene = _buildCurrentScene();
      await _manager.saveScene(widget.series.id, updatedScene);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已成功切出 4 向机位图 (本地耗时 ${result.elapsedMilliseconds}ms)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('全景投影切片失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _slicingPanorama = false;
          _panoramaProgress = '';
        });
      }
    }
  }

  /// 针对单个方位从全景母图重新切片。
  Future<void> _sliceSingleDirectionFromPanorama(SceneDirection dir) async {
    final pano = _panoramaFile;
    if (pano == null || !pano.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('尚未生成全景母图，请先生成')),
      );
      return;
    }

    setState(() => _slicingPanorama = true);
    try {
      final sceneDir = _manager.sceneDir(widget.series.id, widget.scene.id);
      final refsDir = Directory(p.join(sceneDir.path, 'references'));
      await refsDir.create(recursive: true);

      final outPath = p.join(
        refsDir.path,
        'spatial_${dir.key}_slice_${DateTime.now().microsecondsSinceEpoch}.png',
      );

      final baseYaw = SphericalPerspectiveSlicer.getYawForDirection(dir);
      final calibratedYaw = ((baseYaw + _panoramaYawOffset) % 360.0 + 360.0) % 360.0;
      final basePitch = SphericalPerspectiveSlicer.getPitchForDirection(dir);
      final calibratedPitch = (basePitch + _panoramaPitchOffset).clamp(-85.0, 85.0);

      await SphericalPerspectiveSlicer.sliceSingleAsync(
        panoramaPath: pano.path,
        outputPath: outPath,
        params: CameraPerspectiveParams(
          fovDegrees: _panoramaFov,
          yawDegrees: calibratedYaw,
          pitchDegrees: calibratedPitch,
          outputWidth: _sceneDimension.width,
          outputHeight: _sceneDimension.height,
        ),
      );

      final rel = p.relative(outPath, from: sceneDir.path);
      final currentView = _spatialViews[dir.name] ?? SceneDirectionalView(direction: dir);
      _spatialViews[dir.name] = currentView.copyWith(imagePath: rel);
      _failedDirections.remove(dir);

      final updatedScene = _buildCurrentScene();
      await _manager.saveScene(widget.series.id, updatedScene);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已从全景母图重新切出【${dir.labelZh}】机位图')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重切机位失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _slicingPanorama = false);
    }
  }

  /// 一键生成全息组图（依次调度 7 方位生图并绑定，具备单步故障隔离与断点落盘）。
  Future<void> _generateAllSpatialImages() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('一键生成全息组图 (7视角)'),
        content: const Text(
          '确定为当前场景依次生成全部 7 个视角的空间全息图片吗？\n\n'
          '生成视角包含：正面、背面、左侧、右侧、天顶、地坪与俯视全景。\n'
          '系统将依次调用生图并自动关联至对应方位。若某视角暂态失败，不会阻断其他视角。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认生成 (7图)'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _multiGenerating = true;
      _multiGeneratingProgress = '准备生成 7 方位空间全息组图…';
    });

    final adapter = SystemAiImageAdapter();
    final sceneDir = _manager.sceneDir(widget.series.id, widget.scene.id);
    final negativePrompt = ScenePromptBuilder.buildNegativePrompt(
      eraGenreId: widget.series.eraGenre,
      styleNegativeBan: widget.series.negativeStyleTokens,
    );

    final directions = SceneDirection.values;
    final currentFailed = <SceneDirection, String>{};
    int successCount = 0;

    for (var i = 0; i < directions.length; i++) {
      final dir = directions[i];
      if (mounted) {
        setState(() {
          _multiGeneratingProgress =
              '正在生成 7 方位全息组图 (${i + 1}/${directions.length} ${dir.labelZh})…';
        });
      }

      try {
        final desc = _directionDescControllers[dir]?.text.trim() ?? '';
        final basePrompt = desc.isNotEmpty ? desc : _descZh.text.trim();
        final directionalPrompt = dir.formatPrompt(basePrompt.isNotEmpty ? basePrompt : widget.scene.name);
        final stylePrompt = ScenePromptBuilder.buildPositivePrompt(
          basePrompt: directionalPrompt,
          styleTokens: widget.series.styleTokens,
          eraGenreId: widget.series.eraGenre,
        );

        final resolvedRefs = _resolveRefsForDirection(dir, sceneDir.path);

        final out = File(p.join(
          sceneDir.path,
          'references',
          'spatial_${dir.key}_${DateTime.now().microsecondsSinceEpoch}.png',
        ));
        await out.parent.create(recursive: true);
        _lastGeneratedPath = out.path;

        await adapter.generate(ImageGenRequest(
          prompt: stylePrompt,
          negativePrompt: negativePrompt,
          shotNumber: 0,
          outputFile: out,
          width: _sceneDimension.width,
          height: _sceneDimension.height,
          referenceImages: resolvedRefs,
        ));

        final rel = p.relative(out.path, from: sceneDir.path);

        final currentView = _spatialViews[dir.name] ?? SceneDirectionalView(direction: dir);
        _spatialViews[dir.name] = currentView.copyWith(
          descriptionZh: _directionDescControllers[dir]?.text.trim(),
          imagePath: rel,
        );
        _failedDirections.remove(dir);
        successCount++;

        // 每次成功后即时持久化到磁盘
        final currentScene = _buildCurrentScene();
        await _manager.saveScene(widget.series.id, currentScene);

        if (mounted) {
          setState(() {});
        }
      } catch (e) {
        debugPrint('[SceneEditor] 生成【${dir.labelZh}】方位图片失败: $e');
        currentFailed[dir] = e.toString();
        _failedDirections.add(dir);
        if (mounted) {
          setState(() {});
        }
      }
    }

    if (mounted) {
      setState(() {
        _multiGenerating = false;
        _multiGeneratingProgress = '';
      });
      if (currentFailed.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('7 方位全息组图生成完成并已自动绑定')),
        );
      } else if (successCount > 0) {
        final failedLabels = currentFailed.keys.map((d) => d.labelZh).join('、');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('全息组图已完成 $successCount/7。其中【$failedLabels】生成失败（已标红），可单独重试。'),
            duration: const Duration(seconds: 5),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('批量生成全息组图失败: ${currentFailed.values.first}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } else {
      widget.onSaved();
    }
  }

  /// 绑定指定方位的参考图。
  Future<void> _pickImageForDirection(SceneDirection dir) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('绑定【${dir.labelZh}】视角参考图'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'local'),
            child: const Row(
              children: [
                Icon(Icons.file_upload_outlined, size: 18),
                SizedBox(width: 8),
                Text('从本地文件选择'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'asset'),
            child: const Row(
              children: [
                Icon(Icons.photo_library_outlined, size: 18),
                SizedBox(width: 8),
                Text('从资产库选择'),
              ],
            ),
          ),
          if (_refs.isNotEmpty)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'refs'),
              child: const Row(
                children: [
                  Icon(Icons.collections_outlined, size: 18),
                  SizedBox(width: 8),
                  Text('从场景已有参考图选择'),
                ],
              ),
            ),
        ],
      ),
    );

    if (action == null) return;

    if (action == 'local') {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result != null && result.files.isNotEmpty && result.files.first.path != null) {
        final rel = await _manager.addSceneReference(
          seriesId: widget.series.id,
          sceneId: widget.scene.id,
          sourceFilePath: result.files.first.path!,
        );
        setState(() {
          if (!_refs.contains(rel)) _refs.add(rel);
          final currentView = _spatialViews[dir.name] ?? SceneDirectionalView(direction: dir);
          _spatialViews[dir.name] = currentView.copyWith(imagePath: rel);
        });
      }
    } else if (action == 'asset') {
      if (!mounted) return;
      final asset = await AssetPickerDialog.show(
        context,
        kind: AssetKind.image,
        title: '选择【${dir.labelZh}】视角参考图',
      );
      if (asset != null && await asset.file.exists()) {
        final rel = await _manager.addSceneReference(
          seriesId: widget.series.id,
          sceneId: widget.scene.id,
          sourceFilePath: asset.path,
        );
        setState(() {
          if (!_refs.contains(rel)) _refs.add(rel);
          final currentView = _spatialViews[dir.name] ?? SceneDirectionalView(direction: dir);
          _spatialViews[dir.name] = currentView.copyWith(imagePath: rel);
        });
      }
    } else if (action == 'refs') {
      if (!mounted) return;
      final selectedRef = await showDialog<String>(
        context: context,
        builder: (ctx) {
          final sceneDir = _manager.sceneDir(widget.series.id, widget.scene.id);
          return AlertDialog(
            title: Text('选择【${dir.labelZh}】参考图'),
            content: SizedBox(
              width: 380,
              height: 260,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _refs.length,
                itemBuilder: (ctx, i) {
                  final ref = _refs[i];
                  final file = File(p.isAbsolute(ref) ? ref : p.join(sceneDir.path, ref));
                  return InkWell(
                    onTap: () => Navigator.pop(ctx, ref),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: context.borderSubtle),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.file(file, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
                      ),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            ],
          );
        },
      );
      if (selectedRef != null) {
        setState(() {
          final currentView = _spatialViews[dir.name] ?? SceneDirectionalView(direction: dir);
          _spatialViews[dir.name] = currentView.copyWith(imagePath: selectedRef);
        });
      }
    }
  }

  void _clearImageForDirection(SceneDirection dir) {
    setState(() {
      final currentView = _spatialViews[dir.name] ?? SceneDirectionalView(direction: dir);
      _spatialViews[dir.name] = currentView.copyWith(clearImagePath: true);
    });
  }

  IconData _directionIcon(SceneDirection dir) {
    switch (dir) {
      case SceneDirection.front:
        return Icons.crop_portrait;
      case SceneDirection.back:
        return Icons.flip_to_back;
      case SceneDirection.left:
        return Icons.arrow_back;
      case SceneDirection.right:
        return Icons.arrow_forward;
      case SceneDirection.top:
        return Icons.roofing;
      case SceneDirection.bottom:
        return Icons.border_bottom;
      case SceneDirection.topDown:
        return Icons.map_outlined;
    }
  }

  Widget _buildDirectionRefSelector(SceneDirection dir) {
    final selectedSet = _getSelectedRefsForDirection(dir);
    final sceneDir = _manager.sceneDir(widget.series.id, widget.scene.id);

    final baseConceptItems = <Map<String, dynamic>>[];
    for (var i = 0; i < _baseConceptRefs.length; i++) {
      baseConceptItems.add({
        'path': _baseConceptRefs[i],
        'label': '概念图 #${i + 1}',
        'isAnchor': false,
        'direction': null,
      });
    }

    final frontItem = _frontAnchorRef != null && dir != SceneDirection.front
        ? {
            'path': _frontAnchorRef!,
            'label': '正面主景 (锚点)',
            'isAnchor': true,
            'direction': SceneDirection.front,
          }
        : null;

    final otherItems = <Map<String, dynamic>>[];
    for (final otherDir in SceneDirection.values) {
      if (otherDir == dir || otherDir == SceneDirection.front) continue;
      final view = _spatialViews[otherDir.name];
      if (view != null && view.imagePath != null && view.imagePath!.isNotEmpty) {
        otherItems.add({
          'path': view.imagePath!,
          'label': '方位: ${otherDir.labelZh}',
          'isAnchor': false,
          'direction': otherDir,
        });
      }
    }

    final hasFrontAnchor = _frontAnchorRef != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.hub_outlined, size: 14, color: context.accentText),
            const SizedBox(width: 6),
            Text(
              '生图参考图源 (方案 B 防污染链)',
              style: TextStyle(
                color: context.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                dir == SceneDirection.front
                    ? '正面主景仅以基础概念图为准'
                    : '侧向方位默认仅继承正面主景与基础图，杜绝交叉污染',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.textTertiary, fontSize: 11),
              ),
            ),
            if (_selectedRefsPerDirection.containsKey(dir))
              TextButton(
                onPressed: () {
                  setState(() {
                    _selectedRefsPerDirection.remove(dir);
                  });
                },
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                child: const Text('重置为默认', style: TextStyle(fontSize: 11)),
              ),
          ],
        ),
        if (dir != SceneDirection.front && !hasFrontAnchor) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: context.warningText.withAlpha(20),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: context.warningText.withAlpha(80)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 13, color: context.warningText),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '尚未生成【正面主景】。建议先生成正面主景图，以便此方位继承正面的材质色调锚点。',
                    style: TextStyle(color: context.warningText, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final item in baseConceptItems)
              _buildRefChip(
                item: item,
                selected: selectedSet.contains(item['path']),
                sceneDirPath: sceneDir.path,
                dir: dir,
              ),
            if (frontItem != null)
              _buildRefChip(
                item: frontItem,
                selected: selectedSet.contains(frontItem['path']),
                sceneDirPath: sceneDir.path,
                dir: dir,
              ),
            for (final item in otherItems)
              _buildRefChip(
                item: item,
                selected: selectedSet.contains(item['path']),
                sceneDirPath: sceneDir.path,
                dir: dir,
              ),
            if (baseConceptItems.isEmpty && frontItem == null && otherItems.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '暂无可用的参考图（下方可上传基础概念图）',
                  style: TextStyle(color: context.textTertiary, fontSize: 11),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildRefChip({
    required Map<String, dynamic> item,
    required bool selected,
    required String sceneDirPath,
    required SceneDirection dir,
  }) {
    final relPath = item['path'] as String;
    final label = item['label'] as String;
    final isAnchor = item['isAnchor'] as bool;
    final absPath = p.isAbsolute(relPath) ? relPath : p.join(sceneDirPath, relPath);
    final file = File(absPath);

    return FilterChip(
      selected: selected,
      avatar: file.existsSync()
          ? ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Image.file(
                file,
                width: 16,
                height: 16,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 14),
              ),
            )
          : null,
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 11,
        color: selected
            ? (isAnchor ? Colors.amber[200] : context.textPrimary)
            : context.textSecondary,
        fontWeight: isAnchor ? FontWeight.w600 : FontWeight.normal,
      ),
      side: isAnchor
          ? BorderSide(
              color: selected ? Colors.amber.withAlpha(200) : Colors.amber.withAlpha(80),
              width: 1.2,
            )
          : null,
      backgroundColor: context.bgInput,
      selectedColor: isAnchor
          ? Colors.amber.withAlpha(40)
          : context.accentSubtle,
      onSelected: (bool sel) {
        final current = Set<String>.from(_getSelectedRefsForDirection(dir));
        if (sel) {
          current.add(relPath);
        } else {
          current.remove(relPath);
        }
        setState(() {
          _selectedRefsPerDirection[dir] = current;
        });
      },
    );
  }

  Future<void> _pickRefImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;
    for (final file in result.files) {
      if (file.path != null) {
        final rel = await _manager.addSceneReference(
          seriesId: widget.series.id,
          sceneId: widget.scene.id,
          sourceFilePath: file.path!,
        );
        setState(() => _refs.add(rel));
      }
    }
  }

  /// 一键生成多角度场景包（全景建立镜头、主视平视全景、侧逆视角、空间局部特写）。
  Future<void> _generateMultiAngleImages() async {
    final basePrompt = _descZh.text.trim().isNotEmpty
        ? _descZh.text.trim()
        : widget.scene.name;
    if (basePrompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写场景总览描述')),
      );
      return;
    }
    setState(() {
      _multiGenerating = true;
      _multiGeneratingProgress = '准备生成多角度场景包…';
    });
    try {
      final adapter = SystemAiImageAdapter();
      final dir = _manager.sceneDir(widget.series.id, widget.scene.id);
      final resolvedRefs = _refs.map((r) {
        if (p.isAbsolute(r)) return r;
        return p.join(dir.path, r);
      }).toList();

      final negativePrompt = ScenePromptBuilder.buildNegativePrompt(
        eraGenreId: widget.series.eraGenre,
        styleNegativeBan: widget.series.negativeStyleTokens,
      );

      final angles = SceneCameraAngle.values;
      for (var i = 0; i < angles.length; i++) {
        final angle = angles[i];
        if (!mounted) break;
        setState(() {
          _multiGeneratingProgress =
              '正在生成多角度场景包 (${i + 1}/${angles.length} ${angle.labelZh})…';
        });

        final out = File(p.join(
          dir.path,
          'references',
          'gen_${angle.name}_${DateTime.now().microsecondsSinceEpoch}.png',
        ));
        await out.parent.create(recursive: true);
        _lastGeneratedPath = out.path;

        final anglePrompt = ScenePromptBuilder.buildPositivePrompt(
          basePrompt: basePrompt,
          styleTokens: widget.series.styleTokens,
          eraGenreId: widget.series.eraGenre,
          angle: angle,
        );

        await adapter.generate(ImageGenRequest(
          prompt: anglePrompt,
          negativePrompt: negativePrompt,
          shotNumber: 0,
          outputFile: out,
          width: _sceneDimension.width,
          height: _sceneDimension.height,
          referenceImages: resolvedRefs,
        ));

        final rel = await _manager.addSceneReference(
          seriesId: widget.series.id,
          sceneId: widget.scene.id,
          sourceFilePath: out.path,
        );
        if (mounted) {
          setState(() {
            _refs.add(rel);
          });
        }
      }

      if (mounted) {
        setState(() {
          _multiGenerating = false;
          _multiGeneratingProgress = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('多角度场景包已成功生成并追加至参考图库')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _multiGenerating = false;
          _multiGeneratingProgress = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成多角度场景包失败: $e')),
        );
      }
    }
  }

  /// 把场景图收进资产库，归类为 scene。
  Future<void> _collectToAssets() async {
    final dir = _manager.sceneDir(widget.series.id, widget.scene.id);
    final target = _lastGeneratedPath.isNotEmpty
        ? _lastGeneratedPath
        : (_refs.isNotEmpty
            ? (p.isAbsolute(_refs.first) ? _refs.first : p.join(dir.path, _refs.first))
            : '');
    if (target.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有场景图可收集')),
      );
      return;
    }
    final first = File(target);
    if (!await first.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('场景图文件缺失，请重新生成')),
      );
      return;
    }
    try {
      final call = await VideoTaskLedger.instance.findByTargetPath(target);
      await AssetLibrary.instance.addAsset(
        first,
        kind: AssetKind.image,
        source: AssetSource.remote,
        prompt: _descZh.text.trim().isNotEmpty ? _descZh.text.trim() : widget.scene.name,
        sourceCallId: call?.localId,
        originPath: target,
        category: AssetCategory.scene,
        tags: [widget.scene.name],
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已收进资产库')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('收进资产库失败: $e')),
        );
      }
    }
  }

  /// 从资产库选一张图当场景参考图。
  Future<void> _pickRefImageFromAssets() async {
    final asset = await AssetPickerDialog.show(
      context,
      kind: AssetKind.image,
      title: '选择场景参考图',
    );
    if (asset == null) return;
    if (!await asset.file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该资产文件已丢失')),
      );
      return;
    }
    final rel = await _manager.addSceneReference(
      seriesId: widget.series.id,
      sceneId: widget.scene.id,
      sourceFilePath: asset.path,
    );
    setState(() => _refs.add(rel));
  }

  Future<void> _save() async {
    final updatedViews = <String, SceneDirectionalView>{};
    for (final dir in SceneDirection.values) {
      final existing = _spatialViews[dir.name] ?? SceneDirectionalView(direction: dir);
      updatedViews[dir.name] = existing.copyWith(
        descriptionZh: _directionDescControllers[dir]?.text.trim() ?? '',
      );
    }
    final updated = _buildCurrentScene(views: updatedViews);
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
    final currentView = _spatialViews[_activeDirection.name] ?? SceneDirectionalView(direction: _activeDirection);
    final sceneDir = _manager.sceneDir(widget.series.id, widget.scene.id);
    final dirImagePath = currentView.imagePath;
    final dirImageFile = dirImagePath != null && dirImagePath.isNotEmpty
        ? File(p.isAbsolute(dirImagePath) ? dirImagePath : p.join(sceneDir.path, dirImagePath))
        : null;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '编辑场景资产 (7方位空间全息)',
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
          const Divider(height: 18),
          Expanded(
            child: ListView(
              children: [
                TextField(
                  controller: _name,
                  style: TextStyle(color: context.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(labelText: '场景名称 (如: 总裁顶层办公室、议事大厅、丽香苑后院)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descZh,
                  maxLines: 3,
                  style: TextStyle(color: context.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: '场景总览与基础环境描述 (中文)',
                    hintText: '描述场景总体采光、主布局、建筑色调与空间气质',
                  ),
                ),
                const SizedBox(height: 16),
                // --- 360° 空间全景母核工作区 ---------------------------------------
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: context.bgCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _panoramaFile?.existsSync() == true
                          ? context.accentText.withAlpha(120)
                          : context.borderSubtle,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.panorama_photosphere_outlined, size: 18, color: context.accentText),
                          const SizedBox(width: 8),
                          Text(
                            '360° 空间全景母核 (空间绝对一致性基石)',
                            style: TextStyle(
                              color: context.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '（1次文生母图 · 本地毫秒级无损切片正/反/侧机位 · 彻底根除反打雷同）',
                            style: TextStyle(color: context.textTertiary, fontSize: 11),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: (_generatingPanorama || _slicingPanorama || _generating)
                                ? null
                                : _generatePanoramaMaster,
                            icon: _generatingPanorama
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.auto_awesome, size: 15),
                            label: Text(_generatingPanorama ? '全景母图生成中…' : '✨ 生成 360° 全景母图 (1次API)'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: (_generatingPanorama || _slicingPanorama || _generating || _panoramaFile?.existsSync() != true)
                                ? null
                                : _sliceAllFromPanorama,
                            icon: _slicingPanorama
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.crop_free, size: 15),
                            label: Text(_slicingPanorama ? '正在本地切片…' : '🔄 一键无损切片 (本地秒级)'),
                          ),
                        ],
                      ),
                      if (_panoramaProgress.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: context.accentSubtle,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _panoramaProgress,
                                    style: TextStyle(color: context.accentText, fontSize: 12, fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_panoramaFile?.existsSync() == true) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Tooltip(
                              message: '点击进入 360° 3D 沉浸空间漫游与机位校准',
                              child: InkWell(
                                onTap: _openPanorama3dViewer,
                                borderRadius: BorderRadius.circular(6),
                                child: Stack(
                                  children: [
                                    Container(
                                      height: 64,
                                      width: 150,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: context.accentText.withAlpha(150), width: 1.5),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(5),
                                        child: Image.file(_panoramaFile!, fit: BoxFit.cover),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 4,
                                      right: 4,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withAlpha(180),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: const [
                                            Icon(Icons.threed_rotation, size: 11, color: Colors.white),
                                            SizedBox(width: 2),
                                            Text('3D 漫游', style: TextStyle(color: Colors.white, fontSize: 9)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withAlpha(30),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.green, width: 0.8),
                                        ),
                                        child: const Text('4K 全景母核已就绪', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: context.accentSubtle,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '基准角: ${_panoramaYawOffset.toStringAsFixed(1)}° | 视场: ${_panoramaFov.toStringAsFixed(0)}°',
                                          style: TextStyle(color: context.accentText, fontSize: 11, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '规格: 21:9 4K (6272×2688) · 极坐标球面覆盖',
                                        style: TextStyle(color: context.textTertiary, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '点击左侧缩略图或右侧按钮进入 3D 虚拟空间视口，可 360° 环顾四周并将主景一键设为正面基准。',
                                          style: TextStyle(color: context.textSecondary, fontSize: 11),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      FilledButton.tonalIcon(
                                        onPressed: _openPanorama3dViewer,
                                        icon: const Icon(Icons.explore_outlined, size: 14),
                                        label: const Text('🌐 3D 沉浸漫游与校准'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // --- 7方位空间全息档案矩阵 ------------------------------------
                Row(
                  children: [
                    Icon(Icons.spatial_audio_off_outlined, size: 16, color: context.accentText),
                    const SizedBox(width: 6),
                    Text(
                      '七方位空间全息档案',
                      style: TextStyle(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '（3D纯净空镜 · 彻底过滤人物 · 供下游机位智能匹配）',
                      style: TextStyle(color: context.textTertiary, fontSize: 11),
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: (_deconstructing || _multiGenerating) ? null : _deconstructSpatial,
                      icon: _deconstructing
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.auto_awesome, size: 15),
                      label: Text(_deconstructing ? '空间全息解构中…' : 'AI 全息解构七方位 (仅文字)'),
                    ),
                    const SizedBox(width: 8),
                    ImageDimensionSelector(
                      selectedPreset: _sceneDimension,
                      compact: true,
                      enabled: !_deconstructing && !_multiGenerating && !_generating,
                      onChanged: (p) => setState(() => _sceneDimension = p),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: (_deconstructing || _multiGenerating || _generating) ? null : _generateAllSpatialImages,
                      icon: _multiGenerating
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.burst_mode, size: 15),
                      label: Text(_multiGenerating ? '组图生成中…' : '一键生成全息组图 (7视角)'),
                    ),
                  ],
                ),
                if (_multiGenerating && _multiGeneratingProgress.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: context.accentSubtle,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _multiGeneratingProgress,
                              style: TextStyle(color: context.accentText, fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                // 7 方位切换 Tab 条
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final dir in SceneDirection.values) ...[
                        Builder(
                          builder: (context) {
                            final isSelected = dir == _activeDirection;
                            final view = _spatialViews[dir.name] ?? SceneDirectionalView(direction: dir);
                            final hasImg = view.hasImage;
                            final hasTxt = view.descriptionZh.isNotEmpty ||
                                (_directionDescControllers[dir]?.text.trim().isNotEmpty ?? false);
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: InkWell(
                                onTap: () => setState(() => _activeDirection = dir),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: isSelected ? context.bgSelected : context.bgCard,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isSelected ? context.accentText : context.borderSubtle,
                                      width: isSelected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _directionIcon(dir),
                                        size: 14,
                                        color: isSelected ? context.accentText : context.textSecondary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        dir.labelZh,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                          color: isSelected ? context.accentText : context.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      if (hasImg)
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(
                                            color: Colors.green,
                                            shape: BoxShape.circle,
                                          ),
                                        )
                                      else if (_failedDirections.contains(dir))
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(
                                            color: Colors.redAccent,
                                            shape: BoxShape.circle,
                                          ),
                                        )
                                      else if (hasTxt)
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: context.accentText.withAlpha(200),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // 选中视角的详细编辑卡片
                Container(
                  padding: const EdgeInsets.all(14),
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
                          Icon(_directionIcon(_activeDirection), size: 16, color: context.accentText),
                          const SizedBox(width: 6),
                          Text(
                            '${_activeDirection.labelZh}视角 (${_activeDirection.subLabelZh})',
                            style: TextStyle(
                              color: context.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          if (_panoramaFile?.existsSync() == true) ...[
                            FilledButton.tonalIcon(
                              onPressed: (_slicingPanorama || _generating)
                                  ? null
                                  : () => _sliceSingleDirectionFromPanorama(_activeDirection),
                              icon: _slicingPanorama
                                  ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.crop, size: 14),
                              label: const Text('从全景重切'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: (_generating || _multiGenerating || _slicingPanorama)
                                  ? null
                                  : () => _generateDirectionImage(_activeDirection),
                              icon: _generating
                                  ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.auto_awesome, size: 14),
                              label: Text(_generating ? '生成中…' : '独立重绘'),
                            ),
                          ] else ...[
                            FilledButton.tonalIcon(
                              onPressed: (_generating || _multiGenerating)
                                  ? null
                                  : () => _generateDirectionImage(_activeDirection),
                              icon: _generating
                                  ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Icon(
                                      _failedDirections.contains(_activeDirection)
                                          ? Icons.refresh
                                          : Icons.auto_awesome,
                                      size: 14,
                                    ),
                              label: Text(
                                _generating
                                    ? '生成中…'
                                    : (_failedDirections.contains(_activeDirection)
                                        ? '重试此视角图片'
                                        : '生成此视角图片'),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _directionDescControllers[_activeDirection],
                              maxLines: 4,
                              style: TextStyle(color: context.textPrimary, fontSize: 13),
                              decoration: InputDecoration(
                                labelText: '【${_activeDirection.labelZh}】中文空间描写（纯净空镜，如梁木藻井/排窗/铺装）',
                                hintText: '描述该方位所见物理陈设、材质纹理与光照逻辑',
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          // 视角参考图展示与绑定操作
                          SizedBox(
                            width: 140,
                            child: Column(
                              children: [
                                if (dirImageFile != null && dirImageFile.existsSync())
                                  Stack(
                                    children: [
                                      Tooltip(
                                        message: '点击查看大图',
                                        child: InkWell(
                                          onTap: () => ImagePreviewDialog.show(
                                            context,
                                            file: dirImageFile,
                                            title: '${widget.scene.name} - ${_activeDirection.labelZh}视角',
                                          ),
                                          borderRadius: BorderRadius.circular(6),
                                          child: Container(
                                            width: 140,
                                            height: 96,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: context.borderSubtle),
                                            ),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(6),
                                              child: Image.file(
                                                dirImageFile,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 3,
                                        right: 3,
                                        child: InkWell(
                                          onTap: () => _clearImageForDirection(_activeDirection),
                                          child: Container(
                                            padding: const EdgeInsets.all(2),
                                            decoration: BoxDecoration(
                                              color: Colors.black54,
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: const Icon(Icons.close, size: 12, color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  Container(
                                    width: 140,
                                    height: 96,
                                    decoration: BoxDecoration(
                                      color: context.bgInput,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: context.borderSubtle, style: BorderStyle.solid),
                                    ),
                                    alignment: Alignment.center,
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.image_outlined, size: 24, color: context.textTertiary),
                                        const SizedBox(height: 4),
                                        Text('暂未绑定图', style: TextStyle(color: context.textTertiary, fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => _pickImageForDirection(_activeDirection),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        child: Text(
                                          dirImageFile != null ? '更换图片' : '绑定参考图',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      _buildDirectionRefSelector(_activeDirection),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // --- 场景全部参考图库 -----------------------------------------
                Row(
                  children: [
                    Text('场景全部参考图库 (${_refs.length})', style: TextStyle(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: (_generating || _multiGenerating) ? null : _generateMultiAngleImages,
                      icon: const Icon(Icons.camera_alt_outlined, size: 14),
                      label: const Text('多角度包 (4视角)'),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      onPressed: (_generating || _multiGenerating) ? null : _pickRefImageFromAssets,
                      icon: const Icon(Icons.photo_library_outlined, size: 14),
                      label: const Text('从资产库'),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      onPressed: (_generating || _multiGenerating) ? null : _pickRefImage,
                      icon: const Icon(Icons.add_photo_alternate_outlined, size: 14),
                      label: const Text('上传图片'),
                    ),
                  ],
                ),
                if (_refs.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _collectToAssets,
                      icon: const Icon(Icons.bookmark_add_outlined, size: 14),
                      label: const Text('将当前图收进资产库'),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                if (_refs.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (int i = 0; i < _refs.length; i++)
                        Builder(builder: (context) {
                          final dir = _manager.sceneDir(widget.series.id, widget.scene.id);
                          final refPath = _refs[i];
                          final file = File(p.isAbsolute(refPath) ? refPath : p.join(dir.path, refPath));
                          return Stack(
                            children: [
                              Tooltip(
                                message: '点击查看场景大图',
                                child: InkWell(
                                  onTap: () => ImagePreviewDialog.show(
                                    context,
                                    file: file,
                                    title: '场景参考图 - ${_name.text}',
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                  child: Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: context.borderSubtle),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: Image.file(
                                        file,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 2,
                                right: 2,
                                child: InkWell(
                                  onTap: () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('删除场景参考图'),
                                        content: const Text('确定从场景中移除该参考图吗？'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
                                        ],
                                      ),
                                    );
                                    if (ok != true) return;
                                    try {
                                      if (await file.exists()) {
                                        await file.delete();
                                      }
                                    } catch (_) {}
                                    setState(() {
                                      final removed = _refs.removeAt(i);
                                      // 若当前方位绑定了该图，同步解绑
                                      for (final entry in _spatialViews.entries) {
                                        if (entry.value.imagePath == removed) {
                                          _spatialViews[entry.key] = entry.value.copyWith(clearImagePath: true);
                                        }
                                      }
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                                    child: const Icon(Icons.close, size: 12, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }),
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

/// 道具页签：列表 + 新建 + 编辑入口。
class _PropsTab extends StatefulWidget {
  const _PropsTab({required this.series});

  final StudioSeries series;

  @override
  State<_PropsTab> createState() => _PropsTabState();
}

class _PropsTabState extends State<_PropsTab> {
  final _manager = StudioProjectManager.instance;
  List<PropCard> _props = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _manager.listProps(widget.series.id);
    if (!mounted) return;
    setState(() => _props = list);
  }

  void _openEditor(PropCard prop) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => _PropEditorSheet(
        series: widget.series,
        prop: prop,
        onSaved: _load,
        onDeleted: _load,
      ),
    );
  }

  Future<void> _create() async {
    final name = await _promptName(context, '新建道具');
    if (name == null || name.trim().isEmpty) return;
    final created = await _manager.createProp(
      seriesId: widget.series.id,
      name: name.trim(),
    );
    await _load();
    if (mounted) _openEditor(created);
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
                '道具库 (${_props.length})',
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '剧本里的主要道具；关键道具建议出参考图保持跨镜一致',
                style: TextStyle(color: context.textTertiary, fontSize: 12),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新建道具'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _props.isEmpty
              ? Center(
                  child: Text(
                    '还没有道具。点击右上角新建道具。',
                    style: TextStyle(color: context.textTertiary, fontSize: 13),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  itemCount: _props.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final prop = _props[i];
                    return InkWell(
                      onTap: () => _openEditor(prop),
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
                            prop.referenceImages.isNotEmpty
                                ? Tooltip(
                                    message: '点击查看道具大图',
                                    child: InkWell(
                                      onTap: () {
                                        final file = File(p.join(
                                          _manager.propDir(widget.series.id, prop.id).path,
                                          prop.referenceImages.first,
                                        ));
                                        ImagePreviewDialog.show(
                                          context,
                                          file: file,
                                          title: '道具大图 - ${prop.name}',
                                        );
                                      },
                                      borderRadius: BorderRadius.circular(4),
                                      child: Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: context.accentSubtle,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(4),
                                          child: Image.file(
                                            File(p.join(
                                              _manager.propDir(widget.series.id, prop.id).path,
                                              prop.referenceImages.first,
                                            )),
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Icon(
                                              Icons.category_outlined,
                                              color: context.accentText,
                                              size: 20,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                : Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: context.accentSubtle,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Icon(
                                      Icons.category_outlined,
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
                                        prop.name,
                                        style: TextStyle(
                                          color: context.textPrimary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (prop.isKeyProp) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: context.accentSubtle,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '关键',
                                            style: TextStyle(
                                              color: context.accentText,
                                              fontSize: 9,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (prop.descriptionZh.trim().isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      prop.descriptionZh,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: context.textTertiary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
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
}

/// 道具编辑面板。
class _PropEditorSheet extends StatefulWidget {
  const _PropEditorSheet({
    required this.series,
    required this.prop,
    required this.onSaved,
    required this.onDeleted,
  });

  final StudioSeries series;
  final PropCard prop;
  final VoidCallback onSaved;
  final VoidCallback onDeleted;

  @override
  State<_PropEditorSheet> createState() => _PropEditorSheetState();
}

class _PropEditorSheetState extends State<_PropEditorSheet> {
  final _manager = StudioProjectManager.instance;
  late final TextEditingController _name;
  late final TextEditingController _descZh;
  late final TextEditingController _promptEn;
  late List<String> _refs;
  late bool _isKeyProp;
  bool _translating = false;
  bool _generating = false;
  StudioImageDimensionPreset _propDimension =
      StudioImageDimensionPreset.defaultProp;

  /// 最近一次「生成道具图」产出的文件。空串表示当前参考图都来自上传。
  ///
  /// 「收进资产库」只收它——上传的参考图是用户自己的图，入库前该由用户明确
  /// 选哪一张（spec: 道具参考图可进入资产库说的是"生成的图片"）。
  String _lastGeneratedPath = '';

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.prop.name);
    _descZh = TextEditingController(text: widget.prop.descriptionZh);
    _promptEn = TextEditingController(text: widget.prop.promptEn);
    _refs = List.from(widget.prop.referenceImages);
    _isKeyProp = widget.prop.isKeyProp;
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
        productionType: widget.series.productionType.id,
        worldview: widget.series.worldview,
        eraGenre: widget.series.eraGenre,
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
    for (final f in result.files) {
      final path = f.path;
      if (path == null) continue;
      _refs.add(await _manager.addPropReference(
        seriesId: widget.series.id,
        propId: widget.prop.id,
        sourceFilePath: path,
      ));
    }
    if (mounted) setState(() {});
  }

  Future<void> _pickRefImageFromAssets() async {
    final asset = await AssetPickerDialog.show(
      context,
      kind: AssetKind.image,
      title: '选择道具参考图',
    );
    if (asset == null) return;
    if (!await asset.file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该资产文件已丢失')),
      );
      return;
    }
    final rel = await _manager.addPropReference(
      seriesId: widget.series.id,
      propId: widget.prop.id,
      sourceFilePath: asset.path,
    );
    if (mounted) setState(() => _refs.add(rel));
  }

  /// 用提示词或参考图生成道具图。
  ///
  /// 走 [SystemAiImageAdapter]——与关键帧同一条生图链路，经
  /// [MediaCapabilityResolver] 规整尺寸与画幅。生成结果先进道具目录，
  /// 再由用户决定是否收进资产库（不自动入库：入库是主动行为）。
  Future<void> _generateImage() async {
    final prompt = _promptEn.text.trim();
    if (prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写英文生图 Prompt')),
      );
      return;
    }
    setState(() => _generating = true);
    try {
      final adapter = SystemAiImageAdapter();
      final out = File(p.join(
        _manager.propDir(widget.series.id, widget.prop.id).path,
        'references',
        'gen_${DateTime.now().microsecondsSinceEpoch}.png',
      ));
      await out.parent.create(recursive: true);
      _lastGeneratedPath = out.path;

      final finalPrompt = PropPromptBuilder.buildPositivePrompt(
        prompt: prompt,
        styleTokens: widget.series.styleTokens,
        eraGenreId: widget.series.eraGenre,
      );
      final finalNeg = PropPromptBuilder.buildNegativePrompt(
        eraGenreId: widget.series.eraGenre,
        styleNegativeBan: widget.series.negativeStyleTokens,
      );

      await adapter.generate(ImageGenRequest(
        prompt: finalPrompt,
        negativePrompt: finalNeg,
        shotNumber: 0,
        outputFile: out,
        width: _propDimension.width,
        height: _propDimension.height,
        referenceImages: _refs
            .map((r) => p.join(
                  _manager.propDir(widget.series.id, widget.prop.id).path,
                  r,
                ))
            .toList(),
      ));
      _refs.add(await _manager.addPropReference(
        seriesId: widget.series.id,
        propId: widget.prop.id,
        sourceFilePath: out.path,
      ));
      if (mounted) {
        setState(() => _generating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('道具图已生成')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _generating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成道具图失败: $e')),
        );
      }
    }
  }

  /// 把道具图收进资产库，归类为道具。
  ///
  /// 传 [AssetCategory.prop] 让它在资产库的筛选器里有自己的位置——这是
  /// prop-cards spec「道具参考图可进入资产库」要求的分类。来源调用 id 从
  /// 调用记录里反查：`SystemAiImageAdapter` 每次生成都会在台账留一条
  /// (`recordImageCall`)，按 targetPath 匹配即可拿到，从而满足 spec
  /// 「其来源调用记录可反查该道具的生成上下文」。
  Future<void> _collectToAssets() async {
    final dir = _manager.propDir(widget.series.id, widget.prop.id);
    final target = _lastGeneratedPath.isNotEmpty
        ? _lastGeneratedPath
        : (_refs.isNotEmpty ? p.join(dir.path, _refs.first) : '');
    if (target.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有道具图可收集')),
      );
      return;
    }
    final first = File(target);
    final exists = await first.exists();
    if (!exists) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('道具图文件缺失，请重新生成')),
      );
      return;
    }
    try {
      final call = await VideoTaskLedger.instance.findByTargetPath(target);
      await AssetLibrary.instance.addAsset(
        first,
        kind: AssetKind.image,
        source: AssetSource.remote,
        prompt: _promptEn.text.trim(),
        sourceCallId: call?.localId,
        originPath: target,
        category: AssetCategory.prop,
        tags: [widget.prop.name],
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已收进资产库')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('收进资产库失败: $e')),
        );
      }
    }
  }

  Future<void> _save() async {
    final updated = widget.prop.copyWith(
      name: _name.text.trim().isEmpty ? '未命名道具' : _name.text.trim(),
      descriptionZh: _descZh.text.trim(),
      promptEn: _promptEn.text.trim(),
      referenceImages: _refs,
      isKeyProp: _isKeyProp,
    );
    await _manager.saveProp(widget.series.id, updated);
    widget.onSaved();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    await _manager.deleteProp(widget.series.id, widget.prop.id);
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
                '编辑道具资产',
                style: TextStyle(color: context.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _delete,
                style: TextButton.styleFrom(foregroundColor: context.errorText),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('删除道具'),
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
                  decoration: const InputDecoration(labelText: '道具名称 (如: 祖传玉佩)'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('关键道具', style: TextStyle(color: context.textPrimary, fontSize: 13)),
                    const SizedBox(width: 8),
                    Switch(
                      value: _isKeyProp,
                      onChanged: (v) => setState(() => _isKeyProp = v),
                    ),
                    Expanded(
                      child: Text(
                        '关键道具值得单独出参考图保持跨镜一致',
                        style: TextStyle(color: context.textTertiary, fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descZh,
                  maxLines: 3,
                  style: TextStyle(color: context.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: '中文外观与用途描述',
                    hintText: '描述道具的材质、颜色、纹样与剧中来历',
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
                    hintText: 'e.g. an antique jade pendant, pale green, carved dragon pattern',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('参考图/道具图 (${_refs.length})', style: TextStyle(color: context.textPrimary, fontSize: 13)),
                    const Spacer(),
                    ImageDimensionSelector(
                      selectedPreset: _propDimension,
                      compact: true,
                      enabled: !_generating,
                      onChanged: (p) => setState(() => _propDimension = p),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _generating ? null : _generateImage,
                      icon: const Icon(Icons.auto_awesome, size: 15),
                      label: Text(_generating ? '生成中…' : '生成道具图'),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      onPressed: _pickRefImageFromAssets,
                      icon: const Icon(Icons.photo_library_outlined, size: 15),
                      label: const Text('从资产库'),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      onPressed: _pickRefImage,
                      icon: const Icon(Icons.add_photo_alternate_outlined, size: 15),
                      label: const Text('添加参考图'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_refs.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: _collectToAssets,
                    icon: const Icon(Icons.bookmark_add_outlined, size: 15),
                    label: const Text('收进资产库'),
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
                            Tooltip(
                              message: '点击查看大图',
                              child: InkWell(
                                onTap: () {
                                  final file = File(p.join(
                                    _manager.propDir(widget.series.id, widget.prop.id).path,
                                    _refs[i],
                                  ));
                                  ImagePreviewDialog.show(
                                    context,
                                    file: file,
                                    title: '道具参考图 - ${_name.text}',
                                  );
                                },
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: context.borderSubtle),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: Image.file(
                                      File(p.join(
                                        _manager.propDir(widget.series.id, widget.prop.id).path,
                                        _refs[i],
                                      )),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                                    ),
                                  ),
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
  final _presetStore = StudioPresetStore.instance;

  late final TextEditingController _worldview;
  late final TextEditingController _style;
  late final TextEditingController _negativeStyle;
  late final TextEditingController _voice;
  late String _eraGenre;
  late String _styleId;
  late StudioProductionType _productionType;
  String _selectedCategory = '全部';
  Timer? _debounce;
  StreamSubscription? _stylesSub;
  StreamSubscription? _erasSub;

  @override
  void initState() {
    super.initState();
    _worldview = TextEditingController(text: widget.series.worldview);
    _style = TextEditingController(text: widget.series.styleTokens);
    _negativeStyle = TextEditingController(text: widget.series.negativeStyleTokens);
    _voice = TextEditingController(text: widget.series.defaultVoiceId);
    _eraGenre = widget.series.eraGenre;
    _styleId = widget.series.styleId;
    _productionType = widget.series.productionType;

    if (_styleId.isNotEmpty) {
      final s = _presetStore.getStyleById(_styleId);
      if (s != null) {
        _selectedCategory = s.category;
      }
    }

    _stylesSub = _presetStore.stylesStream.listen((_) {
      if (mounted) setState(() {});
    });
    _erasSub = _presetStore.erasStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(_WorldviewTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.series.id != oldWidget.series.id ||
        widget.series.updatedAt != oldWidget.series.updatedAt) {
      if (_worldview.text != widget.series.worldview) {
        _worldview.text = widget.series.worldview;
      }
      if (_style.text != widget.series.styleTokens) {
        _style.text = widget.series.styleTokens;
      }
      if (_negativeStyle.text != widget.series.negativeStyleTokens) {
        _negativeStyle.text = widget.series.negativeStyleTokens;
      }
      if (_voice.text != widget.series.defaultVoiceId) {
        _voice.text = widget.series.defaultVoiceId;
      }
      if (_eraGenre != widget.series.eraGenre) {
        setState(() {
          _eraGenre = widget.series.eraGenre;
        });
      }
      if (_styleId != widget.series.styleId) {
        setState(() {
          _styleId = widget.series.styleId;
        });
      }
      if (_productionType != widget.series.productionType) {
        setState(() {
          _productionType = widget.series.productionType;
        });
      }
    }
  }

  @override
  void dispose() {
    _stylesSub?.cancel();
    _erasSub?.cancel();
    if (_debounce?.isActive == true) {
      _debounce?.cancel();
      final updated = widget.series.copyWith(
        worldview: _worldview.text,
        styleId: _styleId,
        styleTokens: _style.text,
        negativeStyleTokens: _negativeStyle.text,
        defaultVoiceId: _voice.text.trim(),
        eraGenre: _eraGenre,
        productionType: _productionType,
      );
      _manager.saveSeries(updated);
      widget.session.updateSeries(updated);
    }
    _worldview.dispose();
    _style.dispose();
    _negativeStyle.dispose();
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
      styleId: _styleId,
      styleTokens: _style.text,
      negativeStyleTokens: _negativeStyle.text,
      defaultVoiceId: _voice.text.trim(),
      eraGenre: _eraGenre,
      productionType: _productionType,
    );
    await _manager.saveSeries(updated);
    widget.session.updateSeries(updated);
  }

  void _applyAestheticStyle(AestheticStyle style) {
    setState(() {
      _styleId = style.id;
      _style.text = style.positiveAnchor;
      _negativeStyle.text = style.negativeBan;
      if (style.category == '实拍电影质感' ||
          style.id.contains('realism') ||
          style.id.contains('live_action')) {
        _productionType = StudioProductionType.drama;
      }
    });
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final eras = _presetStore.eras;
    final allStyles = _presetStore.styles;
    final categories = ['全部', ..._presetStore.stylesByCategory.keys];
    final filteredStyles = _selectedCategory == '全部'
        ? allStyles
        : allStyles.where((s) => s.category == _selectedCategory).toList();
    final currentStyle = _presetStore.getStyleById(_styleId);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 制作形态选择
          Text(
            '剧集制作形态（决定生图/生视频基础质感基准与动态化策略）',
            style: TextStyle(
              color: context.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final type in StudioProductionType.values)
                ChoiceChip(
                  label: Text(type.label, style: const TextStyle(fontSize: 12)),
                  selected: _productionType == type,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _productionType = type;
                      });
                      _save();
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: context.bgCard,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: context.borderSubtle),
            ),
            child: Text(
              _productionType.description,
              style: TextStyle(fontSize: 12, color: context.textSecondary),
            ),
          ),
          const SizedBox(height: 16),
          // 顶部栏：标题与管理中心按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '视觉时代与题材世界观（决定服饰/道具/场景时代锚点与负向排他锁）',
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.tune, size: 14),
                label: const Text('预设库管理中心', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => StudioPresetManagementDialog.show(
                  context,
                  initialEraId: _eraGenre,
                  initialStyleId: _styleId,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 时代题材 Chips
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final era in eras)
                ChoiceChip(
                  label: Text(era.labelZh, style: const TextStyle(fontSize: 12)),
                  selected: _eraGenre == era.id,
                  onSelected: (selected) {
                    setState(() {
                      _eraGenre = selected ? era.id : '';
                    });
                    _save();
                  },
                ),
            ],
          ),
          if (_eraGenre.isNotEmpty) ...[
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final era = _presetStore.getEraById(_eraGenre);
              if (era == null) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.bgCard,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: context.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.shield_outlined, size: 14, color: Colors.green),
                        const SizedBox(width: 4),
                        Text(
                          '时代正向服饰/建筑/道具锚点 (${era.descriptionZh})',
                          style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '服饰：${era.costumeAnchor}',
                      style: TextStyle(color: context.accentText, fontSize: 11),
                    ),
                    if (era.environmentAnchor.isNotEmpty)
                      Text(
                        '空间：${era.environmentAnchor}',
                        style: TextStyle(color: context.accentText, fontSize: 11),
                      ),
                    if (era.propMaterialAnchor.isNotEmpty)
                      Text(
                        '道具：${era.propMaterialAnchor}',
                        style: TextStyle(color: context.accentText, fontSize: 11),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.block, size: 14, color: Colors.redAccent),
                        const SizedBox(width: 4),
                        Text(
                          '时代负向排他违禁词 (生图时自动杜绝现代穿帮与时空失真)',
                          style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      era.negativeBans,
                      style: TextStyle(color: context.errorText, fontSize: 11),
                    ),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 16),
          _Field(
            controller: _worldview,
            label: '世界观设定',
            maxLines: 6,
            onChanged: (_) => _scheduleSave(),
          ),
          const SizedBox(height: 16),
          // 美学画风分类选择器
          Row(
            children: [
              Text(
                '美学画风定位 (按 8 大工业级体系预设分类绑定)',
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${allStyles.length} 套工业级预设',
                  style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 体系分类筛选
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final cat in categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(cat, style: const TextStyle(fontSize: 11)),
                      selected: _selectedCategory == cat,
                      onSelected: (sel) {
                        if (sel) setState(() => _selectedCategory = cat);
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 风格 Chips
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final style in filteredStyles)
                ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(style.nameZh, style: const TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      Text(
                        '(${style.defaultRatio})',
                        style: TextStyle(
                          fontSize: 10,
                          color: _styleId == style.id ? context.accentText : context.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  selected: _styleId == style.id,
                  onSelected: (selected) {
                    if (selected) {
                      _applyAestheticStyle(style);
                    }
                  },
                ),
            ],
          ),
          if (currentStyle != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.bgCard,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: context.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.palette, size: 14, color: context.accentText),
                      const SizedBox(width: 6),
                      Text(
                        '当前选定画风：${currentStyle.nameZh} [${currentStyle.category}]',
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: context.bgCardHover,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          '画幅 ${currentStyle.defaultRatio}',
                          style: TextStyle(color: context.textSecondary, fontSize: 10),
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.sync, size: 14),
                        label: const Text('重置为本预设默认词', style: TextStyle(fontSize: 11)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _applyAestheticStyle(currentStyle),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    currentStyle.descriptionZh,
                    style: TextStyle(color: context.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          _Field(
            controller: _style,
            label: '全局正向风格词（风格锁）',
            maxLines: 3,
            hint: '如次世代 3D/写实电影质感/新国风水墨提示词，生图时排在首位保持全剧一致',
            onChanged: (_) => _scheduleSave(),
          ),
          const SizedBox(height: 12),
          _Field(
            controller: _negativeStyle,
            label: '美学负向排他词（风格专属防崩锁）',
            maxLines: 3,
            hint: '排斥与此画风相冲突的表现形式（如 3D 排斥 2D手绘、写实排斥卡通动漫），在生图时与时代排他词及通用防崩词自动合并',
            onChanged: (_) => _scheduleSave(),
          ),
          const SizedBox(height: 12),
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
  });

  final TextEditingController controller;
  final String label;
  final int maxLines;
  final String? hint;
  final ValueChanged<String>? onChanged;

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

/// 通用图片全屏预览对话框（支持手势缩放及自适应展示）。
class ImagePreviewDialog extends StatelessWidget {
  const ImagePreviewDialog({
    super.key,
    required this.file,
    this.title = '图片大图预览',
  });

  final File file;
  final String title;

  static void show(BuildContext context, {required File file, String title = '图片大图预览'}) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => ImagePreviewDialog(file: file, title: title),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.file(
                file,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  padding: const EdgeInsets.all(24),
                  color: Colors.black54,
                  child: const Text('图片加载失败或文件已损坏', style: TextStyle(color: Colors.white)),
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

