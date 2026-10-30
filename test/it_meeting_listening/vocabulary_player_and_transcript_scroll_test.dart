import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/listening_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/real_meeting_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/meeting_vocabulary_index.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/vocabulary_study_store.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/ui/transcript_drawer.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/ui/vocabulary_browser_dialog.dart';
import 'package:V8WorkToolbox/tools/reader/models/reader_models.dart';
import 'package:V8WorkToolbox/tools/reader/services/tts_engine.dart';

import 'recording_audio_backend.dart';

class _FakeTtsEngine implements TtsEngine {
  final List<String> synthesizedTexts = [];

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Uint8List> synthesize(String text, TtsSynthesisConfig config) async {
    synthesizedTexts.add(text);
    return Uint8List.fromList([0x49, 0x44, 0x33, ...text.codeUnits]);
  }
}

RealMeeting _sampleMeeting() {
  return RealMeeting(
    id: 'm1',
    title: 'Architecture Sync',
    sourcePath: '/tmp/m1.md',
    fileName: 'm1.md',
    contentHash: 'hash123',
    declaredDurationMs: 60000,
    importedAt: DateTime.utc(2026, 10, 24),
    keywords: const ['governance', 'idempotent'],
    slots: const [
      SpeakerSlot(id: 'Host', turnCount: 1),
      SpeakerSlot(id: 'CTO', turnCount: 1),
    ],
    turns: const [
      MeetingTurn(
        index: 0,
        slotId: 'Host',
        timestampMs: 12000,
        text: 'We need stronger data Governance before scaling.',
      ),
      MeetingTurn(
        index: 1,
        slotId: 'CTO',
        timestampMs: 45000,
        text: "Cloud governance's overhead should not block idempotent jobs.",
      ),
    ],
  );
}

Clip _createTestClip({int turnCount = 30}) {
  return Clip(
    id: 'clip_01',
    scene: MeetingScene.realMeeting,
    title: 'Design Review Meeting',
    audioPath: '/tmp/clip_01.mp3',
    durationMs: turnCount * 5000,
    summary: 'Discussion about system architecture and latency.',
    source: const ClipSource(
      sourceId: 'real-meeting',
      site: 'Internal',
      pageUrl: 'https://internal',
      column: 'Tech Review',
    ),
    turns: List.generate(
      turnCount,
      (i) => SpeakerTurn(
        speaker: 'Engineer ${i % 3 + 1}',
        role: 'Dev',
        rawText: 'This is turn number $i discussing architecture and latency.',
        synthesisText:
            'This is turn number $i discussing architecture and latency.',
        voice: 'en-US-Standard-C',
        startMs: i * 5000,
        endMs: (i + 1) * 5000,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VocabularyBrowserDialog Continuous Playback & Row TTS', () {
    late Directory tempDir;
    late _FakeTtsEngine fakeTts;
    late VocabularyStudyStore studyStore;
    late MeetingVocabularyIndex index;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('vocab_player_test_');
      fakeTts = _FakeTtsEngine();
      studyStore = VocabularyStudyStore(
        baseDir: tempDir,
        ttsEngine: fakeTts,
      );
      index = MeetingVocabularyIndex.build([_sampleMeeting()]);
    });

    tearDown(() async {
      studyStore.dispose();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    testWidgets('Row-level TTS button triggers pronunciation',
        (tester) async {
      final playedFiles = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VocabularyBrowserDialog(
              index: index,
              studyStore: studyStore,
              audioBackend: RecordingAudioBackend(played: playedFiles),
              onJump: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rowTtsBtn = find.byKey(const ValueKey('vocab-row-tts-governance'));
      expect(rowTtsBtn, findsOneWidget);

      await tester.tap(rowTtsBtn);
      await tester.pumpAndSettle();

      expect(fakeTts.synthesizedTexts, contains('governance'));
      expect(playedFiles.length, 1);
    });

    testWidgets('Continuous playback controls and sequential stepping',
        (tester) async {
      final playedFiles = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VocabularyBrowserDialog(
              index: index,
              studyStore: studyStore,
              audioBackend: RecordingAudioBackend(played: playedFiles),
              onJump: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final playPauseBtn =
          find.byKey(const ValueKey('vocab-continuous-play-pause-btn'));
      final nextBtn = find.byKey(const ValueKey('vocab-continuous-next-btn'));
      final prevBtn = find.byKey(const ValueKey('vocab-continuous-prev-btn'));
      final stopBtn = find.byKey(const ValueKey('vocab-continuous-stop-btn'));
      final loopBtn = find.byKey(const ValueKey('vocab-continuous-loop-btn'));

      expect(playPauseBtn, findsOneWidget);
      expect(nextBtn, findsOneWidget);
      expect(prevBtn, findsOneWidget);
      expect(stopBtn, findsOneWidget);
      expect(loopBtn, findsOneWidget);

      // Start continuous playback
      await tester.tap(playPauseBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(playedFiles.isNotEmpty, isTrue);
      expect(find.textContaining('朗读中:'), findsOneWidget);

      // Next word
      await tester.tap(nextBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Stop
      await tester.tap(stopBtn);
      await tester.pumpAndSettle();

      expect(find.textContaining('连续磨耳朵'), findsOneWidget);
    });
  });

  group('TranscriptDrawer Scroll and Center Alignment', () {
    testWidgets('Renders turns and centers on current turn', (tester) async {
      final clip = _createTestClip(turnCount: 40);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 420,
              height: 600,
              child: TranscriptDrawer(
                clip: clip,
                currentTurnIndex: 15,
                onClose: () {},
                onSeekToTurn: (_) {},
                onCollectTerm: (_, __, ___) {},
                onOpenAnswerComposer: (_) {},
                onOpenAnswerActions: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('transcript-drawer')), findsOneWidget);
      expect(find.text('精听 · Design Review Meeting'), findsOneWidget);
      // Turn 15 should be visible in viewport
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is RichText &&
              w.text.toPlainText().contains('This is turn number 15'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'Manual user scroll reveals return button; clicking it returns and centers',
        (tester) async {
      final clip = _createTestClip(turnCount: 50);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 420,
              height: 500,
              child: TranscriptDrawer(
                clip: clip,
                currentTurnIndex: 10,
                onClose: () {},
                onSeekToTurn: (_) {},
                onCollectTerm: (_, __, ___) {},
                onOpenAnswerComposer: (_) {},
                onOpenAnswerActions: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially no return button
      final returnBtnFinder =
          find.byKey(const ValueKey('transcript-return-to-current-btn'));
      expect(returnBtnFinder, findsNothing);

      // Simulate user manual scroll drag
      await tester.drag(
        find.byKey(const ValueKey('transcript-drawer')),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      // Now return button should appear
      expect(returnBtnFinder, findsOneWidget);

      // Tap return button
      await tester.tap(returnBtnFinder);
      await tester.pumpAndSettle();

      // Return button should be gone
      expect(returnBtnFinder, findsNothing);
    });
  });
}
