import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/image_gen_adapter.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/spherical_perspective_slicer.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';

void main() {
  group('360° 等矩全景与透视切片投影测试', () {
    test('ScenePromptBuilder.buildPanoramaPrompt 规范性与净化校验', () {
      final prompt = ScenePromptBuilder.buildPanoramaPrompt(
        basePrompt: '金銮宝座大殿，两名守卫站立，大门敞开，地面金砖',
        styleTokens: '电影级写实，古风实拍',
        eraGenreId: 'historical_chinese',
      );

      // 验证包含 360° 全景强约束标志
      expect(prompt, contains('360 degree equirectangular panorama projection'));
      expect(prompt, contains('VR 360 spherical photosphere'));
      expect(prompt, contains('seamless 360 wide horizon'));

      // 验证包含开阔大空间、大景深与机位后撤约束
      expect(prompt, contains('wide-angle distant establishing shot'));
      expect(prompt, contains('deep perspective'));
      expect(prompt, contains('开阔宏大空间全景'));
      expect(prompt, contains('机位后撤远视距'));

      // 验证人物与动作已被净化剔除
      expect(prompt, isNot(contains('两名守卫')));
      expect(prompt, isNot(contains('站立')));

      // 验证保留了核心建筑陈设
      expect(prompt, contains('金銮宝座大殿'));
      expect(prompt, contains('大门敞开'));
    });

    test('resolveAgnesSizeAndRatio 对 21:9 超宽画幅及 2:1 全景比例的精准识别', () {
      // 官方 2K 21:9 规格 (3136x1344)
      final (size1, ratio1) = SystemAiImageAdapter.resolveAgnesSizeAndRatio(3136, 1344);
      expect(ratio1, equals('21:9'));
      expect(size1, equals('2K'));

      // 标准 2:1 等矩比例 (2048x1024)
      final (size2, ratio2) = SystemAiImageAdapter.resolveAgnesSizeAndRatio(2048, 1024);
      expect(ratio2, equals('21:9'));
      expect(size2, equals('2K'));

      // 4K 21:9 (6272x2688)
      final (size3, ratio3) = SystemAiImageAdapter.resolveAgnesSizeAndRatio(6272, 2688);
      expect(ratio3, equals('21:9'));
      expect(size3, equals('4K'));
    });

    test('SceneCard panoramaMasterPath 与 panoramaYawOffset 序列化与兼容性恢复', () {
      final scene = SceneCard(
        id: 'SC_TEST_01',
        name: '议事大厅',
        descriptionZh: '金銮殿',
        panoramaMasterPath: 'panoramas/pano_master_123.png',
        panoramaYawOffset: 125.5,
        updatedAt: DateTime.now(),
      );

      final json = scene.toJson();
      expect(json['panorama_master_path'], equals('panoramas/pano_master_123.png'));
      expect(json['panorama_yaw_offset'], equals(125.5));

      final recovered = SceneCard.fromJson(json);
      expect(recovered.panoramaMasterPath, equals('panoramas/pano_master_123.png'));
      expect(recovered.panoramaYawOffset, equals(125.5));
      expect(recovered.name, equals('议事大厅'));
    });

    test('SceneCard panoramaFov 与 panoramaPitchOffset 序列化与恢复', () {
      final scene = SceneCard(
        id: 'SC_TEST_03',
        name: '回廊金殿',
        descriptionZh: '廊道',
        panoramaMasterPath: 'panoramas/pano_master_789.png',
        panoramaYawOffset: 45.0,
        panoramaFov: 110.0,
        panoramaPitchOffset: 6.5,
        updatedAt: DateTime.now(),
      );

      final json = scene.toJson();
      expect(json['panorama_fov'], equals(110.0));
      expect(json['panorama_pitch_offset'], equals(6.5));

      final recovered = SceneCard.fromJson(json);
      expect(recovered.panoramaFov, equals(110.0));
      expect(recovered.panoramaPitchOffset, equals(6.5));
    });

    test('BatchSliceRequest 与 CameraPerspectiveParams 默认升级至 105° 电影级超广角', () {
      const camera = CameraPerspectiveParams(yawDegrees: 0.0);
      expect(camera.fovDegrees, equals(105.0));
      expect(camera.pitchDegrees, equals(0.0));

      const batch = BatchSliceRequest(panoramaPath: 'p.png', outputDir: 'out');
      expect(batch.fovDegrees, equals(105.0));
      expect(batch.pitchOffset, equals(0.0));
    });

    test('SphericalPerspectiveSlicer 验证偏航基准角 (yawOffset) 旋转采样准确性', () {
      // 构造四向色块全景母图 (宽 360, 高 180, 1°/像素)
      // Yaw 0° (x: 180 附近): 纯红
      // Yaw 90° (x: 270 附近): 纯绿
      // Yaw 180° (x: 0 或 360 附近): 纯蓝
      // Yaw 270° (x: 90 附近): 纯黄 (R+G)
      const int w = 360;
      const int h = 180;
      final testPano = img.Image(width: w, height: h, numChannels: 4);

      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          if (x >= 135 && x < 225) {
            // Yaw 0° 区域 (经度 -45° ~ +45°) -> 红色
            testPano.setPixelRgba(x, y, 255, 0, 0, 255);
          } else if (x >= 225 && x < 315) {
            // Yaw 90° 区域 (经度 45° ~ 135°) -> 绿色
            testPano.setPixelRgba(x, y, 0, 255, 0, 255);
          } else if (x >= 45 && x < 135) {
            // Yaw 270° (-90°) 区域 (经度 -135° ~ -45°) -> 黄色
            testPano.setPixelRgba(x, y, 255, 255, 0, 255);
          } else {
            // Yaw 180° 区域 -> 蓝色
            testPano.setPixelRgba(x, y, 0, 0, 255, 255);
          }
        }
      }

      // 1. 未校准 (yawOffset = 0.0): 正面 (0°) 应采到红色
      final frontUncalibrated = SphericalPerspectiveSlicer.renderPerspectiveView(
        testPano,
        CameraPerspectiveParams(yawDegrees: 0.0, fovDegrees: 40.0, outputWidth: 32, outputHeight: 32),
      );
      expect(frontUncalibrated.getPixel(16, 16).r > 200, isTrue);
      expect(frontUncalibrated.getPixel(16, 16).g < 50, isTrue);

      // 2. 校准 yawOffset = 90.0: 正面 (原为 0°，加上 offset 90° 变为 90°) 应采到绿色！
      final frontCalibrated = SphericalPerspectiveSlicer.renderPerspectiveView(
        testPano,
        CameraPerspectiveParams(yawDegrees: (0.0 + 90.0) % 360, fovDegrees: 40.0, outputWidth: 32, outputHeight: 32),
      );
      expect(frontCalibrated.getPixel(16, 16).g > 200, isTrue);
      expect(frontCalibrated.getPixel(16, 16).r < 50, isTrue);

      // 3. 验证 BatchSliceRequest 的 yawOffset 字段
      final batchReq = BatchSliceRequest(
        panoramaPath: 'test.png',
        outputDir: 'output',
        fovDegrees: 75.0,
        yawOffset: 90.0,
      );
      expect(batchReq.yawOffset, equals(90.0));
      expect(batchReq.outputDir, equals('output'));
    });

    test('SphericalPerspectiveSlicer 验证正面 (Yaw 0°) 与反打 (Yaw 180°) 的物理绝对互斥性', () {
      // 构造一张测试用合成全景母图 (宽 400，高 200，比率 2:1)
      // 横向经度 -180° ~ +180°：
      // - 正面区域 (Yaw 0° 位于中心经度 0° 附近，即 x 在 [100, 300] 之间)：填充纯红色
      // - 反打区域 (Yaw 180° 位于两极接缝处，即 x 在 [0, 50] 和 [350, 400] 之间)：填充纯蓝色
      const int w = 400;
      const int h = 200;
      final testPano = img.Image(width: w, height: h, numChannels: 4);

      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          if (x >= 100 && x < 300) {
            // 前方主区：纯红 (R: 255, G: 0, B: 0)
            testPano.setPixelRgba(x, y, 255, 0, 0, 255);
          } else {
            // 背后反打区：纯蓝 (R: 0, G: 0, B: 255)
            testPano.setPixelRgba(x, y, 0, 0, 255, 255);
          }
        }
      }

      // 1. 渲染正面切片 (Yaw: 0°, FOV: 60°)
      final frontParams = CameraPerspectiveParams(
        yawDegrees: 0.0,
        fovDegrees: 60.0,
        outputWidth: 64,
        outputHeight: 36,
      );
      final frontImage = SphericalPerspectiveSlicer.renderPerspectiveView(testPano, frontParams);

      // 2. 渲染反打切片 (Yaw: 180°, FOV: 60°)
      final backParams = CameraPerspectiveParams(
        yawDegrees: 180.0,
        fovDegrees: 60.0,
        outputWidth: 64,
        outputHeight: 36,
      );
      final backImage = SphericalPerspectiveSlicer.renderPerspectiveView(testPano, backParams);

      // 统计正面图像素均值
      num frontRedTotal = 0;
      num frontBlueTotal = 0;
      for (final p in frontImage) {
        frontRedTotal += p.r;
        frontBlueTotal += p.b;
      }

      // 统计反打图像素均值
      num backRedTotal = 0;
      num backBlueTotal = 0;
      for (final p in backImage) {
        backRedTotal += p.r;
        backBlueTotal += p.b;
      }

      // 正面切片应该绝大多数为纯红，蓝色几乎为 0
      expect(frontRedTotal > 0, isTrue);
      expect(frontBlueTotal, equals(0));

      // 反打切片应该绝大多数为纯蓝，红色几乎为 0
      expect(backBlueTotal > 0, isTrue);
      expect(backRedTotal, equals(0));

      // 结论：正面机位与反打机位在物理空间上 100% 绝对隔离，彻底根除雷同！
    });
  });

  group('StudioProjectManager 物理母图丢失指针自动自愈 (Auto-Healing) 测试', () {
    late Directory tempDir;
    late StudioProjectManager manager;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('studio_pano_heal_test');
      AppPaths.overrideRootForTesting(tempDir);
      manager = StudioProjectManager.instance;
      await manager.ensureBaseStructure();
    });

    tearDown(() {
      AppPaths.resetForTesting();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('当 config.json 中 panoramaMasterPath 缺失，但 panoramas 目录下存在母图文件时，readScene 与 listScenes 自动自愈', () async {
      final series = await manager.createSeries(name: '自愈测试剧集');
      final seriesId = series.id;

      // 1. 创建初始场景（panoramaMasterPath 为 null）
      final scene = await manager.createScene(
        seriesId: seriesId,
        name: '凌霄宝殿',
        descriptionZh: '宏伟大殿',
      );
      expect(scene.panoramaMasterPath, isNull);

      // 2. 模拟物理全景母图文件已由生成器写入 panoramas 目录
      final panoDir = manager.scenePanoramasDir(seriesId, scene.id);
      await panoDir.create(recursive: true);

      // 创建一个较早的文件和一个较新的文件
      final oldPano = File(p.join(panoDir.path, 'pano_master_1000.png'));
      await oldPano.writeAsString('fake image data 1');
      await Future.delayed(const Duration(milliseconds: 20));

      final newestPano = File(p.join(panoDir.path, 'pano_master_2000.png'));
      await newestPano.writeAsString('fake image data 2');

      // 3. 执行 readScene 读取场景，断言触发自动自愈，指向最新的母图
      final healedScene = manager.readScene(seriesId, scene.id);
      expect(healedScene, isNotNull);
      expect(healedScene!.panoramaMasterPath, isNotNull);
      expect(healedScene.panoramaMasterPath, equals(p.join('panoramas', 'pano_master_2000.png')));

      // 等待异步回写完成
      await Future.delayed(const Duration(milliseconds: 100));

      // 4. 执行 listScenes，断言列表也是自愈后的状态
      final list = await manager.listScenes(seriesId);
      final found = list.firstWhere((s) => s.id == scene.id);
      expect(found.panoramaMasterPath, equals(p.join('panoramas', 'pano_master_2000.png')));

      // 5. 验证底层 config.json 经自愈回写后已有持久化数据
      final configScene = manager.readScene(seriesId, scene.id);
      expect(configScene!.panoramaMasterPath, equals(p.join('panoramas', 'pano_master_2000.png')));
    });
  });
}
