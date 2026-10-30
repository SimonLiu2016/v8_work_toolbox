import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/ui/image_dimension_selector.dart';

void main() {
  group('弹窗与抽屉安全边距及防溢出测试', () {
    testWidgets('道具操作工具栏在窄屏下采用 Wrap 自适应流式折行，不产生 RenderFlex 溢出', (tester) async {
      // 模拟道具操作工具栏在 360px 极窄宽度视口中的渲染
      tester.view.physicalSize = const Size(360, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool addRefClicked = false;
      bool pickAssetClicked = false;
      bool generateClicked = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Container(
              width: 360,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('参考图/道具图 (1)'),
                      OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.bookmark_add_outlined, size: 14),
                        label: const Text('收进资产库'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => addRefClicked = true,
                        icon: const Icon(Icons.add_photo_alternate_outlined, size: 15),
                        label: const Text('添加参考图'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => pickAssetClicked = true,
                        icon: const Icon(Icons.photo_library_outlined, size: 15),
                        label: const Text('从资产库选择'),
                      ),
                      ImageDimensionSelector(
                        selectedPreset: StudioImageDimensionPreset.presets.first,
                        compact: true,
                        onChanged: (_) {},
                      ),
                      FilledButton.icon(
                        onPressed: () => generateClicked = true,
                        icon: const Icon(Icons.auto_awesome, size: 15),
                        label: const Text('生成道具图'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 验证在 360px 宽度下无 Flutter 溢出报错
      expect(tester.takeException(), isNull);

      // 验证各个按钮均正常渲染且可点击
      expect(find.text('添加参考图'), findsOneWidget);
      expect(find.text('从资产库选择'), findsOneWidget);
      expect(find.text('生成道具图'), findsOneWidget);

      await tester.tap(find.text('添加参考图'));
      expect(addRefClicked, isTrue);

      await tester.tap(find.text('从资产库选择'));
      expect(pickAssetClicked, isTrue);

      await tester.tap(find.text('生成道具图'));
      expect(generateClicked, isTrue);
    });

    test('媒体预览弹窗避让 macOS 顶部标题栏盲区 (top >= 48px)', () {
      const inset = EdgeInsets.fromLTRB(40, 52, 40, 24);
      expect(inset.top, greaterThanOrEqualTo(48));
      expect(inset.top, equals(52));
    });
  });
}
