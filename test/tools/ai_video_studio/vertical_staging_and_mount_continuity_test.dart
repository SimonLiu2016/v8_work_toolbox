import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/ai_constraint_engine.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/director_validation_engine.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/prompt_assembler.dart';

StudioEpisode _episode({List<StudioShot> shots = const []}) => StudioEpisode(
  id: 'ep_1',
  seriesId: 's_01',
  index: 1,
  title: '第一集',
  shots: shots,
  createdAt: DateTime(2026, 10, 26),
  updatedAt: DateTime(2026, 10, 26),
);

CharacterCard _char(String id, String name) => CharacterCard(
  id: id,
  name: name,
  descriptionZh: '描述',
  updatedAt: DateTime(2026, 10, 26),
);

SceneCard _scene(String id, String name) => SceneCard(
  id: id,
  name: name,
  descriptionZh: '寒阳城长街青石板官道，落日余晖',
  updatedAt: DateTime(2026, 10, 26),
);

void main() {
  final charYu = _char('char_yu', '余小白');
  final charJiang = _char('char_jiang', '姜七夜');
  final sceneStreet = _scene('sc_street', '寒阳城长街');

  group('1. 垂直高低位空间调度与单向过肩构图（Anti-Floating Staging）', () {
    test('检测垂直高低位空间落差 (三楼窗口 vs 街面)', () {
      final shot = StudioShot(
        number: 2,
        actionZh: '天人居三楼窗口探出白胖身子，余小白提着酒杯，居高临下扬声喊住姜七夜。',
        characterIds: ['char_yu', 'char_jiang'],
        sceneId: 'sc_street',
        continuity: const ShotContinuity(
          worldPosition: '寒阳城长街·天人居酒楼前',
          screenPosition: '姜七夜居画面下方街道，余小白位于上方窗框',
          elevationLevel: 'balcony_3f',
        ),
      );

      expect(
        PromptAssembler.hasVerticalElevationDifference(shot: shot),
        isTrue,
      );
    });

    test('高低位同框时，提示词自动编译为单向过肩前景与街面远景焦点，严禁平地并立', () {
      final shot = StudioShot(
        number: 2,
        durationSec: 6.0,
        shotSize: StudioShotSize.long,
        actionZh: '天人居三楼窗口探出白胖身子，余小白提着酒杯，居高临下扬声喊住姜七夜。',
        dialogue: '余小白：“吆！这不是姜七少吗？上来喝一杯啊！”',
        characterIds: ['char_yu', 'char_jiang'],
        sceneId: 'sc_street',
        continuity: const ShotContinuity(
          worldPosition: '寒阳城长街·天人居酒楼前',
          screenPosition: '姜七夜居画面下方街道，余小白位于上方窗框',
          elevationLevel: 'balcony_3f',
          cameraAngle: 'high_angle',
          mountOrVehicle: '大黑驴',
        ),
        directorDecisions: const DirectorDecisions(
          cameraStaging: '高角度俯拍（三楼窗台向下俯视街道）',
        ),
      );

      final materials = [
        const ResolvedAssetMaterial(
          assetId: 'char_yu',
          assetName: '余小白',
          isScene: false,
          role: ShotAssetRole.subject,
          filePath: '/path/yu.png',
          index: 0,
        ),
        const ResolvedAssetMaterial(
          assetId: 'char_jiang',
          assetName: '姜七夜',
          isScene: false,
          role: ShotAssetRole.subject, // 原本未指定分工时默认为 subject
          filePath: '/path/jiang.png',
          index: 1,
        ),
      ];

      final prompt = PromptAssembler.buildVideoGenPrompt(
        shot: shot,
        episode: _episode(shots: [shot]),
        characters: [charYu, charJiang],
        scene: sceneStreet,
        materials: materials,
        videoMode: AgnesVideoMode.reference,
      );

      // 1. 验证单一主体约束：余小白为主体，姜七夜自动收敛为对峙或配角，严禁两人同时为主体
      expect(prompt, contains('余小白（处于画面前景窗框俯瞰（过肩构图），形象以<Picture 1>为准，分工：主体）'));
      expect(prompt, contains('姜七夜（处于画面远景街道地面焦点，骑在大黑驴上仰头，形象以<Picture 2>为准，分工：对峙）'));
      expect(prompt, isNot(contains('处于画面主体近景')));
      expect(prompt, isNot(contains('处于画面同框配角，形象以<Picture 2>为准，分工：主体')));

      // 2. 空间关系段包含显式物理高差隔离与冲突词清洗（正向深度解耦）
      expect(prompt, contains('垂直空间落差隔离：楼上窗口高位俯视街面，街面长街地面仰望回应，构成单向过肩俯拍构图'));
      expect(prompt, contains('垂直空间落差分明，高位与地面纵深分离'));
      expect(prompt, contains('坐骑状态保持：画内骑乘大黑驴，保持骑坐体态，严禁直立站地'));
    });

    test('生图提示词 resolveCharacterStaging 支持高低位透视过肩转译并剔除远景下的“近景”冲突', () {
      final stagingHigh = PromptAssembler.resolveCharacterStaging(
        index: 0,
        totalCount: 2,
        character: charYu,
        actionZh: '天人居三楼窗口探出白胖身子，余小白提着酒杯，居高临下扬声喊住姜七夜。',
        continuity: const ShotContinuity(
          screenPosition: '姜七夜居画面下方街道，余小白位于上方窗框',
          elevationLevel: 'balcony_3f',
        ),
        shotSize: 'wide',
      );

      final stagingLow = PromptAssembler.resolveCharacterStaging(
        index: 1,
        totalCount: 2,
        character: charJiang,
        actionZh: '天人居三楼窗口探出白胖身子，余小白提着酒杯，居高临下扬声喊住姜七夜。',
        continuity: const ShotContinuity(
          screenPosition: '姜七夜居画面下方街道，余小白位于上方窗框',
          elevationLevel: 'balcony_3f',
          mountOrVehicle: '大黑驴',
        ),
        shotSize: 'wide',
      );

      expect(stagingHigh, contains('余小白身处楼上窗口高位（过肩前景构图框）'));
      expect(stagingHigh, isNot(contains('近景')));

      expect(stagingLow, contains('姜七夜身处下方长街路面（远景街道视觉焦点），骑在大黑驴上仰头回应'));
      expect(stagingLow, contains('严禁平地并立'));
    });
  });

  group('2. 坐骑与载具跨镜头状态台账继承 (Mount Continuity)', () {
    test('convertScenesToShots 自动继承前镜坐骑状态，未发生下骑事件不退化为站姿', () {
      final scene = DramaScene(
        id: 'scene_1',
        sceneNumber: 1,
        title: '寒阳城长街',
        location: '寒阳城长街',
        beats: [
          const DramaBeat(
            id: 'b1',
            sceneId: 'scene_1',
            order: 1,
            action: '姜七夜骑着一头大黑驴，晃晃悠悠走在寒阳城长街上。',
            characterIds: ['char_jiang'],
          ),
          const DramaBeat(
            id: 'b2',
            sceneId: 'scene_1',
            order: 2,
            action: '天人居三楼窗口探出白胖身子，余小白提着酒杯，居高临下扬声喊住姜七夜。',
            dialogue: '余小白：“吆！这不是姜七少吗？上来喝一杯啊！”',
            dialogueSpeaker: '余小白',
            characterIds: ['char_yu', 'char_jiang'],
          ),
          const DramaBeat(
            id: 'b3',
            sceneId: 'scene_1',
            order: 3,
            action: '姜七夜翻身下驴，系好缰绳迈步走进酒楼大门。',
            characterIds: ['char_jiang'],
          ),
          const DramaBeat(
            id: 'b4',
            sceneId: 'scene_1',
            order: 4,
            action: '姜七夜走上三楼木梯。',
            characterIds: ['char_jiang'],
          ),
        ],
      );

      final shots = AiConstraintEngine.convertScenesToShots(
        [scene],
        characters: [charYu, charJiang],
      );

      expect(shots.length, 4);

      // 分镜 1：骑大黑驴
      expect(shots[0].continuity.mountOrVehicle, '大黑驴');

      // 分镜 2：继承大黑驴坐骑状态，且垂直海拔识别为 balcony_3f
      expect(shots[1].continuity.mountOrVehicle, '大黑驴');
      expect(shots[1].continuity.elevationLevel, 'balcony_3f');

      // 分镜 3：翻身下驴，发生下骑动作
      expect(shots[2].continuity.mountOrVehicle, '');

      // 分镜 4：坐骑状态已终结
      expect(shots[3].continuity.mountOrVehicle, '');
    });
  });

  group('3. Keyframe 首尾帧模式参考标签净化（Anti-Ghosting）', () {
    test('keyframe 模式自动剥离【素材指代】段落并净化时间轴中的 Picture 标签', () {
      final shot = StudioShot(
        number: 2,
        durationSec: 6.0,
        shotSize: StudioShotSize.long,
        videoMode: 'keyframe',
        actionZh: '天人居三楼窗口探出白胖身子，余小白提着酒杯，居高临下扬声喊住姜七夜。',
        dialogue: '余小白：“吆！这不是姜七少吗？上来喝一杯啊！”',
        characterIds: ['char_yu', 'char_jiang'],
        sceneId: 'sc_street',
        continuity: const ShotContinuity(
          worldPosition: '寒阳城长街·天人居酒楼前',
          screenPosition: '姜七夜居画面下方街道，余小白位于上方窗框',
          elevationLevel: 'balcony_3f',
        ),
      );

      final materials = [
        const ResolvedAssetMaterial(
          assetId: 'char_yu',
          assetName: '余小白',
          isScene: false,
          role: ShotAssetRole.subject,
          filePath: '/path/yu.png',
          index: 0,
        ),
        const ResolvedAssetMaterial(
          assetId: 'char_jiang',
          assetName: '姜七夜',
          isScene: false,
          role: ShotAssetRole.confrontation,
          filePath: '/path/jiang.png',
          index: 1,
        ),
      ];

      final prompt = PromptAssembler.buildVideoGenPrompt(
        shot: shot,
        episode: _episode(shots: [shot]),
        characters: [charYu, charJiang],
        scene: sceneStreet,
        materials: materials,
        videoMode: AgnesVideoMode.keyframe,
        hasFirstFrame: true,
      );

      // 验证 keyframe 模式下彻底杜绝【素材指代】
      expect(prompt, isNot(contains('【素材指代】')));
      expect(prompt, isNot(contains('<Picture 1>')));
      expect(prompt, isNot(contains('<Picture 2>')));
      expect(prompt, isNot(contains('形象以<Picture')));

      // 验证因果时间轴中只使用纯角色名驱动动态
      expect(prompt, contains('【因果时间轴】'));
      expect(prompt, contains('余小白'));
      expect(prompt, contains('姜七夜'));
    });

    test('sanitizeForVideoMode 能彻底清洗已缓存 prompt 中的残留 Picture 标签', () {
      const rawCachedPrompt = '''
【素材指代】<Picture 1> = 余小白（主体）；<Picture 2> = 姜七夜（主体）；<Picture 3> = 寒阳城长街（场景，仅作环境空间参考，不作为人物人脸参考）
【同框人物与构图】: 余小白（处于画面主体近景，形象以<Picture 1>为准，分工：主体）；姜七夜（处于画面同框配角，形象以<Picture 2>为准，分工：主体）
【画面微动作】: 天人居三楼窗口探出白胖身子，余小白提着酒杯，居高临下扬声喊住姜七夜。
【因果时间轴】0.0s-0.3s 天人居三楼窗口探出白胖身子，余小白（<Picture 1>）提着酒杯，居高临下扬声喊住姜七夜（<Picture 2>）。 → 0.3s-6.0s 台词（约5.8s）：<Picture 1> 吆！这不是姜七少吗？上来喝一杯啊！
【摄影运镜与机位调度】: 景别：远景，氛围情绪：温馨，运镜调度：static
''';

      final materials = [
        const ResolvedAssetMaterial(
          assetId: 'char_yu',
          assetName: '余小白',
          isScene: false,
          role: ShotAssetRole.subject,
          filePath: '/path/yu.png',
          index: 0,
        ),
        const ResolvedAssetMaterial(
          assetId: 'char_jiang',
          assetName: '姜七夜',
          isScene: false,
          role: ShotAssetRole.confrontation,
          filePath: '/path/jiang.png',
          index: 1,
        ),
      ];

      final sanitized = PromptAssembler.sanitizeForVideoMode(
        rawCachedPrompt,
        mode: AgnesVideoMode.keyframe,
        materials: materials,
      );

      expect(sanitized, isNot(contains('【素材指代】')));
      expect(sanitized, isNot(contains('<Picture 1>')));
      expect(sanitized, isNot(contains('<Picture 2>')));
      expect(sanitized, isNot(contains('<Picture 3>')));
      expect(sanitized, isNot(contains('形象以')));
      expect(sanitized, contains('景别：远景'));
    });
  });

  group('4. 导演决策验证引擎预检规则 (DirectorValidationEngine)', () {
    test('检出高低位垂直落差与远景主体近景冲突 (C05)', () {
      final shot = StudioShot(
        number: 2,
        shotSize: StudioShotSize.long,
        actionZh: '天人居三楼窗口探出白胖身子，余小白提着酒杯，居高临下扬声喊住姜七夜。',
        videoPrompt: '【同框人物与构图】: 余小白（处于画面主体近景，分工：主体）',
        characterIds: ['char_yu', 'char_jiang'],
        sceneId: 'sc_street',
        continuity: const ShotContinuity(
          worldPosition: '寒阳城长街·天人居酒楼前',
          screenPosition: '姜七夜居画面下方街道，余小白位于上方窗框',
          elevationLevel: 'balcony_3f',
        ),
      );

      final report = DirectorValidationEngine.validate(
        episode: _episode(shots: [shot]),
        shots: [shot],
        characters: [charYu, charJiang],
        scenes: [sceneStreet],
      );

      final issue = report.issues.firstWhere(
        (i) => i.ruleName == '垂直构图景别冲突',
      );
      expect(issue.ruleId, 'C05');
      expect(issue.shotNumber, 2);
    });

    test('检出跨镜头坐骑丢失突变 (C05)', () {
      final shot1 = StudioShot(
        number: 1,
        actionZh: '姜七夜骑大黑驴慢行。',
        characterIds: ['char_jiang'],
        sceneId: 'sc_street',
        continuity: const ShotContinuity(
          worldPosition: '寒阳城长街',
          mountOrVehicle: '大黑驴',
        ),
      );

      final shot2 = StudioShot(
        number: 2,
        actionZh: '姜七夜转头看向酒楼。',
        characterIds: ['char_jiang'],
        sceneId: 'sc_street',
        continuity: const ShotContinuity(
          worldPosition: '寒阳城长街',
          mountOrVehicle: '', // 坐骑突变丢失且无下骑动作
        ),
      );

      final report = DirectorValidationEngine.validate(
        episode: _episode(shots: [shot1, shot2]),
        shots: [shot1, shot2],
        characters: [charJiang],
        scenes: [sceneStreet],
      );

      final issue = report.issues.firstWhere(
        (i) => i.ruleName == '坐骑状态丢失',
      );
      expect(issue.ruleId, 'C05');
      expect(issue.shotNumber, 2);
    });

    test('检出 keyframe 模式提示词残留 Picture 标签 (C10)', () {
      final shot = StudioShot(
        number: 2,
        videoMode: 'keyframe',
        actionZh: '余小白喊话。',
        videoPrompt: '【素材指代】<Picture 1> = 余小白；余小白（<Picture 1>）探头喊话',
        characterIds: ['char_yu'],
        sceneId: 'sc_street',
      );

      final report = DirectorValidationEngine.validate(
        episode: _episode(shots: [shot]),
        shots: [shot],
        characters: [charYu],
        scenes: [sceneStreet],
      );

      final issue = report.issues.firstWhere(
        (i) => i.ruleName == '首尾帧模式标签残留',
      );
      expect(issue.ruleId, 'C10');
      expect(issue.shotNumber, 2);
    });
  });
}
