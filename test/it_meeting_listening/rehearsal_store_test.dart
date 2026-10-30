import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:V8WorkToolbox/tools/it_meeting_listening/models/listening_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/rehearsal_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/clip_library.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/rehearsal_store.dart';

void main() {
  late Directory tmp;
  late RehearsalStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rehearsal_store_test');
    store = RehearsalStore(root: tmp);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  RehearsalMaterial material(String id) => RehearsalMaterial(
        id: id,
        title: 't$id',
        sourcePath: '/x/$id.md',
        fileName: '$id.md',
        text: 'content $id',
        importedAt: DateTime(2026, 10, 22),
      );

  SpeechDraft draft(String materialId) => SpeechDraft(
        id: 'draft_$materialId',
        materialId: materialId,
        title: 'draft',
        sections: const [DraftSection(title: 'A', body: 'aa')],
        generatedAt: DateTime(2026, 10, 22),
      );

  MeetingScript script(String materialId) => MeetingScript(
        id: 'script_$materialId',
        materialId: materialId,
        draftId: 'draft_$materialId',
        title: 'script',
        turns: const [
          ScriptTurn(role: RehearsalRole.simon, text: 'Hello.'),
          ScriptTurn(role: RehearsalRole.josh, text: 'Hi.'),
        ],
        targetMinutes: 30,
        generatedAt: DateTime(2026, 10, 22),
      );

  group('三阶段产物各自独立落盘', () {
    test('材料、讲稿、剧本分别存取', () async {
      await store.saveMaterial(material('mat_1'));
      await store.saveDraft(draft('mat_1'));
      await store.saveScript(script('mat_1'));

      expect((await store.loadMaterial('mat_1'))!.text, 'content mat_1');
      expect((await store.loadDraft('mat_1'))!.sections, hasLength(1));
      expect((await store.loadScript('mat_1'))!.turns, hasLength(2));
    });

    test('改讲稿不丢剧本，改剧本不丢材料', () async {
      await store.saveMaterial(material('mat_1'));
      await store.saveDraft(draft('mat_1'));
      await store.saveScript(script('mat_1'));

      // 用户改讲稿
      await store.saveDraft(SpeechDraft(
        id: 'draft_mat_1',
        materialId: 'mat_1',
        title: 'edited',
        sections: const [
          DraftSection(title: 'A', body: 'aa'),
          DraftSection(title: 'B', body: 'bb'),
        ],
        generatedAt: DateTime(2026, 10, 23),
      ));

      expect((await store.loadDraft('mat_1'))!.sections, hasLength(2));
      // 剧本与材料原样
      expect((await store.loadScript('mat_1'))!.turns, hasLength(2));
      expect((await store.loadMaterial('mat_1'))!.text, 'content mat_1');
    });

    test('同一材料重复导入覆盖旧产物', () async {
      await store.saveDraft(draft('mat_1'));
      await store.saveDraft(SpeechDraft(
        id: 'draft_mat_1',
        materialId: 'mat_1',
        title: 'v2',
        sections: const [DraftSection(title: 'A', body: 'aa')],
        generatedAt: DateTime(2026, 10, 23),
      ));
      expect((await store.loadDraft('mat_1'))!.title, 'v2');
    });

    test('材料列表按导入时间倒序', () async {
      await store.saveMaterial(material('a'));
      await store.saveMaterial(RehearsalMaterial(
        id: 'b',
        title: 'tb',
        sourcePath: '/x/b.md',
        fileName: 'b.md',
        text: 'newer',
        importedAt: DateTime(2026, 10, 23),
      ));
      final list = await store.listMaterials();
      expect(list.first.id, 'b');
    });
  });

  group('降级', () {
    test('缺失文件返回 null 而不是抛异常', () async {
      expect(await store.loadMaterial('nope'), isNull);
      expect(await store.loadDraft('nope'), isNull);
      expect(await store.loadScript('nope'), isNull);
    });

    test('损坏 JSON 返回 null 而不是崩溃', () async {
      final dir = Directory('${tmp.path}/drafts');
      await dir.create(recursive: true);
      await File('${dir.path}/broken.json').writeAsString('{not json');
      expect(await store.loadDraft('broken'), isNull);
    });

    test('单个材料损坏不影响列表其余部分', () async {
      await store.saveMaterial(material('good'));
      final dir = Directory('${tmp.path}/materials');
      await dir.create(recursive: true);
      await File('${dir.path}/bad.json').writeAsString('nope');
      final list = await store.listMaterials();
      expect(list.map((m) => m.id), ['good']);
    });
  });

  group('合成中间结果回写', () {
    test('回填轮次时间戳，其它字段不变', () async {
      await store.saveScript(script('mat_1'));
      final updated = [
        const ScriptTurn(
            role: RehearsalRole.simon, text: 'Hello.', startMs: 0, endMs: 3200),
        const ScriptTurn(
            role: RehearsalRole.josh,
            text: 'Hi.',
            startMs: 3200,
            endMs: 5100,
            failed: true),
      ];
      await store.saveScriptTurns('mat_1', updated);

      final loaded = (await store.loadScript('mat_1'))!;
      expect(loaded.turns.first.startMs, 0);
      expect(loaded.turns.first.endMs, 3200);
      expect(loaded.turns.last.failed, isTrue);
      // 标题与目标时长未被抹掉
      expect(loaded.title, 'script');
      expect(loaded.targetMinutes, 30);
    });

    test('剧本不存在时回写是空操作', () async {
      await store.saveScriptTurns('nope', const []);
      expect(await store.loadScript('nope'), isNull);
    });
  });

  group('多场排练扩展与讲稿编辑过期判定', () {
    test('RehearsalMaterial 新增 targetMinutes 与 displayTitle 且兼容旧 JSON', () {
      final legacy = RehearsalMaterial.fromJson({
        'id': 'mat_old',
        'title': 'Old Title',
        'sourcePath': '/a/old.md',
        'fileName': 'old.md',
        'text': 'body',
        'importedAt': '2026-10-20T00:00:00.000Z',
      });
      expect(legacy.targetMinutes, 30);
      expect(legacy.displayTitle, isNull);
      expect(legacy.effectiveTitle, 'Old Title');

      final renamed = legacy.copyWith(displayTitle: 'Custom Title', targetMinutes: 60);
      final roundTrip = RehearsalMaterial.fromJson(renamed.toJson());
      expect(roundTrip.targetMinutes, 60);
      expect(roundTrip.effectiveTitle, 'Custom Title');
    });

    test('SpeechDraft 编辑保存生成新 id 并使旧剧本判定为过期', () {
      final mat = material('mat_1');
      final initialDraft = draft('mat_1');
      final initialScript = script('mat_1');

      final statusBefore = RehearsalStatusInfo(
        material: mat,
        draft: initialDraft,
        script: initialScript,
      );
      expect(statusBefore.isScriptStale, isFalse);
      expect(statusBefore.stage, RehearsalStage.scriptReady);

      final editedDraft = initialDraft.copyWithEdited(
        title: 'Edited Draft',
        editedAt: DateTime(2026, 10, 24),
      );
      expect(editedDraft.isEdited, isTrue);
      expect(editedDraft.id, isNot(initialDraft.id));

      final statusAfter = RehearsalStatusInfo(
        material: mat,
        draft: editedDraft,
        script: initialScript,
      );
      expect(statusAfter.isScriptStale, isTrue);
      expect(statusAfter.stage, RehearsalStage.scriptStale);
    });

    test('deleteMaterial 删除全部中间产物、音频并从素材索引移除', () async {
      final matDir = Directory(p.join(tmp.path, 'materials_audio'));
      final cacheDir = Directory(p.join(tmp.path, 'cache_audio'));
      await matDir.create(recursive: true);
      await cacheDir.create(recursive: true);
      final library = ClipLibrary(matDir);

      await store.saveMaterial(material('mat_1'));
      await store.saveDraft(draft('mat_1'));
      await store.saveScript(script('mat_1'));

      final clipId = RehearsalStatusInfo.clipIdFor('mat_1');
      final audioFile = File(p.join(matDir.path, '$clipId.mp3'));
      await audioFile.writeAsString('audio');
      final turnCache = File(p.join(cacheDir.path, '${clipId}_t0_s0.mp3'));
      await turnCache.writeAsString('turn');

      await library.rebuildIndex([
        Clip(
          id: clipId,
          scene: MeetingScene.rehearsal,
          title: 'Rehearsal 1',
          audioPath: '$clipId.mp3',
          durationMs: 60000,
          turns: const [],
          source: const ClipSource(
            sourceId: 'rehearsal',
            site: '排练会议',
            pageUrl: '',
            column: 'Rehearsal 1',
          ),
        ),
      ]);

      await store.deleteMaterial(
        'mat_1',
        library: library,
        materialDir: matDir,
        cacheDir: cacheDir,
      );

      expect(await store.loadMaterial('mat_1'), isNull);
      expect(await store.loadDraft('mat_1'), isNull);
      expect(await store.loadScript('mat_1'), isNull);
      expect(await audioFile.exists(), isFalse);
      expect(await turnCache.exists(), isFalse);
      expect((await library.loadIndex()).byId(clipId), isNull);
    });
  });
}
