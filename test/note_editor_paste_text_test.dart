import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/ui/note_editor.dart';

/// 接管粘贴命令后的纯文本粘贴行为（capability:
/// `notebook-clipboard-image-paste` 的 "Text pasting behaviour is preserved"）。
///
/// **证据边界，读前务必知道**：这里的断言来自读接管前包内实现
/// （`appflowy_editor` 的 `paste_command.dart`）得出的契约，**不是跑出来的**。
/// 那个 handler 是包内私有的，测试与生产都调不到它。所以本文件证明的是
/// 「接管后符合这份读源码得出的契约」，不宣称「与接管前行为逐位相等」——
/// 后者只能由实机对比确认。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a pasted URL stays plain text', () {
    // 接管前包内有一个 URL→href 的分支，但它排在 deleteSelectionIfNeeded()
    // 之后，而删除后 selection 必然 isCollapsed，该分支的守卫又要求
    // isCollapsed == false —— 永远不可达。所以接管前粘 URL 也是纯文本。
    // 这里钉住"我们没有把死分支抄成活的"。
    test('URL is inserted as text, not as a link', () async {
      final state = _stateWithDoc('第一段');

      await insertPlainTextPaste(state, 'https://example.com');

      final hrefs = _collectHrefs(state);
      expect(hrefs, isEmpty, reason: '接管前也不会变链接');
      expect(_allText(state), contains('https://example.com'));
    });

    test('phone number is inserted as text, not as a tel: link', () async {
      final state = _stateWithDoc('第一段');

      await insertPlainTextPaste(state, '13800138000');

      expect(_collectHrefs(state), isEmpty);
      expect(_allText(state), contains('13800138000'));
    });
  });

  group('insertPlainTextPaste', () {
    test('single line continues in the current paragraph', () async {
      // 接管前 pasteSingleLineNode 的语义是"在光标处续写"，不是新建段落——
      // 只有当目标段落本身为空时才整段替换。这条钉住那个语义。
      final state = _stateWithDoc('第一段');

      await insertPlainTextPaste(state, '新的一行');

      expect(state.document.root.children.length, 1);
      expect(
        state.document.root.children.single.delta!.toPlainText(),
        '第一段新的一行',
      );
    });

    test('single line into an empty paragraph replaces it', () async {
      final state = _stateWithDoc('');

      await insertPlainTextPaste(state, '只有一行');

      expect(state.document.root.children.length, 1);
      expect(
        state.document.root.children.single.delta!.toPlainText(),
        '只有一行',
      );
    });

    test('multiple lines merge into the current paragraph then split', () async {
      // pasteMultiLineNodes 的语义：当前段在光标之前的内容并入第一个新节点，
      // 之后按行拆段。所以 '第一段' + 三行 = 3 个节点，第一个是 '第一段行一'。
      final state = _stateWithDoc('第一段');

      await insertPlainTextPaste(state, '行一\n行二\n行三');

      expect(state.document.root.children.length, 3);
      expect(state.document.root.children[0].delta!.toPlainText(), '第一段行一');
      expect(state.document.root.children[1].delta!.toPlainText(), '行二');
      expect(state.document.root.children[2].delta!.toPlainText(), '行三');
    });

    test('CR is stripped and trailing whitespace trimmed', () async {
      final state = _stateWithDoc('第一段');

      await insertPlainTextPaste(state, 'windows 行\r\n带尾空格   ');

      expect(state.document.root.children.length, 2);
      expect(state.document.root.children[0].delta!.toPlainText(), '第一段windows 行');
      expect(state.document.root.children[1].delta!.toPlainText(), '带尾空格');
    });

    test('a URL replaces the selected text', () async {
      final state = _stateWithDoc('要被替换的旧内容');
      _selectAll(state);

      await insertPlainTextPaste(state, 'https://example.com');

      final all = _allText(state);
      expect(all, isNot(contains('要被替换的旧内容')));
      expect(all, contains('https://example.com'));
    });

    test('inline attributes at the selection are inherited', () async {
      // 光标落在加粗段内：接管前用 getDeltaAttributesInSelectionStart() 取
      // 行内属性并带给新插入的文本。
      final state = _stateWithDoc('第一段');
      // 文档只有一段（path [0]），直接把它整段设成加粗。
      final fmtTx = state.transaction;
      fmtTx.formatText(state.getNodeAtPath([0])!, 0, 3, {
        AppFlowyRichTextKeys.bold: true,
      });
      await state.apply(fmtTx);
      state.updateSelectionWithReason(
        Selection.single(path: [0], startOffset: 1),
        reason: SelectionUpdateReason.uiEvent,
      );
      expect(
        state.getDeltaAttributesInSelectionStart(),
        isNotNull,
        reason: '测试前提：光标处必须读得到行内属性',
      );

      await insertPlainTextPaste(state, '续写');

      final target = state.getNodeAtPath([0])!;
      // 光标在 offset 1（"第"之后），所以续写插在"第"与"一段"之间。
      expect(target.delta!.toPlainText(), '第续写一段');
      // Delta 会把相邻同属性的 insert 合并成一个 op，所以不能按
      // op.data == '续写' 精确定位；整段同属性即证明粘贴文本继承了加粗。
      final allBold = target.delta!
          .whereType<TextInsert>()
          .every((op) => op.attributes?[AppFlowyRichTextKeys.bold] == true);
      expect(
        allBold,
        isTrue,
        reason: '粘贴文本必须继承光标处的行内属性',
      );
    });

    test('a non-empty selection is replaced, not appended after', () async {
      final state = _stateWithDoc('要被替换掉的旧内容');
      _selectAll(state);

      await insertPlainTextPaste(state, '新内容');

      // 接管前 deleteSelectionIfNeeded() 先删选中区；若漏了这一步，粘贴会
      // 变成"追加"，原文还在。
      final all = state.document.root.children
          .map((n) => n.delta?.toPlainText() ?? '')
          .join();
      expect(all, isNot(contains('要被替换掉的旧内容')));
      expect(all, contains('新内容'));
    });
  });
}

EditorState _stateWithDoc(String text) {
  // 必须是 Document(root: pageNode(children: [...]))——直接拿 paragraphNode
  // 当 root 会得到 0 个 children（它自己被当成 page），后面全部断言都会空。
  final doc = Document(
    root: pageNode(children: [paragraphNode(delta: Delta()..insert(text))]),
  );
  final state = EditorState(document: doc);
  state.updateSelectionWithReason(
    Selection.single(path: [0], startOffset: text.length),
    reason: SelectionUpdateReason.uiEvent,
  );
  return state;
}

/// 选中整篇文档内容，模拟用户按下 ⌘A 之后的状态。
void _selectAll(EditorState state) {
  final first = state.document.root.children.first;
  final length = first.delta?.length ?? 0;
  state.updateSelectionWithReason(
    Selection.single(path: first.path, startOffset: 0, endOffset: length),
    reason: SelectionUpdateReason.uiEvent,
  );
}

Set<String> _collectHrefs(EditorState state) {
  final hrefs = <String>{};
  for (final node in state.document.root.children) {
    for (final op in node.delta!.whereType<TextInsert>()) {
      final href = op.attributes?[AppFlowyRichTextKeys.href];
      if (href is String) hrefs.add(href);
    }
  }
  return hrefs;
}

String _allText(EditorState state) {
  return state.document.root.children
      .map((n) => n.delta?.toPlainText() ?? '')
      .join();
}

