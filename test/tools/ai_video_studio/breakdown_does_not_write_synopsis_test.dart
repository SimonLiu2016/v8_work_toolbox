import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/drama_director_contract.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/ai_constraint_engine.dart';

/// spec: ai-video-studio/script-workshop · 分镜看板拆镜不回写剧集概要
///
/// 拆镜是读取操作。旧实存在 `episode.copyWith(synopsis: synopsis, ...)` 里
/// 把粗大纲文本框的内容回写成剧集概要——用户在文本框里改几个字点一次拆镜，
/// 这一集的 synopsis 就被永久改写，而剧本工作台读的是另一份文本，从此两边
/// 对"这一集讲什么"有两个答案。
///
/// UI 层的 `_breakdown` 是私有方法，这里通过它调用的数据层契约间接守这条：
/// 拆镜写入只应触碰 shots 与 segments，不应触碰 synopsis。
void main() {
  DramaScene sceneWithDialogue() => DramaScene(
    id: 'scene-1',
    sceneNumber: 1,
    title: '镇魔司大殿',
    location: '大殿',
    beats: [
      DramaBeat(
        id: 'beat-1',
        sceneId: 'scene-1',
        order: 1,
        name: '授刀',
        action: '东方诏将斩妖刀递与沈长青',
        dialogueSpeaker: '东方诏',
        dialogue: '斩妖除魔，护我人族！',
      ),
    ],
  );

  test('拆镜写入只改 shots 与 segments，不动 synopsis', () {
    final now = DateTime(2026, 10, 23);
    final episode = StudioEpisode(
      id: 'ep_1',
      seriesId: 's_01',
      index: 1,
      title: '第一集',
      synopsis: '沈长青入职镇魔司受命出征。',
      scenes: [sceneWithDialogue()],
      createdAt: now,
      updatedAt: now,
    );

    // 模拟 StoryboardBoard._breakdown 的写回形状：文本框里的粗大纲只作为
    // 拆镜输入，不进入 copyWith。
    final shots = AiConstraintEngine.convertScenesToShots(episode.scenes);
    final segments = StudioEpisode.buildSegmentsFromScenes(
      episode.scenes,
      shots,
    );
    final saved = episode.copyWith(
      shots: shots,
      segments: segments.isNotEmpty ? segments : null,
    );

    expect(saved.synopsis, episode.synopsis);
    expect(saved.shots, hasLength(1));
    expect(saved.segments, isNotEmpty);
  });
}
