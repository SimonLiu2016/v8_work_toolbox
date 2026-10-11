import 'package:flutter/material.dart';

import '../../../components/app_components.dart';
import '../../../theme/app_theme.dart';

/// 构建 / 容器日志查看器（task 8.4）。
///
/// 构建与容器日志复用同一个视图：两者都是「一行行追加的文本」，且都需要
/// 自动滚到底部。构建期间 [ArtexLogViewer.building] 为 true 时显示等待态。
class ArtexLogViewer extends StatefulWidget {
  const ArtexLogViewer({
    super.key,
    required this.lines,
    this.title = '日志',
    this.busy = false,
    this.emptyHint = '暂无日志',
  });

  final List<String> lines;
  final String title;

  /// 进行中：显示「等待更多输出」提示，但不阻断查看已有内容。
  final bool busy;

  final String emptyHint;

  @override
  State<ArtexLogViewer> createState() => _ArtexLogViewerState();
}

class _ArtexLogViewerState extends State<ArtexLogViewer> {
  final ScrollController _controller = ScrollController();
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final atBottom =
        _controller.position.pixels >= _controller.position.maxScrollExtent - 24;
    if (atBottom != _autoScroll) {
      setState(() => _autoScroll = atBottom);
    }
  }

  @override
  void didUpdateWidget(ArtexLogViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_autoScroll && widget.lines.length != oldWidget.lines.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_controller.hasClients) return;
        _controller.jumpTo(_controller.position.maxScrollExtent);
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(
          title: widget.title,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_autoScroll)
                AppButton(
                  label: '回到底部',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.small,
                  onPressed: () {
                    if (_controller.hasClients) {
                      _controller.jumpTo(_controller.position.maxScrollExtent);
                    }
                  },
                ),
              if (widget.busy) ...[
                const SizedBox(width: AppTheme.space8),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: AppTheme.space8),
                Text('进行中', style: context.fontCaption),
              ],
            ],
          ),
        ),
        Expanded(
          child: AppCard(
            padding: const EdgeInsets.all(AppTheme.space12),
            child: widget.lines.isEmpty
                ? Center(
                    child: Text(
                      widget.busy ? '等待输出…' : widget.emptyHint,
                      style: context.fontCaption,
                    ),
                  )
                : SelectionArea(
                    child: SingleChildScrollView(
                      controller: _controller,
                      child: Text(
                        widget.lines.join('\n'),
                        style: AppTheme.fontCaption.copyWith(
                          fontFamily: 'Menlo',
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
