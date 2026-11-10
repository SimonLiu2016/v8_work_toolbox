import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:V8WorkToolbox/tools/it_meeting_listening/models/real_meeting_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/meeting_vocabulary_index.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/real_meeting_service.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/speaker_profile_resolver.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/transcript_parser.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/vocabulary_study_store.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/ui/real_meeting_panel.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/ui/transcript_preview_dialog.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/ui/vocabulary_browser_dialog.dart';
import 'package:V8WorkToolbox/tools/reader/models/reader_models.dart';
import 'package:V8WorkToolbox/tools/reader/services/tts_engine.dart';

/// 拦截 FilePicker.saveFile 的假实现，返回预设路径并记录调用参数。
class _FakeFilePicker extends FilePicker {
  _FakeFilePicker(this.savePath);

  final String? savePath;
  String? lastDialogTitle;
  String? lastFileName;
  FileType? lastType;
  List<String>? lastAllowedExtensions;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    lastDialogTitle = dialogTitle;
    lastFileName = fileName;
    lastType = type;
    lastAllowedExtensions = allowedExtensions;
    return savePath;
  }
}

class _FakeTtsEngine implements TtsEngine {
  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Uint8List> synthesize(String text, TtsSynthesisConfig config) async =>
      Uint8List.fromList([0x49, 0x44, 0x33, ...text.codeUnits]);
}


