import 'package:flutter_test/flutter_test.dart';

class MockNote {
  final String id;
  final String title;
  final String? notebookId;
  final bool isDeleted;

  const MockNote({
    required this.id,
    required this.title,
    this.notebookId,
    this.isDeleted = false,
  });
}

class MockNotebook {
  final String id;
  final String name;
  final String? stack;

  const MockNotebook({
    required this.id,
    required this.name,
    this.stack,
  });
}

/// 模拟跨视图跳转时的导航同步状态决策
class NavigationState {
  String? selectedNotebookId;
  String? selectedStack;
  String? selectedTagId;
  String searchQuery = '';
  bool isTrashSelected = false;
  bool isBatchMode = false;
  MockNote? selectedNote;

  void applyJumpToNote(MockNote note, List<MockNotebook> notebooks) {
    MockNotebook? targetNb;
    if (note.notebookId != null) {
      for (final nb in notebooks) {
        if (nb.id == note.notebookId) {
          targetNb = nb;
          break;
        }
      }
    }

    isTrashSelected = note.isDeleted;
    selectedNotebookId = note.notebookId;
    selectedStack = targetNb?.stack;
    selectedTagId = null;
    searchQuery = '';
    isBatchMode = false;
    selectedNote = note;
  }
}

void main() {
  final testNotebooks = [
    const MockNotebook(id: 'nb-work', name: '工作笔记', stack: '职场'),
    const MockNotebook(id: 'nb-life', name: '生活随笔', stack: null),
  ];

  group('跨视图跳转导航同步逻辑测试', () {
    test('从其他笔记本跳转到带有 stack 的笔记本中的笔记', () {
      final state = NavigationState()
        ..selectedNotebookId = 'nb-life'
        ..selectedTagId = 'tag-fitness'
        ..searchQuery = '跑步'
        ..isBatchMode = true;

      const targetNote = MockNote(
        id: 'note-project-plan',
        title: 'Q4 架构演进方案',
        notebookId: 'nb-work',
      );

      state.applyJumpToNote(targetNote, testNotebooks);

      expect(state.selectedNotebookId, 'nb-work');
      expect(state.selectedStack, '职场');
      expect(state.selectedTagId, isNull);
      expect(state.searchQuery, '');
      expect(state.isBatchMode, isFalse);
      expect(state.isTrashSelected, isFalse);
      expect(state.selectedNote?.id, 'note-project-plan');
    });

    test('跳转到无笔记本归属的独立笔记时切回全部笔记', () {
      final state = NavigationState()
        ..selectedNotebookId = 'nb-work'
        ..searchQuery = '架构';

      const targetNote = MockNote(
        id: 'note-standalone',
        title: '闪念笔记',
        notebookId: null,
      );

      state.applyJumpToNote(targetNote, testNotebooks);

      expect(state.selectedNotebookId, isNull);
      expect(state.selectedStack, isNull);
      expect(state.searchQuery, '');
      expect(state.selectedNote?.id, 'note-standalone');
    });

    test('跳转到回收站中的已删除笔记', () {
      final state = NavigationState()..selectedNotebookId = 'nb-work';

      const targetNote = MockNote(
        id: 'note-deleted',
        title: '已弃用方案',
        notebookId: 'nb-work',
        isDeleted: true,
      );

      state.applyJumpToNote(targetNote, testNotebooks);

      expect(state.isTrashSelected, isTrue);
      expect(state.selectedNote?.id, 'note-deleted');
    });
  });
}
