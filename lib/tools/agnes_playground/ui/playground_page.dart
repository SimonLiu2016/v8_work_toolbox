import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../components/markdown_view.dart';
import '../../../theme/app_theme.dart';
import '../../ai_video_studio/services/video_gen_adapter.dart';
import '../models/playground_models.dart';
import '../services/playground_service.dart';
import '../services/playground_store.dart';

/// Agnes 试炼场主界面。
///
/// 形态照即梦的聊天窗，但**核心不是气泡，是请求快照**：每一轮把"喂了什么"
/// （提示词逐字、参考图副本、吸附后的参数）与"出了什么"（产物、耗时、错误）
/// 并排留档，并提供脱敏请求体视图。气泡只是这些留痕的载体。
///
/// 三通道（文本 / 图像 / 视频）共用同一个消息列表；输入区按通道切换。
class PlaygroundPage extends StatefulWidget {
  const PlaygroundPage({super.key});

  @override
  State<PlaygroundPage> createState() => _PlaygroundPageState();
}

class _PlaygroundPageState extends State<PlaygroundPage> {
  final _service = PlaygroundService.instance;
  final _store = PlaygroundStore.instance;
  final _promptCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  PlaygroundChannel _channel = PlaygroundChannel.video;
  String _providerId = '';
  String _model = PlaygroundChannel.video.defaultModel;

  // 视频参数
  int _durationSec = 5;
  String _sizeTier = '';
  String _ratio = '';
  String _mode = 'auto';
  String _seed = '';

  /// 待提交的媒体（原文件 + 角色）。
  final List<({File file, PlaygroundMediaRole role})> _media = [];

  List<PlaygroundTurn> _turns = const [];
  bool _loading = true;
  bool _submitting = false;

  /// 正在「继续等待」的轮次 id 集合。用 Set 而不是单个 id：用户可能对多个
  /// 云端处理中的轮次同时点继续。
  final Set<String> _resuming = <String>{};
  StreamSubscription<PlaygroundDraft?>? _draftSub;

  @override
  void initState() {
    super.initState();
    _draftSub = _store.draftStream.listen((draft) {
      if (draft != null && mounted) {
        _applyDraft(draft);
      }
    });
    _load();
  }