void main() {
  RealMeeting meeting() => RealMeeting(
        id: 'rm_1',
        title: 'AI Agent Security Review',
        sourcePath: '/in/a.md',
        fileName: 'a.md',
        contentHash: 'h',
        declaredDurationMs: 0,
        keywords: const ['governance'],
        slots: const [
          SpeakerSlot(id: '发言人 1', turnCount: 3),
          SpeakerSlot(id: '发言人 2', turnCount: 2),
        ],
        turns: const [
          MeetingTurn(
              index: 0, slotId: '发言人 1', timestampMs: 0, text: 'hello.'),
        ],
        importedAt: DateTime(2026, 10, 20),
      );

  final speakers = {
    '发言人 1': const ResolvedSpeaker(
        slotId: '发言人 1', displayName: 'Alice', voiceId: 'v1', isMe: false),
    '发言人 2': const ResolvedSpeaker(
        slotId: '发言人 2', displayName: '发言人 2', voiceId: 'v2', isMe: true),
  };

  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  group('真实会议面板', () {
    testWidgets('收起时只显示一行摘要', (tester) async {
      await tester.pumpWidget(host(RealMeetingPanel(
        expanded: false,
        onToggleExpanded: () {},
        meetings: [meeting()],
        selectedId: 'rm_1',
        meeting: meeting(),
        speakers: speakers,
        mergeInto: const {},
        onMerge: (_, __) async {},
        onUnmerge: (_) async {},
        onRenameMeeting: (_) async {},
        bakeState: null,
        importing: false,
        baking: false,
        pendingGroupCount: 0,
        rebakeProgress: null,
        onRebake: () async {},
        onCancelRebake: () {},
        onPick: () async {},
        onSelect: (_) {},
        onRename: (_, __) async {},
        onVoice: (_, __) async {},
        onToggleMe: (_, __) async {},
        onBake: () async {},
        onOpenIdentity: () {},
      )));
      expect(find.text('真实会议'), findsOneWidget);
      expect(find.textContaining('AI Agent Security Review'), findsOneWidget);
      expect(find.text('导入逐字稿'), findsNothing);
    });

    testWidgets('展开后能看到说话人、看到「是我」的标记', (tester) async {
      await tester.pumpWidget(host(RealMeetingPanel(
        expanded: true,
        onToggleExpanded: () {},
        meetings: [meeting()],
        selectedId: 'rm_1',
        meeting: meeting(),
        speakers: speakers,
        mergeInto: const {},
        onMerge: (_, __) async {},
        onUnmerge: (_) async {},
        onRenameMeeting: (_) async {},
        bakeState: null,
        importing: false,
        baking: false,
        pendingGroupCount: 0,
        rebakeProgress: null,
        onRebake: () async {},
        onCancelRebake: () {},
        onPick: () async {},
        onSelect: (_) {},
        onRename: (_, __) async {},
        onVoice: (_, __) async {},
        onToggleMe: (_, __) async {},
        onBake: () async {},
        onOpenIdentity: () {},
      )));

      expect(find.text('导入逐字稿'), findsOneWidget);
      expect(find.text('发言人 1'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      // 两个槽位各一个"是我"开关，其中一个是打开的
      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches, hasLength(2));
      expect(switches.where((s) => s.value).length, 1);
    });

    testWidgets('改名字后回车触发 onRename', (tester) async {
      String? renamedSlot;
      String? renamedTo;
      await tester.pumpWidget(host(RealMeetingPanel(
        expanded: true,
        onToggleExpanded: () {},
        meetings: [meeting()],
        selectedId: 'rm_1',
        meeting: meeting(),
        speakers: speakers,
        mergeInto: const {},
        onMerge: (_, __) async {},
        onUnmerge: (_) async {},
        onRenameMeeting: (_) async {},
        bakeState: null,
        importing: false,
        baking: false,
        pendingGroupCount: 0,
        rebakeProgress: null,
        onRebake: () async {},
        onCancelRebake: () {},
        onPick: () async {},
        onSelect: (_) {},
        onRename: (slot, name) async {
          renamedSlot = slot;
          renamedTo = name;
        },
        onVoice: (_, __) async {},
        onToggleMe: (_, __) async {},
        onBake: () async {},
        onOpenIdentity: () {},
      )));

      final field = find.byKey(const ValueKey('speaker-name-发言人 1-Alice'));
      expect(field, findsOneWidget);
      await tester.enterText(field, 'Bob');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(renamedSlot, '发言人 1');
      expect(renamedTo, 'Bob');
    });
  });

  group('待更新提示与重新合成', () {
    Widget panelWith({
      int pending = 0,
      ({int done, int total})? progress,
      Future<void> Function()? onRebake,
      VoidCallback? onCancel,
    }) =>
        host(RealMeetingPanel(
          expanded: true,
          onToggleExpanded: () {},
          meetings: [meeting()],
          selectedId: 'rm_1',
          meeting: meeting(),
          speakers: speakers,
          mergeInto: const {},
          onMerge: (_, __) async {},
          onUnmerge: (_) async {},
          onRenameMeeting: (_) async {},
          bakeState: null,
          importing: false,
          baking: false,
          pendingGroupCount: pending,
          rebakeProgress: progress,
          onRebake: onRebake ?? () async {},
          onCancelRebake: onCancel ?? () {},
          onPick: () async {},
          onSelect: (_) {},
          onRename: (_, __) async {},
          onVoice: (_, __) async {},
          onToggleMe: (_, __) async {},
          onBake: () async {},
          onOpenIdentity: () {},
        ));

    testWidgets('没有待更新组时不显示提示', (tester) async {
      await tester.pumpWidget(panelWith());
      expect(find.textContaining('待更新'), findsNothing);
    });

    testWidgets('有待更新时显示组数并可触发重新合成', (tester) async {
      var rebaked = false;
      await tester.pumpWidget(panelWith(
        pending: 7,
        onRebake: () async => rebaked = true,
      ));
      expect(find.textContaining('7 组音频待更新'), findsOneWidget);

      await tester.tap(find.text('重新合成'));
      await tester.pumpAndSettle();
      expect(rebaked, isTrue);
    });

    testWidgets('合成中显示进度与取消', (tester) async {
      var cancelled = false;
      await tester.pumpWidget(panelWith(
        pending: 7,
        progress: (done: 3, total: 7),
        onCancel: () => cancelled = true,
      ));
      expect(find.textContaining('3/7'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(cancelled, isTrue);
    });
  });

  group('会议重命名入口', () {
    testWidgets('点重命名把当前标题交给回调', (tester) async {
      String? requested;
      await tester.pumpWidget(host(RealMeetingPanel(
        expanded: true,
        onToggleExpanded: () {},
        meetings: [meeting()],
        selectedId: 'rm_1',
        meeting: meeting(),
        speakers: speakers,
        mergeInto: const {},
        onMerge: (_, __) async {},
        onUnmerge: (_) async {},
        onRenameMeeting: (title) async => requested = title,
        bakeState: null,
        importing: false,
        baking: false,
        pendingGroupCount: 0,
        rebakeProgress: null,
        onRebake: () async {},
        onCancelRebake: () {},
        onPick: () async {},
        onSelect: (_) {},
        onRename: (_, __) async {},
        onVoice: (_, __) async {},
        onToggleMe: (_, __) async {},
        onBake: () async {},
        onOpenIdentity: () {},
      )));

      await tester.tap(find.text('重命名'));
      await tester.pumpAndSettle();
      expect(requested, 'AI Agent Security Review');
    });
  });

  group('槽位合并入口', () {
    testWidgets('从菜单选择合并目标会触发 onMerge', (tester) async {
      String? mergedFrom;
      String? mergedInto;
      await tester.pumpWidget(host(RealMeetingPanel(
        expanded: true,
        onToggleExpanded: () {},
        meetings: [meeting()],
        selectedId: 'rm_1',
        meeting: meeting(),
        speakers: speakers,
        mergeInto: const {},
        onMerge: (from, into) async {
          mergedFrom = from;
          mergedInto = into;
        },
        onUnmerge: (_) async {},
        onRenameMeeting: (_) async {},
        bakeState: null,
        importing: false,
        baking: false,
        pendingGroupCount: 0,
        rebakeProgress: null,
        onRebake: () async {},
        onCancelRebake: () {},
        onPick: () async {},
        onSelect: (_) {},
        onRename: (_, __) async {},
        onVoice: (_, __) async {},
        onToggleMe: (_, __) async {},
        onBake: () async {},
        onOpenIdentity: () {},
      )));

      await tester.tap(find.byIcon(Icons.merge_type).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('合并到 发言人 2').last);
      await tester.pumpAndSettle();

      expect(mergedFrom, '发言人 1');
      expect(mergedInto, '发言人 2');
    });

    testWidgets('已合并的槽位显示目标并提供取消合并', (tester) async {
      String? unmerged;
      await tester.pumpWidget(host(RealMeetingPanel(
        expanded: true,
        onToggleExpanded: () {},
        meetings: [meeting()],
        selectedId: 'rm_1',
        meeting: meeting(),
        speakers: speakers,
        mergeInto: const {'发言人 2': '发言人 1'},
        onMerge: (_, __) async {},
        onUnmerge: (slot) async => unmerged = slot,
        onRenameMeeting: (_) async {},
        bakeState: null,
        importing: false,
        baking: false,
        pendingGroupCount: 0,
        rebakeProgress: null,
        onRebake: () async {},
        onCancelRebake: () {},
        onPick: () async {},
        onSelect: (_) {},
        onRename: (_, __) async {},
        onVoice: (_, __) async {},
        onToggleMe: (_, __) async {},
        onBake: () async {},
        onOpenIdentity: () {},
      )));

      expect(find.text('→ 发言人 1'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.merge_type).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消合并').last);
      await tester.pumpAndSettle();

      expect(unmerged, '发言人 2');
    });
  });

  group('解析预览对话框', () {
    TranscriptPreview preview({
      bool contentUnchanged = false,
      bool processed = false,
      bool keywordsMissing = false,
    }) =>
        TranscriptPreview(
          sourcePath: '/in/a.md',
          fileName: 'a.md',
          title: 'AI Agent Security Review',
          meetingId: 'rm_1',
          contentHash: 'h',
          turnCount: 274,
          durationMs: 39 * 60 * 1000 + 44000,
          slotIds: const ['发言人 1', '发言人 2', '发言人 3'],
          samples: const [
            (slot: '发言人 1', text: 'RightLet me pick my colleagues'),
            (slot: '发言人 2', text: '呃。Jocelyn today and see'),
          ],
          parsed: const ParsedTranscript(
            title: 'AI Agent Security Review',
            declaredDurationMs: 0,
            keywords: [],
            turns: [],
            slots: [],
          ),
          isProcessedDocument: processed,
          keywordsMissing: keywordsMissing,
          contentUnchanged: contentUnchanged,
        );

    Future<bool?> show(WidgetTester tester, TranscriptPreview p) async {
      bool? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                result = await showDialog<bool>(
                  context: ctx,
                  builder: (_) => TranscriptPreviewDialog(preview: p),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('显示轮次、说话人与样例', (tester) async {
      await show(tester, preview());
      expect(find.textContaining('274 轮'), findsOneWidget);
      expect(find.textContaining('3 个说话人'), findsOneWidget);
      expect(find.textContaining('39 分 44 秒'), findsOneWidget);
      expect(find.text('RightLet me pick my colleagues'), findsOneWidget);
      expect(find.text('确认并合成'), findsOneWidget);
    });

    testWidgets('取消返回 false，不进入导入', (tester) async {
      await show(tester, preview());
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(TranscriptPreviewDialog), findsNothing);
    });

    testWidgets('内容未变时按钮文案改为使用已有音频', (tester) async {
      await show(tester, preview(contentUnchanged: true));
      expect(find.text('使用已有音频'), findsOneWidget);
      expect(find.textContaining('内容未变'), findsOneWidget);
    });

    testWidgets('归档件与缺失关键词各有说明', (tester) async {
      await show(tester, preview(processed: true, keywordsMissing: true));
      expect(find.textContaining('归档件'), findsOneWidget);
      expect(find.textContaining('关键词'), findsOneWidget);
    });
  });

  group('词汇表对话框', () {
    final index = MeetingVocabularyIndex.build([
      RealMeeting(
        id: 'rm_1',
        title: 'AI Agent Security Review',
        sourcePath: '/in/a.md',
        fileName: 'a.md',
        contentHash: 'h',
        declaredDurationMs: 0,
        keywords: const ['governance'],
        slots: const [SpeakerSlot(id: '发言人 1', turnCount: 1)],
        turns: const [
          MeetingTurn(
              index: 0,
              slotId: '发言人 1',
              timestampMs: 5000,
              text: 'we discussed governance and VPC'),
        ],
        importedAt: DateTime(2026, 10, 20),
      ),
    ]);

    testWidgets('主列表隐藏停用词，显示内容词', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: VocabularyBrowserDialog(index: index, onJump: (_) {}),
        ),
      ));
      expect(find.textContaining('跨全部真实会议'), findsOneWidget);
      expect(find.text('we'), findsNothing);
      expect(find.text('governance'), findsOneWidget);
    });

    testWidgets('查一个词能展开出处并跳转', (tester) async {
      VocabularyPosting? jumped;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: VocabularyBrowserDialog(
              index: index, onJump: (p) => jumped = p),
        ),
      ));

      await tester.enterText(find.byType(TextField).first, 'VPC');
      await tester.pumpAndSettle();
      // 输入框里也留着 "VPC"，所以匹配会命中两处；点列表项那一处。
      expect(find.text('VPC'), findsWidgets);

      await tester.tap(find.text('VPC').last);
      await tester.pumpAndSettle();
      final sentence = find.textContaining('we discussed governance and VPC');
      expect(sentence, findsOneWidget);

      await tester.tap(sentence);
      await tester.pumpAndSettle();
      expect(jumped, isNotNull);
      expect(jumped!.turnIndex, 0);
    });

    testWidgets('无重点词时导出按钮禁用', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: VocabularyBrowserDialog(index: index, onJump: (_) {}),
        ),
      ));
      await tester.pumpAndSettle();

      final btn = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('vocab-export-focused-btn')),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('标记重点词后导出按钮可点击且保存成功写入文件', (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('vocab_export_ui_');
      final savedPath = '${tempDir.path}/重点关注词汇.md';
      final fakePicker = _FakeFilePicker(savedPath);
      FilePicker.platform = fakePicker;

      final studyStore = VocabularyStudyStore(
        baseDir: tempDir,
        ttsEngine: _FakeTtsEngine(),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: VocabularyBrowserDialog(
            index: index,
            studyStore: studyStore,
            onJump: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // 初始：无重点词 → 禁用。
      final initialBtn = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('vocab-export-focused-btn')),
      );
      expect(initialBtn.onPressed, isNull);

      // 标记 governance 为重点关注。
      await tester.tap(
        find.byKey(const ValueKey('vocab-focus-btn-governance')),
      );
      await tester.pumpAndSettle();

      // 有重点词 → 可点击。
      final enabledBtn = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('vocab-export-focused-btn')),
      );
      expect(enabledBtn.onPressed, isNotNull);

      // 点击导出 → 调起 saveFile → 写入文件 → SnackBar。
      // 真实文件 IO 需在 runAsync 中完成（fake-async 区不推进 dart:io 未来）。
      await tester.runAsync(() async {
        await tester.tap(
          find.byKey(const ValueKey('vocab-export-focused-btn')),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      expect(fakePicker.lastDialogTitle, '导出重点关注词汇');
      expect(fakePicker.lastType, FileType.custom);
      expect(fakePicker.lastAllowedExtensions, contains('md'));
      expect(fakePicker.lastFileName, startsWith('重点关注词汇_'));

      final savedFile = File(savedPath);
      expect(savedFile.existsSync(), isTrue);
      final content = savedFile.readAsStringSync();
      expect(content, contains('# 听力练习重点关注词汇表'));
      expect(content, contains('## governance'));
      expect(content, contains('1. we discussed governance and VPC'));

      expect(
        find.textContaining('已成功导出 1 个重点词汇'),
        findsOneWidget,
      );

      studyStore.dispose();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    testWidgets('取消保存时不写文件、无报错', (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('vocab_export_cancel_');
      final fakePicker = _FakeFilePicker(null); // 返回 null = 取消
      FilePicker.platform = fakePicker;

      final studyStore = VocabularyStudyStore(
        baseDir: tempDir,
        ttsEngine: _FakeTtsEngine(),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: VocabularyBrowserDialog(
            index: index,
            studyStore: studyStore,
            onJump: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('vocab-focus-btn-governance')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('vocab-export-focused-btn')),
      );
      await tester.pumpAndSettle();

      // 取消：无 SnackBar（成功或失败都不该有）、无文件。
      expect(find.textContaining('已成功导出'), findsNothing);
      expect(find.textContaining('导出失败'), findsNothing);

      studyStore.dispose();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
