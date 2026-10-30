import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/listening_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/listening_source.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/source_sync_state.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/source_sync_service.dart';

/// 假来源：只用于验证上层对来源无感知。
class _FakeSource implements ListeningSource {
  @override
  String get sourceId => 'fake';

  @override
  String get displayName => 'Fake Source';

  @override
  String get license => 'CC0';

  @override
  Map<String, SourceColumn> get columns => {
        'standup': SourceColumn(
          sourceId: 'fake',
          slug: 'standup',
          displayName: 'Fake Standup',
          scene: MeetingScene.standup,
          pageUrl: 'https://fake.test/standup',
        ),
      };

  @override
  Future<List<SourceDialogue>> fetchDialogues(String columnSlug) async => [
        SourceDialogue(
          column: columns['standup']!,
          pageUrl: 'https://fake.test/standup',
          blockIndex: 0,
          scenarioNote: '',
          turns: const [
            SpeakerTurn(
              speaker: 'Dev',
              role: '',
              rawText: 'Hello.',
              synthesisText: 'Hello.',
              voice: 'v',
            ),
          ],
        ),
      ];

  @override
  Future<String?> siteChangeToken() async => 'fake-token-1';

  @override
  Future<List<SourceColumn>> discoverUnmappedColumns() async => const [];
}

/// 验证「新增来源不触碰上层代码」。
///
/// 这个测试的意义：只要它还编译得过，就说明上层没有引用任何具体来源类。
void main() {
  group('ListeningSource 抽象', () {
    test('假来源能通过抽象接口被消费', () async {
      final source = _FakeSource();
      // 走抽象接口——上层（同步编排）只认这些方法
      expect(source.columns, hasLength(1));
      expect(source.columns['standup']!.scene, MeetingScene.standup);
      final dialogues = await source.fetchDialogues('standup');
      expect(dialogues, hasLength(1));
      expect(dialogues.single.clipId, 'fake_standup_standup_0');
      expect(await source.siteChangeToken(), 'fake-token-1');
    });

    test('来源注册表能按 id 查找', () {
      final registry = ListeningSourceRegistry.instance;
      registry.register(_FakeSource());
      expect(registry.byId('fake'), isNotNull);
      expect(registry.byId('no-such'), isNull);
      registry.byId('fake');
    });

    test('两个来源同名场景不冲突（id 含源前缀）', () {
      final a = SourceColumn(
        sourceId: 'a',
        slug: 'col',
        displayName: 'Col',
        scene: MeetingScene.standup,
        pageUrl: 'https://a/col',
      );
      final b = SourceColumn(
        sourceId: 'b',
        slug: 'col',
        displayName: 'Col',
        scene: MeetingScene.standup,
        pageUrl: 'https://b/col',
      );
      final da = SourceDialogue(
          column: a, pageUrl: a.pageUrl, blockIndex: 0, scenarioNote: '', turns: const []);
      final db = SourceDialogue(
          column: b, pageUrl: b.pageUrl, blockIndex: 0, scenarioNote: '', turns: const []);
      expect(da.clipId, isNot(db.clipId));
      expect(da.clipId, 'a_standup_col_0');
      expect(db.clipId, 'b_standup_col_0');
    });

    test('内容哈希与来源标识绑定（不同来源同内容不算变更）', () {
      final a = SourceSyncState(
          sourceId: 'a', columnSlug: 'col', lastSyncedAt: DateTime(2026), contentHash: 'h');
      final b = SourceSyncState(
          sourceId: 'b', columnSlug: 'col', lastSyncedAt: DateTime(2026), contentHash: 'h');
      // 两个来源各自独立同步
      expect(a.contentChanged(b.contentHash), isFalse);
      expect(a.sourceId, isNot(b.sourceId));
    });
  });
}
