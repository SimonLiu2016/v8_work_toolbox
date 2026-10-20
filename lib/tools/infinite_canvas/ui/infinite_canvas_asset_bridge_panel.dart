import 'package:flutter/material.dart';

import '../../../components/app_components.dart';
import '../../../theme/app_theme.dart';
import '../services/infinite_canvas_asset_bridge.dart';
import '../services/infinite_canvas_bridge_models.dart';
import '../services/infinite_canvas_bridge_server.dart';

/// 资产桥面板（spec: 资产桥的传输通道 / 导回的推送与归集）。
///
/// **只做状态与报告**（design D11）：剧集下拉与「导入」动作都在画布侧的插件
/// 面板里，V8 侧再放一份就是两个真相来源。这里负责显示服务状态、待归集的
/// 视频清单，以及把暂存文件消化进剧集数据。
class InfiniteCanvasAssetBridgePanel extends StatefulWidget {
  const InfiniteCanvasAssetBridgePanel({super.key});

  @override
  State<InfiniteCanvasAssetBridgePanel> createState() =>
      _InfiniteCanvasAssetBridgePanelState();
}

class _InfiniteCanvasAssetBridgePanelState
    extends State<InfiniteCanvasAssetBridgePanel> {
  final InfiniteCanvasBridgeServer _bridge = InfiniteCanvasBridgeServer.instance;

  bool _targetIsSegment = true;
  bool _busy = false;
  String? _report;

  @override
  void initState() {
    super.initState();
    _bridge.addListener(_onChanged);
  }

  @override
  void dispose() {
    _bridge.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _collect() async {
    final staged = List<StagedVideo>.of(_bridge.staged);
    if (staged.isEmpty) return;
    setState(() {
      _busy = true;
      _report = null;
    });

    final inputs = staged
        .map(
          (e) => StagedVideoInput(
            fileName: e.fileName,
            seriesId: e.seriesId,
            episodeId: e.episodeId,
            bytes: e.bytes,
            targetIsSegment: _targetIsSegment,
          ),
        )
        .toList();

    try {
      final results = await InfiniteCanvasAssetBridge.instance.drainStaged(
        staged: inputs,
      );
      if (!mounted) return;
      final lines = <String>[];
      for (final r in results) {
        final result = r.result;
        if (!result.ok) {
          lines.add('${r.episodeId}：失败（${result.error ?? '未知'}）');
          continue;
        }
        lines.add('${r.episodeId}：归集 ${result.imported.length} 个文件');
        if (result.unassigned.isNotEmpty) {
          lines.add('  未配对：${result.unassigned.join('、')}');
        }
      }
      setState(() {
        _report = lines.join('\n');
        _busy = false;
      });
      // 只有全部成功才清空队列——失败的留着让用户重试。
      final allOk = results.every((r) => r.result.ok);
      if (allOk) _bridge.staged.clear();
      _onChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _report = '归集失败：$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionHeader(title: '资产桥'),
          const SizedBox(height: AppTheme.space8),
          _InfoLine(
            label: '服务',
            value: _bridge.isRunning
                ? '运行中（127.0.0.1:${_bridge.port}）'
                : '未运行',
            valueColor: _bridge.isRunning ? context.successText : context.textSecondary,
          ),
          _InfoLine(
            label: '插件',
            value: _bridge.lastHandshakeAt != null ? '已连接' : '未检测到连接',
            valueColor: _bridge.lastHandshakeAt != null
                ? context.successText
                : context.textTertiary,
          ),
          if (_bridge.lastError != null) ...[
            const SizedBox(height: AppTheme.space4),
            Text(
              _bridge.lastError!,
              style: TextStyle(color: context.errorText, fontSize: 11),
            ),
          ],
          const SizedBox(height: AppTheme.space12),
          Text(
            '导入到画布请在无限画布的插件面板里操作；这里负责把画布上归集回来'
            '的成片写进剧集数据。',
            style: context.fontBodySecondary,
          ),
          const SizedBox(height: AppTheme.space12),
          Row(
            children: [
              AppSwitch(
                value: _targetIsSegment,
                onChanged: _busy ? null : (v) => setState(() => _targetIsSegment = v),
              ),
              const SizedBox(width: AppTheme.space8),
              Expanded(
                child: Text(
                  _targetIsSegment ? '写入片段级成片' : '写入分镜级成片',
                  style: TextStyle(color: context.textSecondary, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space12),
          if (_bridge.staged.isEmpty)
            Text(
              '暂无待归集的视频',
              style: TextStyle(color: context.textTertiary, fontSize: 12),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in _bridge.staged)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.movie_outlined,
                          size: 14,
                          color: context.textTertiary,
                        ),
                        const SizedBox(width: AppTheme.space8),
                        Expanded(
                          child: Text(
                            item.fileName,
                            style: context.fontCaption,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${(item.bytes / 1024 / 1024).toStringAsFixed(1)} MB',
                          style: TextStyle(
                            color: context.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppTheme.space8),
                Align(
                  alignment: Alignment.centerRight,
                  child: AppButton.primary(
                    label: _busy ? '归集中…' : '归集到工坊',
                    icon: Icons.download_outlined,
                    onPressed: _busy ? null : _collect,
                  ),
                ),
              ],
            ),
          if (_report != null) ...[
            const SizedBox(height: AppTheme.space12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.textTertiary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                _report!,
                style: AppTheme.fontCaption,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 一行「标签 - 值」信息。
class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(color: context.textTertiary, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? context.textPrimary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
