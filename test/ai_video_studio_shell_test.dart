import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/services/keychain_service.dart';
import 'test_keychain_bridge.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';
import 'package:V8WorkToolbox/theme/app_theme.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/ffmpeg_composer.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/ui/studio_shell.dart';

/// 让外壳的异步 bootstrap 跑完。
///
/// **必须用 `runAsync`。** `pump` 抽帧推进的是 Flutter 的 fake async zone，
/// `Directory.create` 这类真实 IO 的完成回调不会在里面跑——表现就是加载
/// 指示器永远转，`pump` 多少帧都停在 loading 分支。`runAsync` 把控制权交回
/// 真实 event loop，IO 完成后 `pump` 才看得到 `setState` 的结果。
/// 清掉全部剧集，让测试从「空工坊」开始。
///
/// 剧集是真实落盘的：上一个测试建的那部会漏到下一个测试里，「没有剧集时
/// 入口禁用」就是这么被破坏的。删目录是真实 IO，必须包在 `runAsync` 里。
Future<void> _prepareEmptyStudio(WidgetTester tester) async {
  final manager = StudioProjectManager.instance;
  manager.resetCachesForTesting();
  await tester.runAsync(() async {
    final existing = await manager.listSeries();
    for (final series in existing) {
      await manager.deleteSeries(series.id);
    }
  });
  manager.resetCachesForTesting();
}

Future<void> _settle(WidgetTester tester) async {
  // 外壳的 bootstrap 链路：ensureBaseStructure → listSeries →
  // _checkEngineStatus（读两次 Keychain，各约 70ms）。总耗时一两百毫秒，
  // 只等 50ms 会停在 loading 分支。这里轮询到加载指示器消失或超时。
  for (var i = 0; i < 20; i++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
  }
  await tester.pump();
}

