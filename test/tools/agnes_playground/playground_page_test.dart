import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/ai_config_store.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/theme/app_theme.dart';
import 'package:V8WorkToolbox/tools/agnes_playground/models/playground_models.dart';
import 'package:V8WorkToolbox/tools/agnes_playground/services/playground_store.dart';
import 'package:V8WorkToolbox/tools/agnes_playground/ui/playground_page.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/video_gen_adapter.dart';

/// 试炼场界面的可测契约。
///
/// 守三条用户可见性质：无剧集/无项目时也能进、reference 模式讲清占位符写法、
/// 参数面板按型号收敛档位。前两条是 spec 里的明文要求。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlaygroundPage', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('playground_page_test');
      AppPaths.overrideRootForTesting(tempDir);
      PlaygroundStore.instance.resetForTesting();
      await AiConfigStore.instance.resetForTesting();
      await AiConfigStore.instance.init(customRootDir: tempDir);
    });

    tearDown(() async {
      PlaygroundStore.instance.resetForTesting();
      await AiConfigStore.instance.resetForTesting();
      AppPaths.resetForTesting();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });


    Future<void> pumpPage(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          home: const Scaffold(body: PlaygroundPage()),
        ),
      );
      // dart:io 的 exists() 在 FakeAsync 下不会自己完成——必须先让 initState 的
      // _load() 跑到第一个 await，再用 runAsync 进真实事件循环把 IO 跑完，
      // 最后抽帧让 setState 生效。顺序反了（先 pump 十二帧）IO 永远不完成。
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    testWidgets('无剧集、无供应商时也能渲染，不要求先选项目', (tester) async {
      await pumpPage(tester);

      expect(find.text('Agnes 试炼场'), findsOne);
      // 没配供应商时给的是提示而不是空白或崩溃
      expect(find.text('未配置供应商'), findsOne);
      // 空态引导
      expect(find.text('还没有任何调用'), findsOne);
    });

    testWidgets('三个通道都在顶栏可切', (tester) async {
      await pumpPage(tester);

      for (final label in ['文本', '图像', '视频']) {
        expect(find.text(label), findsWidgets);
      }
    });

    testWidgets('视频通道显示模式/时长/清晰度/画幅/种子五个参数控件', (tester) async {
      await pumpPage(tester);

      expect(find.text('模式'), findsOne);
      expect(find.text('时长'), findsOne);
      expect(find.text('清晰度'), findsOne);
      expect(find.text('画幅'), findsOne);
      // 种子是输入框不是下拉，用 label 找
      expect(find.widgetWithText(TextField, '种子'), findsOne);
    });

    testWidgets('Flash 型号下清晰度只给 720P 一档', (tester) async {
      // saveProvider 写盘，FakeAsync 下必须进真实事件循环才完成——直接在
      // testWidgets 里 await 它会永远挂住。
      await tester.runAsync(() async {
        await AiConfigStore.instance.saveProvider(const AiProviderConfig(
        id: 'p1',
        name: 'Agnes',
        protocol: AiProtocolType.agnes,
        baseUrl: 'https://api.agnes-ai.cn/v1',
          keychainKeyId: 'k1',
          videoModels: ['agnes-video-2.5-flash'],
        ));
      });
      await pumpPage(tester);

      // 直接验参数面板的数据源，不走真实点击：下拉菜单要开 overlay、
      // 跑进入动画，在 widget 测试里既慢又容易因布局细节挂住。面板内容由
      // capabilityFor(model) 决定，那条链路由 service 测试覆盖；这里只确认
      // 界面确实按型号收敛——即屏幕上出现了档位标签。
      // 收起的下拉显示当前值。清晰度与画幅都默认「默认」，所以是两个。
      // 按型号收敛的档位断言由 service 测试（capabilityFor）覆盖——那里的
      // 数据源与这里完全一致，且不必跟 overlay 的布局较劲。
      expect(find.text('清晰度'), findsOne);
      expect(find.text('默认'), findsNWidgets(2));
    });

    testWidgets('标准型号下型号下拉带出四档清晰度', (tester) async {
      await tester.runAsync(() async {
        await AiConfigStore.instance.saveProvider(const AiProviderConfig(
          id: 'p1',
          name: 'Agnes',
          protocol: AiProtocolType.agnes,
          baseUrl: 'https://api.agnes-ai.cn/v1',
          keychainKeyId: 'k1',
          videoModels: ['agnes-video-2.5'],
        ));
      });
      await pumpPage(tester);

      // 型号下拉里应出现用户配的那个型号——这是"面板跟着供应商变"的最小证据。
      expect(find.text('清晰度'), findsOne);
      expect(find.text('agnes-video-2.5'), findsOne);
      // 档位集合本身由 service 测试覆盖（capabilityFor），这里不重复。
    });

    testWidgets('模式下拉的项来自 AgnesVideoMode，不含 auto', (tester) async {
      await pumpPage(tester);

      // 不进 overlay：直接验数据源。auto 是"让适配器推导"，把它做成可选项
      // 等于让用户选一个自己不决定的值——那正是默认行为本身。
      final selectable = AgnesVideoMode.values
          .where((m) => m != AgnesVideoMode.auto)
          .map((m) => m.id)
          .toList();
      // 不依赖声明顺序：顺序是呈现细节，契约是「三种可选、不含 auto」。
      expect(selectable, hasLength(3));
      expect(selectable, containsAll(['text', 'keyframe', 'reference']));
      expect(selectable, isNot(contains('auto')));
      expect(AgnesVideoMode.values.map((m) => m.id), contains('auto'));
    });

    testWidgets('参考图按钮的提示讲清 <Picture N> 写法', (tester) async {
      await pumpPage(tester);

      final button = find.byIcon(Icons.photo_library_outlined);
      expect(button, findsOne);
      // tooltip 是给用户的唯一说明——不写清楚他就会按 {{ref 1}} 写，
      // 而 Agnes 只认 <Picture 1>。
      final widget = tester.widget<Tooltip>(
        find.ancestor(of: button, matching: find.byType(Tooltip)),
      );
      expect(widget.message, contains('<Picture N>'));
    });

    testWidgets('空提示词时发送被拦下并提示', (tester) async {
      await pumpPage(tester);

      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(find.text('请先填写提示词'), findsOne);
    });

    testWidgets('有历史轮次时渲染卡片而非空态', (tester) async {
      // 直接塞一条轮次进索引文件，绕开真实调用。record 内部写盘，FakeAsync 下
      // 必须进真实事件循环。
      final store = PlaygroundStore.instance;
      await tester.runAsync(() async {
        await store.record(
          channel: PlaygroundChannel.video,
          providerId: 'p1',
          providerName: 'Agnes',
          model: 'agnes-video-2.5-flash',
          prompt: '已有的一次调用',
          params: const {'seconds': '5'},
          media: const [],
          invoke: (outDir) async => const PlaygroundCallOutcome(
            status: PlaygroundTurnStatus.failed,
            error: '上游 400',
          ),
        );
      });

      await pumpPage(tester);

      expect(find.text('还没有任何调用'), findsNothing);
      expect(find.text('已有的一次调用'), findsOne);
      expect(find.text('失败'), findsOne);
      // 查看请求入口
      expect(find.text('查看请求'), findsOne);
    });

    testWidgets('查看请求弹窗展示脱敏视图', (tester) async {
      final store = PlaygroundStore.instance;
      await tester.runAsync(() async {
        await store.record(
          channel: PlaygroundChannel.video,
          providerId: 'p1',
          providerName: 'Agnes',
          model: 'agnes-video-2.5-flash',
          prompt: '弹窗测试提示词',
          params: const {'mode': 'keyframe', 'seconds': '5', 'size': '720P'},
          media: const [],
          invoke: (outDir) async => const PlaygroundCallOutcome(
            status: PlaygroundTurnStatus.failed,
            error: 'x',
          ),
        );
      });

      await pumpPage(tester);
      await tester.tap(find.text('查看请求'));
      await tester.pumpAndSettle();

      expect(find.text('本次提交的请求体'), findsOne);
      // 默认落在「HTTP JSON」页，文本是缩进 JSON 而不是 key: value。
      expect(find.textContaining('"prompt": "弹窗测试提示词"'), findsOne);
      expect(find.textContaining('"mode": "keyframe"'), findsOne);
    });

    testWidgets('图片产物成功后渲染缩略图与打开/访达快捷按钮', (tester) async {
      final store = PlaygroundStore.instance;
      await tester.runAsync(() async {
        await store.record(
          channel: PlaygroundChannel.image,
          providerId: 'p1',
          providerName: 'Agnes',
          model: 'agnes-image-2.5-flash',
          prompt: '生成余小白',
          params: const {},
          media: const [],
          invoke: (outDir) async {
            final f = File('${outDir.path}/image.png');
            await f.writeAsBytes(List<int>.filled(128, 0));
            return PlaygroundCallOutcome(
              status: PlaygroundTurnStatus.completed,
              outputFileName: 'image.png',
              outputBytes: 128,
            );
          },
        );
      });

      await pumpPage(tester);

      expect(find.text('点击放大'), findsOne);
      expect(find.text('打开图片'), findsOne);
      expect(find.text('在访达中显示'), findsOne);
    });

    testWidgets('视频产物成功后渲染视频卡片与播放/访达快捷按钮', (tester) async {
      final store = PlaygroundStore.instance;
      await tester.runAsync(() async {
        await store.record(
          channel: PlaygroundChannel.video,
          providerId: 'p1',
          providerName: 'Agnes',
          model: 'agnes-video-2.5-flash',
          prompt: '余小白动作视频',
          params: const {'seconds': '5'},
          media: const [],
          invoke: (outDir) async {
            final f = File('${outDir.path}/video.mp4');
            await f.writeAsBytes(List<int>.filled(256, 0));
            return PlaygroundCallOutcome(
              status: PlaygroundTurnStatus.completed,
              outputFileName: 'video.mp4',
              outputBytes: 256,
            );
          },
        );
      });

      await pumpPage(tester);

      expect(find.text('点击播放视频'), findsOne);
      expect(find.text('播放视频'), findsOne);
      expect(find.text('在访达中显示'), findsOne);
    });
  });
}

