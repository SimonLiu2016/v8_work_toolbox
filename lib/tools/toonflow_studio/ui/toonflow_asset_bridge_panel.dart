import 'dart:io';

import 'package:flutter/material.dart';

import '../../../components/app_components.dart';
import '../../../theme/app_theme.dart';
import '../../ai_video_studio/models/studio_models.dart';
import '../../ai_video_studio/services/studio_project_manager.dart';
import '../models/toonflow_studio_state.dart';
import '../services/toonflow_asset_bridge.dart';
import '../services/toonflow_compose_service.dart';

/// 资产桥面板：把工坊内容送进 Toonflow，再把成品取回来。
///
/// 单独一个面板而不是塞进工具页主体：工具页已经被容器生命周期占满，而资产桥
/// 的操作对象是「某个剧集的某一集」，需要自己的选择器与结果区。
///
/// 三条 spec 约束在这里落地：
/// 1. **未选中集时不猜**（spec: 导回的扫描与归集）——两个按钮在没选中集时都
///    禁用，并说明原因，而不是默认挑第一集；
/// 2. **导出结果必须说清没做什么**（spec: 写画布内容的权限边界）——报告里
///    明确「未创建任何连线、未触发生成」；
/// 3. **容器没跑起来时不给导**——工作区目录归容器管，容器不在时导出的东西
///    用户看不到，导入更是无从谈起。
class ToonflowAssetBridgePanel extends StatefulWidget {
  const ToonflowAssetBridgePanel({super.key});

  @override
  State<ToonflowAssetBridgePanel> createState() =>
      _ToonflowAssetBridgePanelState();
}

class _ToonflowAssetBridgePanelState extends State<ToonflowAssetBridgePanel> {
  final ToonflowAssetBridge _bridge = ToonflowAssetBridge.instance;
  final ToonflowComposeService _engine = ToonflowComposeService.instance;
  final StudioProjectManager _manager = StudioProjectManager.instance;

  List<StudioSeries> _series = const [];
  List<StudioEpisode> _episodes = const [];
  String? _seriesId;
  String? _episodeId;

  bool _loadingSeries = true;
  bool _loadingEpisodes = false;
  bool _exporting = false;
  bool _scanning = false;
  bool _importing = false;

  /// 扫描到的候选视频，值为工作区内的绝对路径。
  List<String> _candidates = const [];
  final Set<String> _picked = <String>{};

  /// 归集目标：片段级进 `segments/`，分镜级进 `clips/`。
  bool _targetIsSegment = true;

  ExportResult? _lastExport;
  ImportResult? _lastImport;
  String? _error;

  /// 本次面板生命周期内导出发生的时刻。null 表示还没导出过。
  ///
  /// spec 说扫描范围是「本次导出后新增或修改的视频」。写死一个时间窗（如
  /// 「最近 10 分钟」）会在两种情况下出错：用户隔天回来归集，成品全被漏掉；
  /// 用户同时开着两个工作区，别处的旧文件又被误列进来。用导出时刻作界桩，
  /// 「本次」才有确定含义。
  ///
  /// 还没导出过时用会话开始时刻兜底：用户可能上一轮在 Toonflow 里生成了
  /// 视频，这一轮打开面板直接想归集。
  late DateTime _exportedAt;