/// 工坊外壳的冒烟测试：能构建、能建剧、切页不崩。
///
/// UI 只测「不会一进去就抛」。真正的交互（AI 拆分、合成、导出）都有服务层
/// 测试覆盖，widget 测试在这里的性价比低于它带来的维护成本。
void main() {
  setUpAll(() async {
    // 外壳的 bootstrap 会探测生图/视频引擎可用性，那要读 Keychain。flutter
    // test 里没有平台通道，真实 Keychain 读取会一直不返回——表现就是加载
    // 指示器永远转，_settle 多少轮都停在 loading 分支。装内存桥后读密钥
    // 同步完成，bootstrap 才能跑完。
    TestKeychainBridge.install();
    KeychainService.instance.setKekManagerForTesting(
      TestKeychainBridge.makeManager(),
    );

    AppPaths.overrideRootForTesting(
      Directory.systemTemp.createTempSync('studio_ui'),
    );
    // 预建目录：外壳的 initState 会做真实 IO（create/readAsString），而 widget
    // 测试的 fake async zone 不会等它——目录已存在时那些 IO 全部命中缓存，
    // bootstrap 同步返回，pump 一帧就能看到结果。
    await StudioProjectManager.instance.ensureBaseStructure();

    // 预热 Keychain 与 FFmpeg 可用性探测：外壳的 DeliveryPanel 与 engine status 会在
    // 没有平台通道的测试环境里起进程或读密钥。提前探测使缓存命中，避免 pending timer。
    await KeychainService.instance.readSecret('warmup');
    await FfmpegComposer.checkAvailability();
  });

  testWidgets('外壳可构建并显示工序导航', (tester) async {
    await _prepareEmptyStudio(tester);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.darkTheme, home: const StudioShellPage()),
    );
    await _settle(tester);

    expect(find.text('剧集库'), findsWidgets);
    expect(find.text('创意孵化'), findsOneWidget);
    expect(find.text('IP 主库'), findsOneWidget);
    expect(find.text('分镜看板'), findsOneWidget);
    expect(find.text('声音设计'), findsOneWidget);
    expect(find.text('合成交付'), findsOneWidget);
  });

  testWidgets('空剧集库显示新建引导', (tester) async {
    await _prepareEmptyStudio(tester);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.darkTheme, home: const StudioShellPage()),
    );
    await _settle(tester);
    expect(find.text('新建第一部剧集'), findsOneWidget);
  });

  testWidgets('有剧集时默认选中并显示在顶栏', (tester) async {
    final manager = StudioProjectManager.instance;
    await tester.runAsync(() => manager.createSeries(name: '雨夜回声'));
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.darkTheme, home: const StudioShellPage()),
    );
    await _settle(tester);
    expect(find.text('雨夜回声'), findsWidgets);
  });

  testWidgets('没有剧集时创意孵化入口被禁用', (tester) async {
    await _prepareEmptyStudio(tester);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.darkTheme, home: const StudioShellPage()),
    );
    await _settle(tester);

    // 侧导航在没剧集时直接禁用这些页，比让用户点了再看提示更早拦住。
    final inkWells = find.ancestor(
      of: find.text('创意孵化'),
      matching: find.byType(InkWell),
    );
    expect(inkWells, findsOneWidget);
    final inkWell = tester.widget<InkWell>(inkWells);
    expect(inkWell.onTap, isNull, reason: '没剧集时该入口应不可点');

    // 未生成的页面区此时仍是剧集库。
    expect(find.text('还没有剧集。先从模糊想法开始，AI 会帮你拆成能拍的结构。'),
        findsOneWidget);
  });

  testWidgets('有剧集后创意孵化入口恢复可点', (tester) async {
    await tester.runAsync(
      () => StudioProjectManager.instance.createSeries(name: '雨夜回声'),
    );
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.darkTheme, home: const StudioShellPage()),
    );
    await _settle(tester);

    final inkWells = find.ancestor(
      of: find.text('创意孵化'),
      matching: find.byType(InkWell),
    );
    final inkWell = tester.widget<InkWell>(inkWells);
    expect(inkWell.onTap, isNotNull);

    inkWell.onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // 进入了创意孵化面板
    expect(find.text('用一句模糊的想法开始。AI 会拆出三个能直接开拍的故事方向。'),
        findsOneWidget);
  });
  test('StudioSession 切剧集会重置集数', () {
    final session = StudioSession();
    final seriesA = StudioSeries(
      id: 'a',
      name: 'A',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final seriesB = StudioSeries(
      id: 'b',
      name: 'B',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    session.select(seriesA);
    session.selectEpisode(
      StudioEpisode(
        id: 'ep',
        seriesId: 'a',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
    expect(session.episode, isNotNull);

    session.select(seriesB);
    expect(session.episode, isNull,
           reason: '换剧后还留着上一部的集，会让分镜看板写出跨剧数据');
    expect(session.hasSeries, isTrue);

    session.select(null);
    expect(session.hasSeries, isFalse);
  });

  test('StudioSession 重复选择同一部不会触发刷新', () {
    final session = StudioSession();
    final series = StudioSeries(
      id: 'a',
      name: 'A',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    var notifications = 0;
    session.addListener(() => notifications++);
    session.select(series);
    session.select(series);
    expect(notifications, 1);
  });

  test('StudioSession 更新同 ID 剧集时更新 series 并保留 episode', () {
    final session = StudioSession();
    final seriesA1 = StudioSeries(
      id: 'a',
      name: 'A',
      eraGenre: '',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final seriesA2 = seriesA1.copyWith(
      eraGenre: 'xianxia',
      worldview: '玄幻修仙世界',
      updatedAt: DateTime(2026, 1, 2),
    );
    session.select(seriesA1);
    session.selectEpisode(
      StudioEpisode(
        id: 'ep1',
        seriesId: 'a',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
    expect(session.episode?.id, 'ep1');

    var notified = false;
    session.addListener(() => notified = true);

    session.select(seriesA2);
    expect(session.series?.eraGenre, 'xianxia');
    expect(session.series?.worldview, '玄幻修仙世界');
    expect(session.episode?.id, 'ep1', reason: '同 ID 剧集更新不应清空已选中的集');
    expect(notified, isTrue);

    // updateSeries 同样就地更新
    final seriesA3 = seriesA2.copyWith(eraGenre: 'cyberpunk_sci_fi');
    session.updateSeries(seriesA3);
    expect(session.series?.eraGenre, 'cyberpunk_sci_fi');
    expect(session.episode?.id, 'ep1');
  });
}
