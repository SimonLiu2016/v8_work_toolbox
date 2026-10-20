import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import '../models/studio_models.dart';

/// 虚拟相机参数配置。
class CameraPerspectiveParams {
  /// 水平视场角（单位：度，推荐 105° 用于电影级超广角完整画幅，90° 用于标准广角，60° 用于标准中景，35° 用于特写）。
  final double fovDegrees;

  /// 偏航角（单位：度，0° 正面, 180° 反打, 90° 右侧, 270° 左侧）。
  final double yawDegrees;

  /// 俯仰角（单位：度，0° 平视, >0 仰视, <0 俯视）。
  final double pitchDegrees;

  /// 输出图像宽度。
  final int outputWidth;

  /// 输出图像高度。
  final int outputHeight;

  const CameraPerspectiveParams({
    this.fovDegrees = 105.0,
    required this.yawDegrees,
    this.pitchDegrees = 0.0,
    this.outputWidth = 1920,
    this.outputHeight = 1080,
  });

  /// 目标宽高比。
  double get aspectRatio => outputWidth / (outputHeight > 0 ? outputHeight : 1);
}

/// 批量切片任务输入包。
class BatchSliceRequest {
  final String panoramaPath;
  final String outputDir;
  final int outputWidth;
  final int outputHeight;
  final double fovDegrees;
  final double yawOffset;
  final double pitchOffset;
  final List<SceneDirection> directions;

  const BatchSliceRequest({
    required this.panoramaPath,
    required this.outputDir,
    this.outputWidth = 1920,
    this.outputHeight = 1080,
    this.fovDegrees = 105.0,
    this.yawOffset = 0.0,
    this.pitchOffset = 0.0,
    this.directions = const [
      SceneDirection.front,
      SceneDirection.back,
      SceneDirection.left,
      SceneDirection.right,
    ],
  });
}

/// 批量切片产物结果映射。
class BatchSliceResult {
  final Map<SceneDirection, String> slicedFilePaths;
  final int elapsedMilliseconds;

  const BatchSliceResult({
    required this.slicedFilePaths,
    required this.elapsedMilliseconds,
  });
}

/// 基于球面几何与逆向光线投射的纯 Dart 全景透视切片投影引擎。
class SphericalPerspectiveSlicer {
  SphericalPerspectiveSlicer._();

  /// 将偏航角映射至 SceneDirection 标准朝向。
  static double getYawForDirection(SceneDirection dir) {
    switch (dir) {
      case SceneDirection.front:
        return 0.0;
      case SceneDirection.right:
        return 90.0;
      case SceneDirection.back:
        return 180.0;
      case SceneDirection.left:
        return 270.0;
      case SceneDirection.topDown:
      case SceneDirection.top:
      case SceneDirection.bottom:
        return 0.0;
    }
  }

  /// 将俯仰角映射至 SceneDirection 标准朝向。
  static double getPitchForDirection(SceneDirection dir) {
    switch (dir) {
      case SceneDirection.top:
        return 45.0;
      case SceneDirection.bottom:
        return -45.0;
      case SceneDirection.topDown:
        return -35.0;
      default:
        return 0.0;
    }
  }

  /// 在单独 Isolate 中执行一键并发切片处理。
  static Future<BatchSliceResult> sliceBatchAsync(BatchSliceRequest request) async {
    return await compute(_executeBatchSlice, request);
  }

