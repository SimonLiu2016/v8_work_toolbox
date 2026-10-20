import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../theme/app_theme.dart';
import '../models/studio_models.dart';
import '../services/spherical_perspective_slicer.dart';
import '../services/studio_project_manager.dart';

/// 360° 沉浸式 3D 全景空间漫游与相机校准视口对话框。
class Panorama3dViewerDialog extends StatefulWidget {
  final File panoramaFile;
  final SceneCard scene;
  final String seriesId;
  final double initialYawOffset;
  final double initialFov;
  final double initialPitch;
  final ValueChanged<double>? onYawOffsetChanged;
  final void Function(double yaw, double pitch, double fov)? onBaselineChanged;
  final VoidCallback? onReSliceRequested;
  final ValueChanged<String>? onSnapshotSaved;

  const Panorama3dViewerDialog({
    super.key,
    required this.panoramaFile,
    required this.scene,
    required this.seriesId,
    this.initialYawOffset = 0.0,
    this.initialFov = 105.0,
    this.initialPitch = 0.0,
    this.onYawOffsetChanged,
    this.onBaselineChanged,
    this.onReSliceRequested,
    this.onSnapshotSaved,
  });

  static Future<void> show(
    BuildContext context, {
    required File panoramaFile,
    required SceneCard scene,
    required String seriesId,
    double initialYawOffset = 0.0,
    double initialFov = 105.0,
    double initialPitch = 0.0,
    ValueChanged<double>? onYawOffsetChanged,
    void Function(double yaw, double pitch, double fov)? onBaselineChanged,
    VoidCallback? onReSliceRequested,
    ValueChanged<String>? onSnapshotSaved,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Panorama3dViewerDialog(
          panoramaFile: panoramaFile,
          scene: scene,
          seriesId: seriesId,
          initialYawOffset: initialYawOffset,
          initialFov: initialFov,
          initialPitch: initialPitch,
          onYawOffsetChanged: onYawOffsetChanged,
          onBaselineChanged: onBaselineChanged,
          onReSliceRequested: onReSliceRequested,
          onSnapshotSaved: onSnapshotSaved,
        ),
      ),
    );
  }

  @override
  State<Panorama3dViewerDialog> createState() => _Panorama3dViewerDialogState();
}

class _Panorama3dViewerDialogState extends State<Panorama3dViewerDialog> {
  late double _yaw;
  late double _pitch;
  late double _fov;

  img.Image? _fullPanoImage;
  img.Image? _fastPreviewPano;
  Uint8List? _viewportImageBytes;
  bool _loading = true;
  bool _isInteracting = false;
  Timer? _renderDebounce;

  @override
  void initState() {
    super.initState();
    _yaw = widget.initialYawOffset;
    _pitch = widget.initialPitch;
    _fov = widget.initialFov;
    _loadPanorama();
  }

