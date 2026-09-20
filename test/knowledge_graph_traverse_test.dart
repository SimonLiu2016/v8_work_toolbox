import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:V8WorkToolbox/tools/notebook/note_database.dart';
import 'package:V8WorkToolbox/tools/notebook/notebook_kb_service.dart';
import 'package:V8WorkToolbox/tools/notebook/note_store.dart';

/// 星图多跳遍历测试。
///
/// traverse 读的是 NoteStore.instance.allLinks()（单例 + path_provider），
/// 故此处直接验证 BFS 的**纯逻辑**：用 NoteDatabase 建图后，
/// 复用一个与 traverse 同构的内存 BFS 断言语义（跳数、环路、上限）。
/// 端到端（真实 NoteStore）由手工验证 4.3.1 覆盖。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NoteDatabase db;
  final now = DateTime.now();

  Future<void> note(String id) => db.insertNote(NotesCompanion.insert(
        id: id, title: id, deltaJson: '[]', createdAt: now, updatedAt: now,
      ));

  Future<void> link(String a, String b) => db.insertLink(
      NoteLinksCompanion.insert(sourceNoteId: a, targetNoteId: b, createdAt: now));

  setUp(() async {
    db = NoteDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => await db.close());

  /// 与 NotebookKbService.traverse 同构的内存 BFS（验证语义，不依赖单例）。
  List<GraphPath> bfs(
    Map<String, Set<String>> adj,
    String start, {
    int hops = 2,
    int maxPaths = 50,
  }) {
    if (hops <= 0) return const [];
    final results = <GraphPath>[];
    final visited = <String>{start};
    var frontier = <List<String>>[
      [start]
    ];
    for (var depth = 1; depth <= hops; depth++) {
      final next = <List<String>>[];
      for (final path in frontier) {
        for (final n in adj[path.last] ?? const <String>{}) {
          if (visited.contains(n)) continue;
          visited.add(n);
          final np = [...path, n];
          results.add(GraphPath(noteIds: np, hops: depth));
          next.add(np);
          if (results.length >= maxPaths) break;
        }
        if (results.length >= maxPaths) break;
      }
      if (results.length >= maxPaths || next.isEmpty) break;
      frontier = next;
    }
    return results;
  }

  Future<Map<String, Set<String>>> adjacency() async {
    final links = await db.allLinks();
    final adj = <String, Set<String>>{};
    for (final l in links) {
      adj.putIfAbsent(l.sourceNoteId, () => {}).add(l.targetNoteId);
      adj.putIfAbsent(l.targetNoteId, () => {}).add(l.sourceNoteId);
    }
    return adj;
  }

  group('BFS 跳数与路径', () {
    test('一跳可达', () async {
      await note('a');
      await note('b');
      await link('a', 'b');
      final paths = bfs(await adjacency(), 'a', hops: 1);
      expect(paths.length, 1);
      expect(paths.first.noteIds, ['a', 'b']);
      expect(paths.first.hops, 1);
    });

    test('两跳链式可达', () async {
      for (final id in ['a', 'b', 'c']) {
        await note(id);
      }
      await link('a', 'b');
      await link('b', 'c');
      final paths = bfs(await adjacency(), 'a', hops: 2);
      final ends = paths.map((p) => p.end).toSet();
      expect(ends, {'b', 'c'});
      final toC = paths.firstWhere((p) => p.end == 'c');
      expect(toC.noteIds, ['a', 'b', 'c']);
      expect(toC.hops, 2);
    });

    test('hops 限制截断更远的节点', () async {
      for (final id in ['a', 'b', 'c', 'd']) {
        await note(id);
      }
      await link('a', 'b');
      await link('b', 'c');
      await link('c', 'd');
      final paths = bfs(await adjacency(), 'a', hops: 2);
      expect(paths.map((p) => p.end).toSet(), {'b', 'c'});
      expect(paths.any((p) => p.end == 'd'), isFalse);
    });

    test('无关联返回空', () async {
      await note('a');
      expect(bfs(await adjacency(), 'a'), isEmpty);
    });

    test('hops=0 返回空', () async {
      await note('a');
      await note('b');
      await link('a', 'b');
      expect(bfs(await adjacency(), 'a', hops: 0), isEmpty);
    });
  });

  group('环路防护', () {
    test('双向边不导致重复访问', () async {
      await note('a');
      await note('b');
      // a→b 与 b→a 是两条独立行（有向），构成环
      await link('a', 'b');
      await link('b', 'a');
      final paths = bfs(await adjacency(), 'a', hops: 3);
      expect(paths.length, 1, reason: 'b 应只被访问一次');
      expect(paths.first.noteIds, ['a', 'b']);
    });

    test('三角形环不无限循环', () async {
      for (final id in ['a', 'b', 'c']) {
        await note(id);
      }
      await link('a', 'b');
      await link('b', 'c');
      await link('c', 'a');
      final paths = bfs(await adjacency(), 'a', hops: 5);
      // b 与 c 各一条最短路径，回到 a 的边被 visited 拦截
      expect(paths.map((p) => p.end).toSet(), {'b', 'c'});
    });

    test('长链在 hops 内终止', () async {
      for (var i = 0; i < 20; i++) {
        await note('n$i');
      }
      for (var i = 0; i < 19; i++) {
        await link('n$i', 'n${i + 1}');
      }
      final paths = bfs(await adjacency(), 'n0', hops: 3);
      expect(paths.length, 3, reason: 'n1/n2/n3 各一跳，不应继续外扩');
      expect(paths.map((p) => p.end).toSet(), {'n1', 'n2', 'n3'});
    });
  });

  group('GraphPath 模型', () {
    test('start / end 取首尾', () {
      const p = GraphPath(noteIds: ['a', 'b', 'c'], hops: 2);
      expect(p.start, 'a');
      expect(p.end, 'c');
      expect(p.hops, 2);
    });
  });

  group('traverse 在无初始化时安全降级', () {
    test('无 note_store 初始化时返回空而非抛异常', () async {
      // NoteStore.instance 未 init，allLinks 会走 db getter 的断言；
      // traverse 内部 try/catch 应吞掉并返回空列表。
      final out = await NotebookKbService.instance.traverse('any', hops: 2);
      expect(out, isEmpty);
    });
  });

  group('RelatedNote 与图数据一致性', () {
    test('allLinks 返回的行可用于建邻接表', () async {
      await note('a');
      await note('b');
      await link('a', 'b');
      final links = await db.allLinks();
      expect(links.length, 1);
      final adj = <String, Set<String>>{};
      for (final l in links) {
        adj.putIfAbsent(l.sourceNoteId, () => {}).add(l.targetNoteId);
        adj.putIfAbsent(l.targetNoteId, () => {}).add(l.sourceNoteId);
      }
      expect(adj['a'], {'b'});
      expect(adj['b'], {'a'}, reason: '无向遍历：反向也可达');
    });

    test('RelatedNote 携带方向标记', () {
      const r = RelatedNote(noteId: 'n', title: 't', outgoing: false);
      expect(r.outgoing, isFalse);
    });
  });
}