  @override
  void initState() {
    super.initState();
    _exportedAt = DateTime.now();
    _engine.addListener(_onEngineChanged);
    _loadSeries();
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngineChanged);
    super.dispose();
  }

  void _onEngineChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSeries() async {
    setState(() => _loadingSeries = true);
    try {
      final list = await _manager.listSeries();
      if (!mounted) return;
      setState(() {
        _series = list;
        _loadingSeries = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingSeries = false;
        _error = '读取剧集库失败：$e';
      });
    }
  }

  Future<void> _loadEpisodes(String seriesId) async {
    setState(() => _loadingEpisodes = true);
    try {
      final list = await _manager.listEpisodes(seriesId);
      if (!mounted) return;
      setState(() {
        _episodes = list;
        _loadingEpisodes = false;
        // 换剧集就丢掉上一剧集的扫描结果——路径属于旧工作区。
        _candidates = const [];
        _picked.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingEpisodes = false;
        _error = '读取集列表失败：$e';
      });
    }
  }

  Future<void> _export() async {
    final seriesId = _seriesId;
    final episodeId = _episodeId;
    // 双保险：按钮本应已禁用，这里仍要拦住（spec: 未选择集时不猜测目标）。
    if (seriesId == null || episodeId == null) {
      setState(() => _error = '请先选择要导出的剧集与集');
      return;
    }
    setState(() {
      _exporting = true;
      _error = null;
      _lastExport = null;
      _lastImport = null;
    });
    final result = await _bridge.export(seriesId: seriesId, episodeId: episodeId);
    if (!mounted) return;
    setState(() {
      _exporting = false;
      _lastExport = result;
      if (result.ok) _exportedAt = DateTime.now();
      if (!result.ok) _error = result.error;
    });
  }

  Future<void> _scan() async {
    final seriesId = _seriesId;
    final episodeId = _episodeId;
    if (seriesId == null || episodeId == null) {
      setState(() => _error = '请先选择要归集到的剧集与集');
      return;
    }
    setState(() {
      _scanning = true;
      _error = null;
      _lastImport = null;
    });
    // 界桩取「本面板最后一次成功导出的时刻」：更早的文件多半已经归集过。
    final found =
        await _bridge.scanNewVideos(seriesId: seriesId, since: _exportedAt);
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _candidates = found;
      _picked
        ..clear()
        ..addAll(found);
    });
  }

  Future<void> _import() async {
    final seriesId = _seriesId;
    final episodeId = _episodeId;
    if (seriesId == null || episodeId == null) {
      setState(() => _error = '请先选择要归集到的剧集与集');
      return;
    }
    final chosen = _candidates.where(_picked.contains).toList();
    if (chosen.isEmpty) {
      setState(() => _error = '请先勾选要归集的视频');
      return;
    }
    setState(() {
      _importing = true;
      _error = null;
    });
    final result = await _bridge.importVideos(
      seriesId: seriesId,
      episodeId: episodeId,
      sourcePaths: chosen,
      targetIsSegment: _targetIsSegment,
    );
    if (!mounted) return;
    setState(() {
      _importing = false;
      _lastImport = result;
      if (!result.ok) _error = result.error;
      // 归集成功后清空候选，避免同一次扫描被重复导入。
      if (result.ok) {
        _candidates = const [];
        _picked.clear();
      }
    });
  }

  bool get _hasTarget => _seriesId != null && _episodeId != null;
  bool get _containerReady => _engine.state.status == ToonflowStatus.running;
  bool get _busy => _exporting || _scanning || _importing;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionHeader(title: '资产桥'),
          const SizedBox(height: AppTheme.space8),
          Text(
            '把工坊的剧本、角色与场景送进 Toonflow 工作台，再把生成的视频取回'
            '当前集。创作过程仍在 Toonflow 内完成。',
            style: TextStyle(color: context.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: AppTheme.space12),
          if (!_containerReady) ...[
            AppBanner(
              message: '容器未运行。请先在上方启动 Toonflow，否则导出的工作区'
                  '无法在工作台里打开。',
              type: AppBannerType.warning,
            ),
            const SizedBox(height: AppTheme.space12),
          ],
          _buildPickers(),
          const SizedBox(height: AppTheme.space16),
          _buildExportSection(),
          const SizedBox(height: AppTheme.space16),
          _buildImportSection(),
          if (_error != null) ...[
            const SizedBox(height: AppTheme.space12),
            AppBanner(message: _error!, type: AppBannerType.error),
          ],
          if (_lastExport != null && _lastExport!.ok) ...[
            const SizedBox(height: AppTheme.space12),
            _buildExportReport(_lastExport!),
          ],
          if (_lastImport != null && _lastImport!.ok) ...[
            const SizedBox(height: AppTheme.space12),
            AppBanner(
              message: '已归集 ${_lastImport!.imported.length} 个视频到'
                  '${_targetIsSegment ? 'segments' : 'clips'}/',
              type: AppBannerType.success,
            ),
            if (_lastImport!.unassigned.isNotEmpty) ...[
              const SizedBox(height: AppTheme.space8),
              // 视频比片段多时必须说清，否则用户以为那几个也进了剧集数据。
              AppBanner(
                message: '有 ${_lastImport!.unassigned.length} 个视频没有对应'
                    '片段可写，已复制到目录但未关联到分镜：'
                    '${_lastImport!.unassigned.join('、')}',
                type: AppBannerType.warning,
              ),
            ],
          ],
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  Widget _buildPickers() {
    if (_loadingSeries) {
      return const Padding(
        padding: EdgeInsets.all(AppTheme.space12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_series.isEmpty) {
      return AppBanner(
        message: '剧集库是空的。请先在「AI 短视频工坊」里创建剧集。',
        type: AppBannerType.info,
      );
    }

    final validSeries = _series.any((s) => s.id == _seriesId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Dropdown<String>(
          label: '剧集',
          value: validSeries ? _seriesId : null,
          items: _series
              .map((s) => DropdownMenuItem(
                    value: s.id,
                    child: Text(s.name, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (v) {
            setState(() {
              _seriesId = v;
              _episodeId = null;
              _episodes = const [];
            });
            if (v != null) _loadEpisodes(v);
          },
        ),
        const SizedBox(height: AppTheme.space8),
        _Dropdown<String>(
          label: '集',
          value: _episodes.any((e) => e.id == _episodeId) ? _episodeId : null,
          items: _episodes
              .map((e) => DropdownMenuItem(
                    value: e.id,
                    child: Text('第 ${e.index} 集 ${e.title}',
                        overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          hint: _loadingEpisodes
              ? '加载中…'
              : (_episodes.isEmpty ? '该剧集还没有集' : '请选择'),
          onChanged: (v) => setState(() => _episodeId = v),
        ),
        if (!_hasTarget) ...[
          const SizedBox(height: AppTheme.space8),
          Text(
            '未选中集时无法导出或归集——本工具不猜测目标集。',
            style: TextStyle(color: context.textTertiary, fontSize: 11),
          ),
        ],
      ],
    );
  }

  Widget _buildExportSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppSectionHeader(title: '导出到 Toonflow'),
        const SizedBox(height: AppTheme.space8),
        Text(
          '导出本集大纲、世界观与风格词、分镜表、角色卡与场景卡（含参考图）。',
          style: TextStyle(color: context.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: AppTheme.space12),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton.primary(
            label: _exporting ? '导出中…' : '导出',
            icon: Icons.upload_outlined,
            // 没选中目标集，或容器没跑，都不给导（spec: 未选择集时不猜测目标）。
            onPressed: (_busy || !_hasTarget || !_containerReady)
                ? null
                : _export,
          ),
        ),
      ],
    );
  }

  Widget _buildImportSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppSectionHeader(title: '从 Toonflow 归集'),
        const SizedBox(height: AppTheme.space8),
        Text(
          '扫描工作区内新生成的视频，勾选后复制到当前集。Toonflow 侧的原文件'
          '保持不动。',
          style: TextStyle(color: context.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: AppTheme.space8),
        Row(
          children: [
            AppSwitch(
              value: _targetIsSegment,
              onChanged: (v) => setState(() => _targetIsSegment = v),
            ),
            const SizedBox(width: AppTheme.space8),
            Expanded(
              child: Text(
                _targetIsSegment
                    ? '归集为片段（segments/）'
                    : '归集为分镜片段（clips/）',
                style: TextStyle(color: context.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.space12),
        Wrap(
          spacing: AppTheme.space8,
          runSpacing: AppTheme.space8,
          children: [
            AppButton.secondary(
              label: _scanning ? '扫描中…' : '扫描新视频',
              icon: Icons.refresh,
              onPressed:
                  (_busy || !_hasTarget || !_containerReady) ? null : _scan,
            ),
            AppButton.primary(
              label: _importing ? '归集中…' : '归集选中',
              icon: Icons.download_outlined,
              onPressed: (_busy ||
                      !_hasTarget ||
                      !_containerReady ||
                      _candidates.isEmpty ||
                      _picked.isEmpty)
                  ? null
                  : _import,
            ),
          ],
        ),
        if (_candidates.isNotEmpty) ...[
          const SizedBox(height: AppTheme.space12),
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              border: Border.all(color: context.borderSubtle),
              borderRadius: AppTheme.borderRadiusSmall,
            ),
            child: ListView(
              shrinkWrap: true,
              children: _candidates.map(_candidateRow).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _candidateRow(String path) {
    final file = File(path);
    final name = path.split('/').last;
    String size = '';
    try {
      final bytes = file.lengthSync();
      size = '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    } catch (_) {
      // 文件可能刚被外部移走；大小缺失不该让整行报错。
    }
    return CheckboxListTile(
      value: _picked.contains(path),
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(name, style: const TextStyle(fontSize: 12)),
      subtitle: size.isEmpty
          ? null
          : Text(size, style: TextStyle(color: context.textTertiary, fontSize: 11)),
      onChanged: (v) {
        setState(() {
          if (v == true) {
            _picked.add(path);
          } else {
            _picked.remove(path);
          }
        });
      },
    );
  }

  /// 导出结果报告。
  ///
  /// spec 要求报告里**明确说明没做什么**——用户看到"已写入 5 个文件"会以为
  /// 漫剧已经在生成了，必须让他知道连线与生成还在他这边。
  ///
  /// 抽成顶层小部件而不是私有方法：spec 的这条要求（"导出结果 SHALL 说明…
  /// 需要用户在 Toonflow 内完成连线与生成"）必须能被测试直接渲染，走完整
  /// 导出流程才能验它的话，这条断言会永远躺在"没测"的那一档。
  Widget _buildExportReport(ExportResult result) {
    return ExportReportCard(result: result);
  }
}

/// 导出成功后的结果报告（spec: 写画布内容的权限边界）。
class ExportReportCard extends StatelessWidget {
  const ExportReportCard({super.key, required this.result});

  final ExportResult result;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.space12),
      decoration: BoxDecoration(
        color: context.successText.withValues(alpha: 0.08),
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline,
                  size: 16, color: context.successText),
              const SizedBox(width: AppTheme.space8),
              Expanded(
                child: Text(
                  '已写入 ${result.writtenFiles.length} 个文件',
                  style: context.fontBody,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space8),
          Text(
            '工作区目录：${result.workspaceDir}',
            style: TextStyle(color: context.textTertiary, fontSize: 11),
          ),
          const SizedBox(height: AppTheme.space8),
          // 权限边界必须出现在结果里，而不是只存在于文档（spec）。
          Text(
            '已写入内容节点与参考素材，但未创建任何连线、未触发生成。'
            '请在 Toonflow 工作台内打开该工作区，用它的 Agent 完成连线与生成。',
            style: TextStyle(color: context.textSecondary, fontSize: 11),
          ),
          if (result.skippedNotes.isNotEmpty) ...[
            const SizedBox(height: AppTheme.space8),
            ...result.skippedNotes.map(
              (note) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '· $note',
                  style: TextStyle(color: context.textTertiary, fontSize: 11),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 贴主题的下拉框。项目里已有同样的内联写法（分镜看板、工坊设置），这里收成
/// 一个小部件避免资产桥面板里重复三份。
class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: context.textTertiary, fontSize: 11)),
        const SizedBox(height: AppTheme.space4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.space12),
          decoration: BoxDecoration(
            color: context.bgInput,
            borderRadius: AppTheme.borderRadiusSmall,
            border: Border.all(color: context.borderSubtle),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              hint: Text(
                hint ?? '请选择',
                style: TextStyle(color: context.textTertiary, fontSize: 12),
              ),
              dropdownColor: context.bgCard,
              style: TextStyle(color: context.textPrimary, fontSize: 12),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