  @override
  void dispose() {
    _draftSub?.cancel();
    _promptCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _store.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _turns = _store.turns;
      _loading = false;
    });
    _pickDefaultProvider();

    final draft = await _store.consumeDraft();
    if (draft != null && mounted) {
      _applyDraft(draft);
    }
  }

  Map<String, dynamic>? _activeRawPayload;

  void _applyDraft(PlaygroundDraft draft) {
    setState(() {
      _channel = draft.channel;
      if (draft.providerId.isNotEmpty) {
        _providerId = draft.providerId;
      }
      if (draft.model.isNotEmpty) {
        _model = draft.model;
      }
      _promptCtrl.text = draft.prompt;
      _durationSec = draft.durationSec;
      if (draft.sizeTier.isNotEmpty) _sizeTier = draft.sizeTier;
      if (draft.ratio.isNotEmpty) _ratio = draft.ratio;
      if (draft.mode.isNotEmpty) _mode = draft.mode;
      if (draft.seed.isNotEmpty) _seed = draft.seed;
      _media.clear();
      _media.addAll(draft.media);
      _activeRawPayload = draft.rawPayload;
    });
  }

  void _showDraftRequestView() {
    final draft = PlaygroundDraft(
      channel: _channel,
      providerId: _providerId,
      model: _model,
      prompt: _promptCtrl.text,
      media: List.of(_media),
      durationSec: _durationSec,
      sizeTier: _sizeTier,
      ratio: _ratio,
      mode: _mode,
      seed: _seed,
      rawPayload: _activeRawPayload,
    );

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final jsonText = draft.formattedRawPayloadJson;
        final reqText = draft.renderRedactedRequest();
        var showJson = true;

        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final activeText = showJson ? jsonText : reqText;
            return AlertDialog(
              backgroundColor: dialogCtx.bgCard,
              title: Row(
                children: [
                  Text(
                    '当前草稿/任务请求体',
                    style: TextStyle(
                      color: dialogCtx.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        label: Text('HTTP JSON', style: TextStyle(fontSize: 11)),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text('参数概览', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                    selected: {showJson},
                    onSelectionChanged: (set) {
                      setDialogState(() => showJson = set.first);
                    },
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 620,
                height: 420,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: dialogCtx.bgContent,
                    borderRadius: AppTheme.borderRadiusSmall,
                    border: Border.all(color: dialogCtx.borderSubtle),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      activeText,
                      style: TextStyle(
                        color: dialogCtx.textPrimary,
                        fontSize: 12,
                        fontFamily: 'monospace',
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              actions: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy, size: 14),
                  label: const Text('复制请求 JSON'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: jsonText));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已复制脱敏请求 JSON 到剪贴板'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.text_snippet_outlined, size: 14),
                  label: const Text('复制提示词'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _promptCtrl.text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已复制提示词全文到剪贴板'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('关闭'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 默认选中第一个可用供应商。用户没配任何供应商时保持空——提交时会给出
  /// 明确错误，而不是静默用一个不存在的 id。
  void _pickDefaultProvider() {
    final providers = _service.availableProviders();
    if (providers.isEmpty) return;
    final models = _service.modelsFor(providers.first, _channel);
    setState(() {
      _providerId = providers.first.id;
      _model = models.isNotEmpty ? models.first : _channel.defaultModel;
    });
  }

  List<String> get _modelOptions {
    final provider = _service.providerById(_providerId);
    if (provider == null) return const [];
    return _service.modelsFor(provider, _channel);
  }

  // --- 输入处理 -----------------------------------------------------------

  Future<void> _pickMedia(PlaygroundMediaRole role) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
    );
    if (result == null) return;
    setState(() {
      for (final f in result.files) {
        final path = f.path;
        if (path == null || path.isEmpty) continue;
        _media.add((file: File(path), role: role));
      }
    });
  }

  void _removeMedia(int index) {
    setState(() => _media.removeAt(index));
  }

  void _switchChannel(PlaygroundChannel channel) {
    if (channel == _channel) return;
    setState(() {
      _channel = channel;
      _model = channel.defaultModel;
      // 媒体角色是按视频的三种模式定义的；切到别的通道时清空，避免用户
      // 把"首帧"带到图像通道——那儿的图没有角色之分。
      if (channel != PlaygroundChannel.video) {
        _media.clear();
      }
    });
    _syncModelForChannel();
  }

  void _syncModelForChannel() {
    final options = _modelOptions;
    if (options.isNotEmpty && !options.contains(_model)) {
      setState(() => _model = options.first);
    }
  }

  Future<void> _submit() async {
    final prompt = _promptCtrl.text.trim();
    if (prompt.isEmpty) {
      _toast('请先填写提示词');
      return;
    }
    if (_providerId.isEmpty) {
      _toast('请先在「AI 基础设施」配置并启用一个 Agnes 供应商');
      return;
    }
    if (_submitting) return;

    setState(() => _submitting = true);
    final draft = PlaygroundDraft(
      channel: _channel,
      providerId: _providerId,
      model: _model,
      prompt: prompt,
      media: List.of(_media),
      durationSec: _durationSec,
      sizeTier: _sizeTier,
      ratio: _ratio,
      mode: _mode,
      seed: _seed,
    );

    await _service.submit(draft);
    if (!mounted) return;
    setState(() {
      _turns = _store.turns;
      _submitting = false;
      _media.clear();
      _promptCtrl.clear();
    });
    _scrollToBottom();
  }

  Future<void> _resume(PlaygroundTurn turn) async {
    setState(() => _resuming.add(turn.id));
    final ok = await _service.resumeCloudTask(turn);
    if (!mounted) return;
    setState(() {
      _resuming.remove(turn.id);
      _turns = _store.turns;
    });
    _toast(ok ? '已取回视频' : '云端仍在处理，稍后再试');
  }

  Future<void> _collect(PlaygroundTurn turn) async {
    final asset = await _store.collectToAssetLibrary(turn);
    if (!mounted) return;
    _toast(asset != null ? '已收进资产库' : '收进资产库失败');
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // --- 构建 ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgWindow,
      body: Column(
        children: [
          _buildHeader(),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _turns.isEmpty
                    ? _buildEmpty()
                    : _buildTurns(),
          ),
          const Divider(height: 1),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      alignment: Alignment.centerLeft,
      // 顶栏控件多（标题 + 三段通道 + 两个下拉），窄窗口下必须能横滚——
      // 否则右侧的型号选择会被挤出屏幕且无法触达。
      //
      // 横滚的 SingleChildScrollView 给子代的是「宽无限、高不限」的约束，
      // Row 在这种约束下无法定高。用 SizedBox 给一个确定高度，Row 就能按
      // 内容居中——这是横滚包 Row 的标准做法。
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          height: 40,
          child: Row(
        children: [
          Icon(Icons.science_outlined, size: 18, color: context.accentText),
          const SizedBox(width: 8),
          Text(
            'Agnes 试炼场',
            style: TextStyle(
              color: context.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          // 通道切换
          SegmentedButton<PlaygroundChannel>(
            segments: [
              for (final c in PlaygroundChannel.values)
                ButtonSegment(
                  value: c,
                  label: Text(c.label),
                  icon: Icon(_iconFor(c), size: 14),
                ),
            ],
            selected: {_channel},
            onSelectionChanged: (s) => _switchChannel(s.first),
            style: _segmentedStyle(),
          ),
          const SizedBox(width: 12),
          // 供应商
          _buildProviderPicker(),
          const SizedBox(width: 8),
          // 型号
          _buildModelPicker(),
        ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(PlaygroundChannel c) => switch (c) {
        PlaygroundChannel.text => Icons.notes_outlined,
        PlaygroundChannel.image => Icons.image_outlined,
        PlaygroundChannel.video => Icons.movie_outlined,
      };

  ButtonStyle _segmentedStyle() {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return context.bgSelected;
        return null;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return context.accentText;
        return context.textSecondary;
      }),
      textStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 12, color: context.textPrimary),
      ),
    );
  }

  Widget _buildProviderPicker() {
    final providers = _service.availableProviders();
    if (providers.isEmpty) {
      return Text(
        '未配置供应商',
        style: TextStyle(color: context.warningText, fontSize: 11),
      );
    }
    return _MiniDropdown<String>(
      label: '供应商',
      value: _providerId,
      items: [
        for (final p in providers)
          DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) {
        if (v == null) return;
        setState(() {
          _providerId = v;
          _model = '';
        });
        _syncModelForChannel();
      },
    );
  }

  Widget _buildModelPicker() {
    final options = _modelOptions;
    return _MiniDropdown<String>(
      label: '型号',
      value: options.contains(_model) && _model.isNotEmpty
          ? _model
          : (options.isNotEmpty ? options.first : ''),
      items: [
        for (final m in options)
          DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) => setState(() => _model = v ?? ''),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.science_outlined, size: 40, color: context.textTertiary),
            const SizedBox(height: 12),
            Text(
              '还没有任何调用',
              style: TextStyle(color: context.textPrimary, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              '填写提示词与参数，直接调用 Agnes。每一轮都会留下完整请求快照，'
              '方便对比提示词与参考图对画面的影响。',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.textSecondary, fontSize: 12, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTurns() {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(16),
      itemCount: _turns.length,
      itemBuilder: (ctx, i) => _TurnCard(
        turn: _turns[i],
        resuming: _resuming.contains(_turns[i].id),
        onResume: () => _resume(_turns[i]),
        onCollect: () => _collect(_turns[i]),
        onDelete: () async {
          await _store.remove(_turns[i].id);
          if (!mounted) return;
          setState(() => _turns = _store.turns);
        },
      ),
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: context.bgCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_media.isNotEmpty) _buildMediaStrip(),
          if (_channel == PlaygroundChannel.video) _buildVideoParams(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (_channel == PlaygroundChannel.video) ...[
                _MediaButton(
                  icon: Icons.first_page,
                  tooltip: '添加首帧',
                  onTap: () => _pickMedia(PlaygroundMediaRole.firstFrame),
                ),
                const SizedBox(width: 6),
                _MediaButton(
                  icon: Icons.last_page,
                  tooltip: '添加尾帧',
                  onTap: () => _pickMedia(PlaygroundMediaRole.lastFrame),
                ),
                const SizedBox(width: 6),
                _MediaButton(
                  icon: Icons.photo_library_outlined,
                  tooltip: '添加参考图（reference 模式以 <Picture N> 指代）',
                  onTap: () => _pickMedia(PlaygroundMediaRole.reference),
                ),
                const SizedBox(width: 6),
              ] else
                _MediaButton(
                  icon: Icons.add_photo_alternate_outlined,
                  tooltip: '添加参考图',
                  onTap: () => _pickMedia(PlaygroundMediaRole.reference),
                ),
              if (_channel == PlaygroundChannel.video) const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _promptCtrl,
                  maxLines: 4,
                  minLines: 1,
                  style: TextStyle(color: context.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: _channel == PlaygroundChannel.video &&
                            _media.any((m) =>
                                m.role == PlaygroundMediaRole.reference)
                        ? '提示词（reference 模式下用 <Picture N> 指代参考图）'
                        : '提示词',
                    hintStyle: TextStyle(color: context.textTertiary, fontSize: 13),
                    filled: true,
                    fillColor: context.bgContent,
                    border: OutlineInputBorder(
                      borderRadius: AppTheme.borderRadiusSmall,
                      borderSide: BorderSide(color: context.borderSubtle),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: AppTheme.borderRadiusSmall,
                      borderSide: BorderSide(color: context.borderSubtle),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.data_object_outlined, size: 20),
                tooltip: '查看/复制请求体 (JSON)',
                onPressed: _showDraftRequestView,
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('发送'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMediaStrip() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < _media.length; i++)
            _MediaChip(
              role: _media[i].role,
              name: _media[i].file.uri.pathSegments.last,
              index: _media[i].role == PlaygroundMediaRole.reference
                  ? _media
                      .where((m) => m.role == PlaygroundMediaRole.reference)
                      .toList()
                      .indexOf(_media[i]) + 1
                  : null,
              onRemove: () => _removeMedia(i),
            ),
        ],
      ),
    );
  }

  Widget _buildVideoParams() {
    final cap = _service.capabilityFor(_model);
    final sizes = cap.resolutions;
    final ratios = cap.ratios;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _MiniDropdown<String>(
            label: '模式',
            value: _mode,
            items: [
              for (final m in AgnesVideoMode.values)
                // auto 是推导模式，不该出现在手动选择里——用户选它就是选了
                // "让适配器决定"，那正是默认值本身。
                if (m != AgnesVideoMode.auto)
                  DropdownMenuItem(value: m.id, child: Text(m.id)),
            ],
            onChanged: (v) => setState(() => _mode = v ?? 'auto'),
          ),
          _MiniDropdown<int>(
            label: '时长',
            value: _durationSec,
            items: [
              for (final d in (cap.durations.isEmpty
                  ? const [4, 5, 6, 8, 10, 12]
                  : cap.durations))
                DropdownMenuItem(value: d, child: Text('${d}s')),
            ],
            onChanged: (v) => setState(() => _durationSec = v ?? 5),
          ),
          _MiniDropdown<String>(
            label: '清晰度',
            value: _sizeTier,
            items: [
              const DropdownMenuItem(value: '', child: Text('默认')),
              for (final s in sizes)
                DropdownMenuItem(value: s, child: Text(s.toUpperCase())),
            ],
            onChanged: (v) => setState(() => _sizeTier = v ?? ''),
          ),
          _MiniDropdown<String>(
            label: '画幅',
            value: _ratio,
            items: [
              const DropdownMenuItem(value: '', child: Text('默认')),
              for (final r in ratios)
                DropdownMenuItem(value: r, child: Text(r)),
            ],
            onChanged: (v) => setState(() => _ratio = v ?? ''),
          ),
          SizedBox(
            width: 90,
            child: TextField(
              controller: TextEditingController(text: _seed),
              keyboardType: TextInputType.number,
              style: TextStyle(color: context.textPrimary, fontSize: 12),
              decoration: InputDecoration(
                labelText: '种子',
                labelStyle: TextStyle(color: context.textTertiary, fontSize: 11),
                filled: true,
                fillColor: context.bgContent,
                border: OutlineInputBorder(
                  borderRadius: AppTheme.borderRadiusSmall,
                  borderSide: BorderSide(color: context.borderSubtle),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              ),
              onChanged: (v) => _seed = v,
            ),
          ),
        ],
      ),
    );
  }
}

/// 迷你下拉：标签 + 下拉框，横向紧凑排列用。
class _MiniDropdown<T> extends StatelessWidget {
  const _MiniDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    // value 必须出现在 items 里，否则 DropdownButton 直接断言失败。三种情况
    // 会让它不在：items 为空（没配供应商）、value 为空串而 items 不含空串、
    // 切换通道后旧型号不在新列表里。统一在这里归一成 null（显示 hint）而不是
    // 让每个调用点各自保证。
    final safeValue = items.any((it) => it.value == value) ? value : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: context.bgContent,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: context.textTertiary, fontSize: 11),
          ),
          const SizedBox(width: 4),
          DropdownButton<T>(
            value: safeValue,
            items: items,
            onChanged: onChanged,
            underline: const SizedBox.shrink(),
            isDense: true,
            borderRadius: AppTheme.borderRadiusSmall,
            dropdownColor: context.bgCard,
            style: TextStyle(color: context.textPrimary, fontSize: 12),
            hint: Text(
              '未配置',
              style: TextStyle(color: context.textTertiary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// 输入栏的媒体添加按钮。
class _MediaButton extends StatelessWidget {
  const _MediaButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTheme.borderRadiusSmall,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: context.bgContent,
            borderRadius: AppTheme.borderRadiusSmall,
            border: Border.all(color: context.borderSubtle),
          ),
          child: Icon(icon, size: 18, color: context.textSecondary),
        ),
      ),
    );
  }
}

/// 待提交媒体的标签。
class _MediaChip extends StatelessWidget {
  const _MediaChip({
    required this.role,
    required this.name,
    this.index,
    required this.onRemove,
  });

  final PlaygroundMediaRole role;
  final String name;
  final int? index;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final color = switch (role) {
      PlaygroundMediaRole.firstFrame => context.accentText,
      PlaygroundMediaRole.lastFrame => context.warningText,
      PlaygroundMediaRole.reference => context.successText,
    };
    final label = switch (role) {
      PlaygroundMediaRole.firstFrame => '首帧',
      PlaygroundMediaRole.lastFrame => '尾帧',
      PlaygroundMediaRole.reference => '参考 $index',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 11)),
          const SizedBox(width: 6),
          Text(
            name,
            style: TextStyle(color: context.textSecondary, fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onRemove,
            child: Icon(Icons.close, size: 13, color: context.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// 一轮调用的卡片：请求 + 产物 + 操作。
class _TurnCard extends StatelessWidget {
  const _TurnCard({
    required this.turn,
    required this.resuming,
    required this.onResume,
    required this.onCollect,
    required this.onDelete,
  });

  final PlaygroundTurn turn;
  final bool resuming;
  final VoidCallback onResume;
  final VoidCallback onCollect;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusMedium,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMeta(context),
          const SizedBox(height: 8),
          _buildPrompt(context),
          if (turn.media.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildMedia(context),
          ],
          const SizedBox(height: 8),
          _buildResult(context),
          const SizedBox(height: 4),
          _buildActions(context),
        ],
      ),
    );
  }

  Widget _buildMeta(BuildContext context) {
    final statusColor = switch (turn.status) {
      PlaygroundTurnStatus.completed => context.successText,
      PlaygroundTurnStatus.failed => context.errorText,
      PlaygroundTurnStatus.cloudProcessing => context.warningText,
    };
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: statusColor.withAlpha(25),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            turn.status.label,
            style: TextStyle(color: statusColor, fontSize: 11),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${turn.providerName} · ${turn.model}',
          style: TextStyle(color: context.textSecondary, fontSize: 11),
        ),
        const Spacer(),
        Text(
          '${(turn.durationMs / 1000).toStringAsFixed(1)}s',
          style: TextStyle(color: context.textTertiary, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildPrompt(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: context.accentSubtle,
        borderRadius: AppTheme.borderRadiusSmall,
      ),
      child: SelectableText(
        turn.prompt,
        style: TextStyle(color: context.textPrimary, fontSize: 13, height: 1.5),
      ),
    );
  }

  Widget _buildMedia(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final m in turn.media)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: context.bgContent,
              borderRadius: AppTheme.borderRadiusSmall,
              border: Border.all(color: context.borderSubtle),
            ),
            child: Text(
              '${m.role.label}: ${m.originalName}'
              '${m.width != null ? ' ${m.width}×${m.height}' : ''}',
              style: TextStyle(color: context.textSecondary, fontSize: 11),
            ),
          ),
      ],
    );
  }

  Widget _buildResult(BuildContext context) {
    if (turn.status == PlaygroundTurnStatus.failed) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: context.errorText.withAlpha(20),
          borderRadius: AppTheme.borderRadiusSmall,
        ),
        child: Text(
          turn.error ?? '未知错误',
          style: TextStyle(color: context.errorText, fontSize: 12),
        ),
      );
    }
    if (turn.status == PlaygroundTurnStatus.cloudProcessing) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: context.warningText.withAlpha(20),
          borderRadius: AppTheme.borderRadiusSmall,
        ),
        child: Text(
          '${turn.error ?? '云端仍在处理'}\nvideo_id: ${turn.remoteTaskId}',
          style: TextStyle(color: context.warningText, fontSize: 12),
        ),
      );
    }

    final name = turn.outputFileName;
    if (name == null) {
      return Text(
        '无产物',
        style: TextStyle(color: context.textTertiary, fontSize: 12),
      );
    }
    final isVideo = turn.channel == PlaygroundChannel.video;
    final isText = turn.channel == PlaygroundChannel.text;

    final file = PlaygroundStore.instance.outputFile(turn);

    if (isText) {
      // 文本产物用共享 Markdown 视图渲染——与 AI 助手同一套主题。
      return FutureBuilder<String>(
        future: _readOutputText(),
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const SizedBox(
              height: 40,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          return Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: context.bgContent,
              borderRadius: AppTheme.borderRadiusSmall,
            ),
            // 限高 + 内部滚动：模型返回可能几千字，不限高会把整个消息列表顶开，
            // 输入栏被挤出屏幕——用户想改提示词得先滚很远。
            child: AppMarkdownView(
              data: snap.data!,
              baseStyle: TextStyle(color: context.textPrimary, fontSize: 13, height: 1.6),
              maxHeight: 320,
            ),
          );
        },
      );
    }

    if (!isVideo && file != null && file.existsSync()) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _showImageLightbox(context, file),
              child: ClipRRect(
                borderRadius: AppTheme.borderRadiusSmall,
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  decoration: BoxDecoration(
                    color: context.bgContent,
                    borderRadius: AppTheme.borderRadiusSmall,
                    border: Border.all(color: context.borderSubtle),
                  ),
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Image.file(
                        file,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            '图片加载失败',
                            style: TextStyle(color: context.errorText, fontSize: 12),
                          ),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.all(6),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.zoom_in, color: Colors.white, size: 12),
                            SizedBox(width: 4),
                            Text('点击放大', style: TextStyle(color: Colors.white, fontSize: 10)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.image_outlined, size: 14, color: context.textSecondary),
              const SizedBox(width: 4),
              Text(name, style: TextStyle(color: context.textSecondary, fontSize: 11)),
              if (turn.outputBytes != null) ...[
                const SizedBox(width: 8),
                Text(
                  _formatBytes(turn.outputBytes!),
                  style: TextStyle(color: context.textTertiary, fontSize: 11),
                ),
              ],
            ],
          ),
        ],
      );
    }

    if (isVideo && file != null && file.existsSync()) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _openMediaFile(file),
              child: ClipRRect(
                borderRadius: AppTheme.borderRadiusSmall,
                child: Container(
                  height: 140,
                  width: 240,
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: AppTheme.borderRadiusSmall,
                    border: Border.all(color: context.borderSubtle),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Icon(Icons.play_circle_fill, size: 48, color: Colors.white70),
                      Positioned(
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.open_in_new, color: Colors.white, size: 11),
                              SizedBox(width: 4),
                              Text('点击播放视频', style: TextStyle(color: Colors.white, fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.movie_outlined, size: 14, color: context.textSecondary),
              const SizedBox(width: 4),
              Text(name, style: TextStyle(color: context.textSecondary, fontSize: 11)),
              if (turn.outputBytes != null) ...[
                const SizedBox(width: 8),
                Text(
                  _formatBytes(turn.outputBytes!),
                  style: TextStyle(color: context.textTertiary, fontSize: 11),
                ),
              ],
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        Icon(
          isVideo ? Icons.movie_outlined : Icons.image_outlined,
          size: 16,
          color: context.textSecondary,
        ),
        const SizedBox(width: 6),
        Text(
          name,
          style: TextStyle(color: context.textSecondary, fontSize: 12),
        ),
        if (turn.outputBytes != null) ...[
          const SizedBox(width: 8),
          Text(
            _formatBytes(turn.outputBytes!),
            style: TextStyle(color: context.textTertiary, fontSize: 11),
          ),
        ],
      ],
    );
  }

  void _showImageLightbox(BuildContext ownerContext, File file) {
    showDialog<void>(
      context: ownerContext,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: Colors.black87,
          insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 6.0,
                  child: Center(
                    child: Image.file(
                      file,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '用系统应用打开',
                      icon: const Icon(Icons.open_in_new, color: Colors.white, size: 20),
                      onPressed: () => _openMediaFile(file),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: '在访达中显示',
                      icon: const Icon(Icons.folder_open_outlined, color: Colors.white, size: 20),
                      onPressed: () => _revealInFinder(file),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: '关闭',
                      icon: const Icon(Icons.close, color: Colors.white, size: 20),
                      onPressed: () => Navigator.pop(dialogCtx),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static void _openMediaFile(File file) {
    Process.run('open', [file.path]);
  }

  static void _revealInFinder(File file) {
    Process.run('open', ['-R', file.path]);
  }

  Future<String> _readOutputText() async {
    final dir = PlaygroundStore.instance.outputDir(turn.id);
    final name = turn.outputFileName;
    if (name == null) return '';
    final file = File('${dir.path}/$name');
    if (!file.existsSync()) return '（产物文件已丢失）';
    return file.readAsString();
  }

  Widget _buildActions(BuildContext context) {
    final file = PlaygroundStore.instance.outputFile(turn);
    final hasOutput = file != null && file.existsSync();
    final isVideo = turn.channel == PlaygroundChannel.video;

    return Row(
      children: [
        TextButton.icon(
          onPressed: () => _showRequestView(context),
          icon: const Icon(Icons.visibility_outlined, size: 14),
          label: const Text('查看请求', style: TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(foregroundColor: context.accentText),
        ),
        if (hasOutput) ...[
          TextButton.icon(
            onPressed: () => _openMediaFile(file),
            icon: const Icon(Icons.open_in_new, size: 14),
            label: Text(isVideo ? '播放视频' : '打开图片', style: const TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(foregroundColor: context.accentText),
          ),
          TextButton.icon(
            onPressed: () => _revealInFinder(file),
            icon: const Icon(Icons.folder_open_outlined, size: 14),
            label: const Text('在访达中显示', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(foregroundColor: context.textSecondary),
          ),
        ],
        if (turn.status == PlaygroundTurnStatus.cloudProcessing)
          TextButton.icon(
            onPressed: resuming ? null : onResume,
            icon: resuming
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined, size: 14),
            label: const Text('继续等待', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(foregroundColor: context.warningText),
          ),
        if (turn.outputFileName != null &&
            turn.status == PlaygroundTurnStatus.completed)
          TextButton.icon(
            onPressed: onCollect,
            icon: const Icon(Icons.bookmark_add_outlined, size: 14),
            label: const Text('存入资产库', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(foregroundColor: context.successText),
          ),
        const Spacer(),
        IconButton(
          onPressed: onDelete,
          icon: Icon(Icons.delete_outline, size: 15, color: context.textTertiary),
          tooltip: '删除本轮',
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  /// 展示脱敏请求体。这是试炼场最该被用起来的功能——它直接回答
  /// "我到底发了什么"，比任何气泡都值钱。
  void _showRequestView(BuildContext ownerContext) {
    showDialog<void>(
      context: ownerContext,
      builder: (dialogCtx) {
        final jsonText = turn.renderRedactedJson();
        final reqText = turn.renderRedactedRequest();
        var showJson = true;

        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final activeText = showJson ? jsonText : reqText;
            return AlertDialog(
              backgroundColor: dialogCtx.bgCard,
              title: Row(
                children: [
                  Text(
                    '本次提交的请求体',
                    style: TextStyle(
                      color: dialogCtx.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        label: Text('HTTP JSON', style: TextStyle(fontSize: 11)),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text('参数概览', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                    selected: {showJson},
                    onSelectionChanged: (set) {
                      setDialogState(() => showJson = set.first);
                    },
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 620,
                height: 420,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: dialogCtx.bgContent,
                    borderRadius: AppTheme.borderRadiusSmall,
                    border: Border.all(color: dialogCtx.borderSubtle),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      activeText,
                      style: TextStyle(
                        color: dialogCtx.textPrimary,
                        fontSize: 12,
                        fontFamily: 'monospace',
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              actions: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy, size: 14),
                  label: const Text('复制请求 JSON'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: jsonText));
                    ScaffoldMessenger.of(ownerContext).showSnackBar(
                      const SnackBar(
                        content: Text('已复制完整脱敏请求 JSON 到剪贴板'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.text_snippet_outlined, size: 14),
                  label: const Text('复制提示词'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: turn.prompt));
                    ScaffoldMessenger.of(ownerContext).showSnackBar(
                      const SnackBar(
                        content: Text('已复制提示词全文到剪贴板'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('关闭'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0B';
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}