  @override
  void dispose() {
    _renderDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadPanorama() async {
    try {
      final bytes = await widget.panoramaFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw Exception('无法解码全景图');

      _fullPanoImage = decoded;
      // 构建轻量快速预览图 (宽度 1280)，保证 60fps 流畅手势拖拽
      _fastPreviewPano = img.copyResize(decoded, width: 1280);

      _renderViewportFrame(fast: false);
    } catch (e) {
      debugPrint('[Panorama3dViewerDialog] 加载失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _renderViewportFrame({required bool fast}) {
    final src = fast ? (_fastPreviewPano ?? _fullPanoImage) : _fullPanoImage;
    if (src == null) return;

    final outW = fast ? 640 : 1280;
    final outH = fast ? 360 : 720;

    final frame = SphericalPerspectiveSlicer.renderPerspectiveView(
      src,
      CameraPerspectiveParams(
        fovDegrees: _fov,
        yawDegrees: _yaw,
        pitchDegrees: _pitch,
        outputWidth: outW,
        outputHeight: outH,
      ),
    );

    final pngBytes = Uint8List.fromList(img.encodePng(frame));
    if (mounted) {
      setState(() {
        _viewportImageBytes = pngBytes;
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _isInteracting = true;
      _yaw = ((_yaw - details.delta.dx * 0.35) % 360.0 + 360.0) % 360.0;
      _pitch = (_pitch + details.delta.dy * 0.35).clamp(-75.0, 75.0);
    });

    _renderViewportFrame(fast: true);

    _renderDebounce?.cancel();
    _renderDebounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) {
        _isInteracting = false;
        _renderViewportFrame(fast: false);
      }
    });
  }

  void _onPointerScroll(PointerScrollEvent event) {
    setState(() {
      _fov = (_fov + event.scrollDelta.dy * 0.05).clamp(45.0, 115.0);
    });

    _renderDebounce?.cancel();
    _renderDebounce = Timer(const Duration(milliseconds: 80), () {
      if (mounted) {
        _renderViewportFrame(fast: false);
      }
    });
  }

  void _jumpToRelativeAngle(double relativeYaw) {
    final base = widget.scene.panoramaYawOffset;
    setState(() {
      _yaw = ((base + relativeYaw) % 360.0 + 360.0) % 360.0;
      _pitch = widget.scene.panoramaPitchOffset;
    });
    _renderViewportFrame(fast: false);
  }

  /// 将当前视口角度、俯仰与视场设为正面主景基准并自动持久化。
  Future<void> _setAsFrontBaseline() async {
    final manager = StudioProjectManager.instance;
    final updated = widget.scene.copyWith(
      panoramaYawOffset: _yaw,
      panoramaFov: _fov,
      panoramaPitchOffset: _pitch,
    );
    await manager.saveScene(widget.seriesId, updated);

    widget.onBaselineChanged?.call(_yaw, _pitch, _fov);
    widget.onYawOffsetChanged?.call(_yaw);
    widget.onReSliceRequested?.call();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已将当前角度 (${_yaw.toStringAsFixed(1)}°)、俯仰 (${_pitch.toStringAsFixed(1)}°)、视场 (${_fov.toStringAsFixed(0)}°) 设为正面基准，四向机位已自动对齐重切！',
          ),
        ),
      );
    }
  }

  /// 截取当前 3D 视口所见画面并存为分镜场景参考图。
  Future<void> _takeSnapshot() async {
    if (_fullPanoImage == null) return;
    try {
      final manager = StudioProjectManager.instance;
      final sceneDir = manager.sceneDir(widget.seriesId, widget.scene.id);
      final refsDir = Directory(p.join(sceneDir.path, 'references'));
      await refsDir.create(recursive: true);

      final fileName = 'snapshot_${DateTime.now().microsecondsSinceEpoch}.png';
      final file = File(p.join(refsDir.path, fileName));

      final highResFrame = SphericalPerspectiveSlicer.renderPerspectiveView(
        _fullPanoImage!,
        CameraPerspectiveParams(
          fovDegrees: _fov,
          yawDegrees: _yaw,
          pitchDegrees: _pitch,
          outputWidth: 1920,
          outputHeight: 1080,
        ),
      );

      await file.writeAsBytes(img.encodePng(highResFrame));
      final relPath = p.join('references', fileName);

      final newRefs = List<String>.from(widget.scene.referenceImages);
      if (!newRefs.contains(relPath)) {
        newRefs.insert(0, relPath);
      }
      final updated = widget.scene.copyWith(referenceImages: newRefs);
      await manager.saveScene(widget.seriesId, updated);

      widget.onSnapshotSaved?.call(relPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已将当前相机视口截帧存入场景参考图库！')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('截帧失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1080,
      height: 720,
      decoration: BoxDecoration(
        color: context.bgContent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderSubtle),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 20, spreadRadius: 4),
        ],
      ),
      child: Column(
        children: [
          // 顶部栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: context.bgCard,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: context.borderSubtle)),
            ),
            child: Row(
              children: [
                Icon(Icons.panorama_photosphere, color: context.accentText, size: 20),
                const SizedBox(width: 8),
                Text(
                  '360° 空间全景 3D 沉浸漫游视口 - ${widget.scene.name}',
                  style: TextStyle(color: context.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.accentSubtle,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '按住鼠标左键 360° 拖拽环顾 · 鼠标滚轮缩放焦距',
                    style: TextStyle(color: context.accentText, fontSize: 11),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: '关闭',
                ),
              ],
            ),
          ),
          // 核心 3D 视口画布
          Expanded(
            child: Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  _onPointerScroll(event);
                }
              },
              child: GestureDetector(
                onPanUpdate: _onPanUpdate,
                child: Container(
                  color: Colors.black,
                  alignment: Alignment.center,
                  child: _loading
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: context.accentText),
                            const SizedBox(height: 12),
                            Text('正在加载 4K 空间立体全景…', style: TextStyle(color: context.textTertiary, fontSize: 13)),
                          ],
                        )
                      : (_viewportImageBytes != null
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.memory(
                                  _viewportImageBytes!,
                                  fit: BoxFit.contain,
                                  gaplessPlayback: true,
                                ),
                                // 居中轻量十字准星 (取景辅助线)
                                Center(
                                  child: Opacity(
                                    opacity: _isInteracting ? 0.6 : 0.25,
                                    child: Icon(Icons.center_focus_weak, size: 36, color: context.accentText),
                                  ),
                                ),
                                // 左上角机位实时物理参数展示
                                Positioned(
                                  top: 14,
                                  left: 14,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withAlpha(180),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.white24),
                                    ),
                                    child: Text(
                                      '偏航(Yaw): ${_yaw.toStringAsFixed(1)}°  |  俯仰(Pitch): ${_pitch.toStringAsFixed(1)}°  |  焦距(FOV): ${_fov.toStringAsFixed(0)}°',
                                      style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : const Text('无法渲染视口')),
                ),
              ),
            ),
          ),
          // 底部控制与机位校准操作栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: context.bgCard,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              border: Border(top: BorderSide(color: context.borderSubtle)),
            ),
            child: Row(
              children: [
                Text('快速视角跳转: ', style: TextStyle(color: context.textTertiary, fontSize: 12)),
                const SizedBox(width: 6),
                _quickAngleButton('正面 (0°)', 0.0),
                const SizedBox(width: 4),
                _quickAngleButton('反打 (180°)', 180.0),
                const SizedBox(width: 4),
                _quickAngleButton('左视 (270°)', 270.0),
                const SizedBox(width: 4),
                _quickAngleButton('右视 (90°)', 90.0),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _loading ? null : _setAsFrontBaseline,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.gps_fixed, size: 15),
                  label: const Text('🎯 设为正面主景基准 (重切)'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _takeSnapshot,
                  icon: const Icon(Icons.camera_alt_outlined, size: 15),
                  label: const Text('📷 截取当前视角为分镜参考'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickAngleButton(String label, double relYaw) {
    return InkWell(
      onTap: () => _jumpToRelativeAngle(relYaw),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: context.bgInput,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: context.borderSubtle),
        ),
        child: Text(label, style: TextStyle(color: context.textPrimary, fontSize: 11)),
      ),
    );
  }
}
