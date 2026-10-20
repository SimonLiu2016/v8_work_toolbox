import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/theme/app_theme.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/asset_library.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/ui/asset_library_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AssetLibraryPage Action Handlers and Export Tests', () {
    late Directory tempDir;
    late Directory sourceDir;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('asset_lib_ui_test');
      AppPaths.overrideRootForTesting(tempDir);
      AssetLibrary.instance.resetForTesting();
      sourceDir = Directory(p.join(tempDir.path, 'src'))..createSync(recursive: true);
    });

    tearDown(() {
      AssetLibrary.instance.resetForTesting();
      AppPaths.resetForTesting();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    Future<File> makeSource(String name, int bytes) async {
      final f = File(p.join(sourceDir.path, name));
      if (name.endsWith('.png')) {
        await f.writeAsBytes(base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='));
      } else {
        await f.writeAsBytes(List<int>.filled(bytes, 42));
      }
      return f;
    }

    Future<void> pumpUntilLoaded(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      }
      await tester.pump();
    }

    Future<void> pumpAssetLibrary(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: AssetLibraryPage(session: null)),
        ),
      );
      await pumpUntilLoaded(tester);
    }

    testWidgets('渲染资产卡片，包含查看、访达、导出及删除按钮', (tester) async {
      late StudioAsset asset;
      await tester.runAsync(() async {
        final src = await makeSource('shot_1.png', 1024);
        asset = await AssetLibrary.instance.addAsset(
          src,
          kind: AssetKind.image,
          prompt: '测试资产卡片提示词',
        );
      });

      await pumpAssetLibrary(tester);

      expect(find.text(asset.id), findsOneWidget);
      expect(find.text('测试资产卡片提示词'), findsOneWidget);
      expect(find.byTooltip('查看大图'), findsOneWidget);
      expect(find.byTooltip('在访达中显示'), findsOneWidget);
      expect(find.byTooltip('导出到本地...'), findsOneWidget);
      expect(find.byTooltip('删除'), findsOneWidget);
    });

    testWidgets('点击查看大图弹出带有 InteractiveViewer 的 Lightbox', (tester) async {
      late StudioAsset asset;
      await tester.runAsync(() async {
        final src = await makeSource('shot_zoom.png', 1024);
        asset = await AssetLibrary.instance.addAsset(
          src,
          kind: AssetKind.image,
          prompt: '放大查看测试',
        );
      });

      await pumpAssetLibrary(tester);

      // 点击卡片上的查看大图按钮
      await tester.tap(find.byTooltip('查看大图'));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();

      // Lightbox 弹窗中应包含 InteractiveViewer
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text(asset.id), findsWidgets);
      expect(find.byTooltip('用系统应用打开'), findsOneWidget);
      expect(find.byTooltip('关闭'), findsOneWidget);

      // 点击关闭弹窗
      await tester.tap(find.byTooltip('关闭'));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(find.byType(InteractiveViewer), findsNothing);
    });

    testWidgets('视频资产卡片提供播放视频按钮', (tester) async {
      late StudioAsset asset;
      await tester.runAsync(() async {
        final src = await makeSource('clip_1.mp4', 2048);
        asset = await AssetLibrary.instance.addAsset(
          src,
          kind: AssetKind.clip,
          prompt: '视频片段测试',
          durationSec: 5,
        );
      });

      await pumpAssetLibrary(tester);

      // 切换到视频片段页签
      await tester.tap(find.text('视频片段'));
      await pumpUntilLoaded(tester);

      expect(find.text(asset.id), findsOneWidget);
      expect(find.byTooltip('播放视频'), findsOneWidget);
    });

    test('资产文件导出到目标路径时保持完整复制', () async {
      final src = await makeSource('export_test.bin', 2048);
      final asset = await AssetLibrary.instance.addAsset(src, kind: AssetKind.image);

      final exportDest = File(p.join(tempDir.path, 'exported_file.bin'));
      expect(exportDest.existsSync(), isFalse);

      await asset.file.copy(exportDest.path);

      expect(exportDest.existsSync(), isTrue);
      expect(await exportDest.length(), 2048);
      expect(await exportDest.readAsBytes(), await asset.file.readAsBytes());
    });
  });
}
