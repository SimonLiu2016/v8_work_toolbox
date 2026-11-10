import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/listening_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/sentence_vault_store.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/ui/transcript_drawer.dart';

Clip _createMockClip() {
  return const Clip(
    id: 'test_transcript_copy_clip',
    scene: MeetingScene.realMeeting,
    title: 'Sprint Planning Meeting',
    audioPath: 'test.mp3',
    durationMs: 30000,
    turns: [
      SpeakerTurn(
        speaker: 'Dave',
        role: 'Tech Lead',
        rawText:
            'In this case, the query execution plan took five seconds to complete before indexing.',
        synthesisText:
            'In this case, the query execution plan took five seconds to complete before indexing.',
        voice: 'en-US-GuyNeural',
        startMs: 0,
        endMs: 8000,
      ),
    ],
    source: ClipSource(
      sourceId: 'real-meeting',
      site: 'Local',
      pageUrl: '',
      column: '',
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  String? clipboardContent;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('transcript_copy_test');
    final vaultFile = File(p.join(tmp.path, 'sentence_vault.json'));
    final store = SentenceVaultStore(vaultFile);
    await store.init();
    SentenceVaultStore.setInstanceForTesting(store);

    clipboardContent = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (methodCall) async {
      if (methodCall.method == 'Clipboard.setData') {
        final args = methodCall.arguments as Map<dynamic, dynamic>?;
        clipboardContent = args?['text'] as String?;
        return null;
      }
      if (methodCall.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': clipboardContent};
      }
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    SentenceVaultStore.setInstanceForTesting(null);
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  testWidgets('TranscriptDrawer 标准模式下正文为 SelectableText 且点击复制写入纯英文',
      (tester) async {
    final clip = _createMockClip();
    int? seekTarget;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TranscriptDrawer(
            clip: clip,
            currentTurnIndex: 0,
            onClose: () {},
            onSeekToTurn: (ms) => seekTarget = ms,
            onCollectTerm: (_, __, ___) {},
            onOpenAnswerComposer: (_) {},
            onOpenAnswerActions: (_) {},
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 验证正文使用 SelectableText 渲染
    final selectableTexts = find.byType(SelectableText);
    expect(selectableTexts, findsWidgets);

    // 验证说话人栏可点击触发 seek
    final speakerFinder = find.text('Dave:');
    expect(speakerFinder, findsOneWidget);
    await tester.tap(speakerFinder);
    await tester.pump();
    expect(seekTarget, 0);

    // 点击复制按钮 (Icons.copy_rounded)
    final copyBtn = find.byIcon(Icons.copy_rounded);
    expect(copyBtn, findsOneWidget);
    await tester.tap(copyBtn);
    await tester.pump();

    // 验证剪贴板写入纯英文（不带发言人）
    expect(
      clipboardContent,
      'In this case, the query execution plan took five seconds to complete before indexing.',
    );
  });

  testWidgets('TranscriptDrawer 意群模式下点击复制写入带 // 和行号的排版文本', (tester) async {
    final clip = _createMockClip();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TranscriptDrawer(
            clip: clip,
            currentTurnIndex: 0,
            onClose: () {},
            onSeekToTurn: (_) {},
            onCollectTerm: (_, __, ___) {},
            onOpenAnswerComposer: (_) {},
            onOpenAnswerActions: (_) {},
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 切换到意群断句模式
    final senseGroupBtn = find.text('意群断句');
    expect(senseGroupBtn, findsOneWidget);
    await tester.tap(senseGroupBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 点击复制按钮
    final copyBtn = find.byIcon(Icons.copy_rounded);
    await tester.tap(copyBtn);
    await tester.pump();

    // 验证剪贴板写入带有 // 停顿符排版的意群内容
    expect(clipboardContent, isNotNull);
    expect(clipboardContent!.contains('//'), isTrue);
    expect(clipboardContent!.contains('1. '), isTrue);
  });
}
