import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/listening_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/clip_summarizer.dart';

Clip _clip(int durationMs, int turns) => Clip(
      id: 'c1',
      scene: MeetingScene.incident,
      title: 't',
      audioPath: 'c1.mp3',
      durationMs: durationMs,
      turns: List.generate(
        turns,
        (i) => SpeakerTurn(
          speaker: 'IC',
          role: 'Incident Commander',
          rawText: 'line $i',
          synthesisText: 'line $i',
          voice: 'step_boy',
        ),
      ),
      source: const ClipSource(sourceId: 'test', site: 's', pageUrl: 'u', column: 'c'),
    );

void main() {
  group('ClipSummarizer.split 解析「议题｜结论」', () {
    test('标准两段式被正确拆分', () {
      final r = ClipSummarizer.split('支付服务返回 503｜决定回滚配置变更');
      expect(r.topic, '支付服务返回 503');
      expect(r.conclusion, '决定回滚配置变更');
    });

    test('无分隔符时整段作为议题，结论留空', () {
      final r = ClipSummarizer.split('只是一句话');
      expect(r.topic, '只是一句话');
      expect(r.conclusion, isEmpty);
    });

    test('空串返回两个空字段', () {
      final r = ClipSummarizer.split('');
      expect(r.topic, isEmpty);
      expect(r.conclusion, isEmpty);
    });

    test('结论里含分隔符时后半段整体作为结论', () {
      final r = ClipSummarizer.split('议题｜结论一｜结论二');
      expect(r.topic, '议题');
      expect(r.conclusion, '结论一｜结论二');
    });
  });

  group('ClipSummarizer 摘要门槛', () {
    test('短片段不生成摘要', () async {
      final s = ClipSummarizer();
      // 59 秒 < 门槛 60 秒 → 不调用 LLM
      expect(await s.summarize(_clip(59000, 5)), isNull);
    });

    test('空轮次不生成摘要', () async {
      final s = ClipSummarizer();
      expect(await s.summarize(_clip(120000, 0)), isNull);
    });
  });
}
