import 'dart:io';
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../services/thumbnail_manager.dart';

/// 统一的媒体卡片/列表视频缩略图展示组件（支持自动本地缓存与异步帧提取）
class MediaThumbnailWidget extends StatefulWidget {
  final String? thumbnailPath;
  final String? videoPathOrUrl;
  final bool isOnline;
  final double width;
  final double height;
  final double borderRadius;
  final Widget? overlay;

  const MediaThumbnailWidget({
    super.key,
    this.thumbnailPath,
    this.videoPathOrUrl,
    this.isOnline = false,
    this.width = 64,
    this.height = 44,
    this.borderRadius = 6,
    this.overlay,
  });

  @override
  State<MediaThumbnailWidget> createState() => _MediaThumbnailWidgetState();
}

class _MediaThumbnailWidgetState extends State<MediaThumbnailWidget> {
  String? _resolvedPath;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _resolveThumbnail();
  }

  @override
  void didUpdateWidget(covariant MediaThumbnailWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thumbnailPath != widget.thumbnailPath ||
        oldWidget.videoPathOrUrl != widget.videoPathOrUrl) {
      _resolveThumbnail();
    }
  }

  Future<void> _resolveThumbnail() async {
    final direct = widget.thumbnailPath;
    if (direct != null && direct.isNotEmpty && File(direct).existsSync()) {
      setState(() => _resolvedPath = direct);
      return;
    }

    final target = widget.videoPathOrUrl;
    if (target == null || target.isEmpty) return;

    setState(() => _isLoading = true);

    final localPath = await ThumbnailManager.instance.getOrCreateThumbnail(
      target,
      remoteThumbnailUrl: (direct != null && direct.startsWith('http')) ? direct : null,
    );

    if (mounted) {
      setState(() {
        _resolvedPath = localPath;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;

    if (_resolvedPath != null && File(_resolvedPath!).existsSync()) {
      content = Image.file(
        File(_resolvedPath!),
        width: widget.width,
        height: widget.height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallback(),
      );
    } else if (widget.thumbnailPath != null && widget.thumbnailPath!.startsWith('http')) {
      content = Image.network(
        widget.thumbnailPath!,
        width: widget.width,
        height: widget.height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallback(),
      );
    } else if (_isLoading) {
      content = Container(
        width: widget.width,
        height: widget.height,
        color: AppTheme.bgCard,
        child: const Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.accent),
          ),
        ),
      );
    } else {
      content = _buildFallback();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Container(
        width: widget.width,
        height: widget.height,
        color: AppTheme.bgCard,
        child: Stack(
          fit: StackFit.expand,
          children: [
            content,
            if (widget.overlay != null) widget.overlay!,
          ],
        ),
      ),
    );
  }

  Widget _buildFallback() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: AppTheme.bgCard,
      child: Center(
        child: Icon(
          widget.isOnline ? Icons.public_rounded : Icons.video_file_rounded,
          color: AppTheme.accent.withValues(alpha: 0.7),
          size: widget.height * 0.45,
        ),
      ),
    );
  }
}
