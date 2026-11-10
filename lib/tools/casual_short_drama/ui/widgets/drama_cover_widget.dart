import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../services/drama_cover_decryptor.dart';

/// 短剧封面异步解密海报组件
class DramaCoverWidget extends StatefulWidget {
  final String? coverUrl;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final BoxFit fit;

  const DramaCoverWidget({
    super.key,
    required this.coverUrl,
    this.width,
    this.height,
    this.borderRadius,
    this.fit = BoxFit.cover,
  });

  @override
  State<DramaCoverWidget> createState() => _DramaCoverWidgetState();
}

class _DramaCoverWidgetState extends State<DramaCoverWidget> {
  Uint8List? _bytes;
  bool _isLoading = true;
  String? _lastUrl;

  @override
  void initState() {
    super.initState();
    _loadCover();
  }

  @override
  void didUpdateWidget(covariant DramaCoverWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverUrl != widget.coverUrl) {
      _loadCover();
    }
  }

  Future<void> _loadCover() async {
    final url = widget.coverUrl;
    _lastUrl = url;
    if (url == null || url.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _bytes = null;
          _isLoading = false;
        });
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final bytes = await DramaCoverDecryptor.instance.getCoverBytes(url);
    if (!mounted || _lastUrl != url) return;

    setState(() {
      _bytes = bytes;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(8);
    final theme = Theme.of(context);

    Widget content;
    if (_bytes != null && _bytes!.isNotEmpty) {
      content = Image.memory(
        _bytes!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(theme),
      );
    } else if (_isLoading) {
      content = Container(
        width: widget.width,
        height: widget.height,
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary.withValues(alpha: 0.6),
            ),
          ),
        ),
      );
    } else {
      content = _buildPlaceholder(theme);
    }

    return ClipRRect(
      borderRadius: radius,
      child: content,
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      width: widget.width,
      height: widget.height,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.movie_creation_outlined,
          size: 28,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
