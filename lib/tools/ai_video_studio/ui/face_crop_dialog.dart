import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../../theme/app_theme.dart';

/// 交互式 1:1 正方形视窗面部特写裁剪对话框。
///
/// 遵循 iOS / 微信头像裁剪交互：
/// - 中央固定 1:1 正方形取景框与半透明遮罩；
/// - 底图通过 [InteractiveViewer] 自由拖拽平移与滚轮/滑块缩放；
/// - 自动根据三视图排版进行初始面部中心吸附；
/// - 点击确认后，通过反向几何变换矩阵计算精确像素选区并毫秒级生成 1:1 图片。
class FaceCropDialog extends StatefulWidget {
  const FaceCropDialog({
    super.key,
    required this.imageFile,
    this.title = '从三视图截取面部特写锚点',
  });

  final File imageFile;
  final String title;

  /// 便捷静态唤起方法，返回裁剪后的 [img.Image]，取消返回 null。
  static Future<img.Image?> show(
    BuildContext context, {
    required File imageFile,
    String title = '从三视图截取面部特写锚点',
  }) {
    return showDialog<img.Image?>(
      context: context,
      barrierColor: Colors.black87,
      barrierDismissible: false,
      builder: (_) => FaceCropDialog(
        imageFile: imageFile,
        title: title,
      ),
    );
  }

  @override
  State<FaceCropDialog> createState() => _FaceCropDialogState();
}

class _FaceCropDialogState extends State<FaceCropDialog> {
  final TransformationController _transformController =
      TransformationController();

  Uint8List? _rawBytes;
  img.Image? _decodedImage;
  bool _loading = true;
  String? _error;

  static const double _viewportSize = 420.0;
  static const double _cropFrameSize = 260.0;

  double _currentScale = 1.0;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    try {
      if (!await widget.imageFile.exists()) {
        throw StateError('源图片文件不存在');
      }
      final bytes = await widget.imageFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw const FormatException('无法解析图片数据');
      }
      if (!mounted) return;
      setState(() {
        _rawBytes = bytes;
        _decodedImage = decoded;
        _loading = false;
      });

      _initSmartAlignment(decoded.width, decoded.height);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// 智能对准三视图正面人脸区域：
  /// 标准三视图中，正视图位于左侧 1/3（X 约 17%），头部位于上部（Y 约 13%）。
  void _initSmartAlignment(int imgW, int imgH) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cx = _viewportSize / 2.0;
      final cy = _viewportSize / 2.0;

      // 估算目标头部在底图上的中心
      final isLandscapeTurnaround = (imgW > imgH * 1.3);
      final isPortraitTurnaround = (imgH > imgW * 1.3);

      final double targetCenterX;
      final double targetCenterY;
      final double headEstimatedWidth;

      if (isLandscapeTurnaround) {
        // 横屏 16:9 三视图：正视图位于最左侧 1/3 (X 约 17%)，立绘全身站立，头部位于顶部 (Y 约 20%)
        targetCenterX = imgW * 0.17;
        targetCenterY = imgH * 0.20;
        headEstimatedWidth = imgH * 0.20;
      } else if (isPortraitTurnaround) {
        // 竖屏 9:16 三视图：正视图位于左侧 1/3 (X 约 17%)，立绘纵向拉长，头部位于顶部 (Y 约 13%)
        targetCenterX = imgW * 0.17;
        targetCenterY = imgH * 0.13;
        headEstimatedWidth = imgW * 0.22;
      } else {
        // 单人头像或常规参考图：头部位于居中偏上位置
        targetCenterX = imgW * 0.5;
        targetCenterY = imgH * 0.35;
        headEstimatedWidth = imgW * 0.45;
      }

      final double initialScale = (_cropFrameSize / headEstimatedWidth).clamp(0.1, 8.0);

      final double tx = cx - targetCenterX * initialScale;
      final double ty = cy - targetCenterY * initialScale;

      // ignore: deprecated_member_use
      final matrix = Matrix4.identity()
        // ignore: deprecated_member_use
        ..translate(tx, ty)
        // ignore: deprecated_member_use
        ..scale(initialScale);

