import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/theme/app_theme.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/ui/asset_prompt_preview_dialog.dart';

void main() {
  testWidgets('AssetPromptPreviewDialog renders without error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                AssetPromptPreviewDialog.show(
                  context,
                  title: '360° 全景母图 Prompt 预览与微调',
                  assetName: '姜七夜识海 (360°母图)',
                  initialPositivePrompt: 'test positive prompt',
                  initialNegativePrompt: 'test negative prompt',
                  componentLayers: const [
                    PromptComponentLayer(
                      label: '全景透视约束',
                      content: '360 degree projection',
                      color: Colors.blueAccent,
                    ),
                    PromptComponentLayer(
                      label: '空镜底板规范',
                      content: 'pure empty plate',
                      color: Colors.purpleAccent,
                    ),
                  ],
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('360° 全景母图 Prompt 预览与微调'), findsOneWidget);
    expect(find.text('当前目标：姜七夜识海 (360°母图)'), findsOneWidget);
    expect(find.text('test positive prompt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