  /// 单张切片处理：从全景母图切出单一视角透视图像。
  static Future<File> sliceSingleAsync({
    required String panoramaPath,
    required String outputPath,
    required CameraPerspectiveParams params,
  }) async {
    return await compute(
      _executeSingleSlice,
      _SingleSliceJob(
        panoramaPath: panoramaPath,
        outputPath: outputPath,
        params: params,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 核心图形学光线投射与插值算法
  // ---------------------------------------------------------------------------

  static File _executeSingleSlice(_SingleSliceJob job) {
    final panoFile = File(job.panoramaPath);
    if (!panoFile.existsSync()) {
      throw ArgumentError('全景母图文件不存在: ${job.panoramaPath}');
    }
    final panoBytes = panoFile.readAsBytesSync();
    final panoImage = img.decodeImage(panoBytes);
    if (panoImage == null) {
      throw StateError('无法解码全景图: ${job.panoramaPath}');
    }

    final outImage = renderPerspectiveView(panoImage, job.params);
    final outFile = File(job.outputPath);
    outFile.parent.createSync(recursive: true);
    outFile.writeAsBytesSync(img.encodePng(outImage));
    return outFile;
  }

  static BatchSliceResult _executeBatchSlice(BatchSliceRequest request) {
    final sw = Stopwatch()..start();
    final panoFile = File(request.panoramaPath);
    if (!panoFile.existsSync()) {
      throw ArgumentError('全景母图文件不存在: ${request.panoramaPath}');
    }
    final panoBytes = panoFile.readAsBytesSync();
    final panoImage = img.decodeImage(panoBytes);
    if (panoImage == null) {
      throw StateError('无法解码全景图: ${request.panoramaPath}');
    }

    final outDir = Directory(request.outputDir);
    outDir.createSync(recursive: true);

    final results = <SceneDirection, String>{};
    final timestamp = DateTime.now().microsecondsSinceEpoch;

    for (final dir in request.directions) {
      final baseYaw = getYawForDirection(dir);
      final calibratedYaw = ((baseYaw + request.yawOffset) % 360.0 + 360.0) % 360.0;
      final basePitch = getPitchForDirection(dir);
      final calibratedPitch = (basePitch + request.pitchOffset).clamp(-85.0, 85.0);
      final params = CameraPerspectiveParams(
        fovDegrees: request.fovDegrees,
        yawDegrees: calibratedYaw,
        pitchDegrees: calibratedPitch,
        outputWidth: request.outputWidth,
        outputHeight: request.outputHeight,
      );

      final slicedImage = renderPerspectiveView(panoImage, params);
      final fileName = 'spatial_${dir.key}_slice_$timestamp.png';
      final destFile = File(p.join(outDir.path, fileName));
      destFile.writeAsBytesSync(img.encodePng(slicedImage));
      results[dir] = destFile.path;
    }

    sw.stop();
    return BatchSliceResult(
      slicedFilePaths: results,
      elapsedMilliseconds: sw.elapsedMilliseconds,
    );
  }

  /// 核心投影渲染：将等矩全景母图渲染为透视相机视口位图。
  static img.Image renderPerspectiveView(
    img.Image panoImage,
    CameraPerspectiveParams params,
  ) {
    final int inW = panoImage.width;
    final int inH = panoImage.height;
    final int outW = params.outputWidth;
    final int outH = params.outputHeight;

    final outImage = img.Image(width: outW, height: outH, numChannels: 4);

    final double fovXRad = params.fovDegrees * (math.pi / 180.0);
    final double halfTanFovX = math.tan(fovXRad / 2.0);
    final double halfTanFovY = halfTanFovX * (outH / outW.toDouble());

    final double yawRad = params.yawDegrees * (math.pi / 180.0);
    final double pitchRad = params.pitchDegrees * (math.pi / 180.0);

    final double cosYaw = math.cos(yawRad);
    final double sinYaw = math.sin(yawRad);
    final double cosPitch = math.cos(pitchRad);
    final double sinPitch = math.sin(pitchRad);

    // 像素角增量：横向等矩跨度 2π 弧度对应 inW 像素
    final double radToPixel = inW / (2.0 * math.pi);
    final double halfInH = (inH - 1.0) / 2.0;

    for (int y = 0; y < outH; y++) {
      final double ny = (1.0 - (2.0 * (y + 0.5)) / outH) * halfTanFovY;

      // 绕 X 轴旋转 (Pitch)
      final double y1 = ny * cosPitch - sinPitch;
      final double z1 = ny * sinPitch + cosPitch;

      for (int x = 0; x < outW; x++) {
        final double nx = ((2.0 * (x + 0.5)) / outW - 1.0) * halfTanFovX;

        // 绕 Y 轴旋转 (Yaw)
        final double rx = nx * cosYaw + z1 * sinYaw;
        final double ry = y1;
        final double rz = -nx * sinYaw + z1 * cosYaw;

        // 归一化三维向量
        final double norm = math.sqrt(rx * rx + ry * ry + rz * rz);
        final double dx = rx / norm;
        final double dy = ry / norm;
        final double dz = rz / norm;

        // 极坐标转换
        final double lon = math.atan2(dx, dz); // -π ~ +π
        final double lat = math.asin(dy.clamp(-1.0, 1.0)); // -π/2 ~ +π/2

        // 映射至等矩图像素坐标 (地平线位于高度正中，消除21:9垂直拉伸)
        final double u = (lon / (2.0 * math.pi) + 0.5) * (inW - 1.0);
        final double v = halfInH - lat * radToPixel;

        // 双线性插值采样取色并直接写入输出画布
        _sampleAndSetBilinear(panoImage, outImage, x, y, u, v, inW, inH);
      }
    }

    // 施加轻量级自适应边缘锐化滤波（Unsharp Masking），消除双线性插值高频衰减，提升建筑边缘清晰度
    final sharpened = img.convolution(
      outImage,
      filter: const [0, -1, 0, -1, 5, -1, 0, -1, 0],
      amount: 0.3,
    );

    // 增强对比度与饱和度，提升切片画面细节质感与清晰透通度
    final enhanced = img.adjustColor(sharpened, contrast: 1.05, saturation: 1.02);
    return enhanced;
  }

  /// 双线性插值采样取色并设置到目标图像。
  static void _sampleAndSetBilinear(
    img.Image srcImage,
    img.Image dstImage,
    int dstX,
    int dstY,
    double u,
    double v,
    int width,
    int height,
  ) {
    int u0 = u.floor();
    int v0 = v.floor();
    final double fracU = u - u0;
    final double fracV = v - v0;

    // 水平环绕 (Seamless Wrap)
    u0 = ((u0 % width) + width) % width;
    final int u1 = (u0 + 1) % width;

    // 垂直 clamp
    v0 = v0.clamp(0, height - 1);
    final int v1 = (v0 + 1).clamp(0, height - 1);

    final p00 = srcImage.getPixel(u0, v0);
    final p10 = srcImage.getPixel(u1, v0);
    final p01 = srcImage.getPixel(u0, v1);
    final p11 = srcImage.getPixel(u1, v1);

    final double w00 = (1.0 - fracU) * (1.0 - fracV);
    final double w10 = fracU * (1.0 - fracV);
    final double w01 = (1.0 - fracU) * fracV;
    final double w11 = fracU * fracV;

    final num r = p00.r * w00 + p10.r * w10 + p01.r * w01 + p11.r * w11;
    final num g = p00.g * w00 + p10.g * w10 + p01.g * w01 + p11.g * w11;
    final num b = p00.b * w00 + p10.b * w10 + p01.b * w01 + p11.b * w11;
    final num a = p00.a * w00 + p10.a * w10 + p01.a * w01 + p11.a * w11;

    dstImage.setPixelRgba(dstX, dstY, r, g, b, a);
  }
}

class _SingleSliceJob {
  final String panoramaPath;
  final String outputPath;
  final CameraPerspectiveParams params;

  _SingleSliceJob({
    required this.panoramaPath,
    required this.outputPath,
    required this.params,
  });
}