      _transformController.value = matrix;
      setState(() {
        _currentScale = initialScale;
      });
    });
  }

  void _onScaleChanged(double newScale) {
    final currentMatrix = _transformController.value;
    final scale = currentMatrix.getMaxScaleOnAxis();
    if (scale <= 0) return;

    final factor = newScale / scale;
    final cx = _viewportSize / 2.0;
    final cy = _viewportSize / 2.0;

    // 以取景框中心为原点进行缩放
    // ignore: deprecated_member_use
    final newMatrix = Matrix4.identity()
      // ignore: deprecated_member_use
      ..translate(cx, cy)
      // ignore: deprecated_member_use
      ..scale(factor)
      // ignore: deprecated_member_use
      ..translate(-cx, -cy)
      ..multiply(currentMatrix);

    _transformController.value = newMatrix;
    setState(() {
      _currentScale = newScale;
    });
  }

  void _resetView() {
    if (_decodedImage != null) {
      _initSmartAlignment(_decodedImage!.width, _decodedImage!.height);
    }
  }

  /// 计算反向几何变换并执行精确像素裁切
  void _onConfirm() {
    final image = _decodedImage;
    if (image == null) return;

    final frameLeft = (_viewportSize - _cropFrameSize) / 2.0;
    final frameTop = (_viewportSize - _cropFrameSize) / 2.0;

    // 使用 InteractiveViewer 官方原生 toScene 进行高保真反向像素映射
    final pTopLeft = _transformController.toScene(Offset(frameLeft, frameTop));
    final pBottomRight = _transformController.toScene(
      Offset(frameLeft + _cropFrameSize, frameTop + _cropFrameSize),
    );

    final left = min(pTopLeft.dx, pBottomRight.dx).round();
    final top = min(pTopLeft.dy, pBottomRight.dy).round();
    final right = max(pTopLeft.dx, pBottomRight.dx).round();
    final bottom = max(pTopLeft.dy, pBottomRight.dy).round();
    final rawSize = min(right - left, bottom - top);

    final safeX = left.clamp(0, image.width - 1);
    final safeY = top.clamp(0, image.height - 1);
    final maxAvailable = min(image.width - safeX, image.height - safeY);
    final cropSize = rawSize.clamp(10, maxAvailable);

    final cropped = img.copyCrop(
      image,
      x: safeX,
      y: safeY,
      width: cropSize,
      height: cropSize,
    );

    // 保留 100% 原生无损超清像素，绝不进行下采样有损压缩
    Navigator.of(context).pop(cropped);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.crop, color: Colors.amber, size: 22),
                const SizedBox(width: 8),
                Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(null),
                  tooltip: '取消',
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '在正方形取景框内拖拽底图平移、滚轮缩放，框选出人物正面头部（发顶、五官、下巴），彻底阻断服装深色外溢。',
              style: TextStyle(fontSize: 12, color: context.textSecondary),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const SizedBox(
                height: _viewportSize,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              SizedBox(
                height: _viewportSize,
                child: Center(
                  child: Text('加载失败: $_error',
                      style: TextStyle(color: context.errorText)),
                ),
              )
            else
              Center(
                child: Container(
                  width: _viewportSize,
                  height: _viewportSize,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.borderSubtle),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      InteractiveViewer(
                        transformationController: _transformController,
                        constrained: false,
                        minScale: 0.1,
                        maxScale: 8.0,
                        boundaryMargin: const EdgeInsets.all(double.infinity),
                        onInteractionUpdate: (_) {
                          final scale = _transformController.value
                              .getMaxScaleOnAxis();
                          if (scale > 0 && mounted) {
                            setState(() {
                              _currentScale = scale;
                            });
                          }
                        },
                        child: SizedBox(
                          width: _decodedImage!.width.toDouble(),
                          height: _decodedImage!.height.toDouble(),
                          child: Image.memory(
                            _rawBytes!,
                            fit: BoxFit.fill,
                          ),
                        ),
                      ),
                      IgnorePointer(
                        child: CustomPaint(
                          size: const Size(_viewportSize, _viewportSize),
                          painter: _CropOverlayPainter(
                            viewportSize: _viewportSize,
                            cropFrameSize: _cropFrameSize,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.zoom_out, size: 18),
                Expanded(
                  child: Slider(
                    value: _currentScale.clamp(0.1, 8.0),
                    min: 0.1,
                    max: 8.0,
                    activeColor: Colors.amber,
                    onChanged: _loading ? null : _onScaleChanged,
                  ),
                ),
                const Icon(Icons.zoom_in, size: 18),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _loading ? null : _resetView,
                  icon: const Icon(Icons.center_focus_strong, size: 16),
                  label: const Text('重置中心', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _loading || _error != null ? null : _onConfirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.amber.shade700,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('确认截取为面部特写'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 绘制取景框与半透明遮罩
class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter({
    required this.viewportSize,
    required this.cropFrameSize,
  });

  final double viewportSize;
  final double cropFrameSize;

  @override
  void paint(Canvas canvas, Size size) {
    final frameLeft = (viewportSize - cropFrameSize) / 2.0;
    final frameTop = (viewportSize - cropFrameSize) / 2.0;
    final frameRect = Rect.fromLTWH(
      frameLeft,
      frameTop,
      cropFrameSize,
      cropFrameSize,
    );

    // 绘制外部半透明遮罩
    final overlayPaint = Paint()
      ..color = Colors.black.withAlpha(160)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(frameRect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, overlayPaint);

    // 绘制金色取景框边框
    final borderPaint = Paint()
      ..color = Colors.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRect(frameRect, borderPaint);

    // 绘制三分法则网格参考线
    final gridPaint = Paint()
      ..color = Colors.white.withAlpha(50)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final step = cropFrameSize / 3.0;
    for (int i = 1; i <= 2; i++) {
      final x = frameLeft + step * i;
      final y = frameTop + step * i;
      canvas.drawLine(
        Offset(x, frameTop),
        Offset(x, frameTop + cropFrameSize),
        gridPaint,
      );
      canvas.drawLine(
        Offset(frameLeft, y),
        Offset(frameLeft + cropFrameSize, y),
        gridPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) =>
      oldDelegate.viewportSize != viewportSize ||
      oldDelegate.cropFrameSize != cropFrameSize;
}
