import 'package:flutter_test/flutter_test.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

void main() {
  test('insertTable works cleanly in AppFlowy document', () {
    final doc = Document(
      root: pageNode(
        children: [
          paragraphNode(text: 'First line'),
        ],
      ),
    );
    final editorState = EditorState(document: doc);

    final tableNode = TableNode.fromList([
      [paragraphNode(text: '表头 1'), paragraphNode(text: '表头 2'), paragraphNode(text: '表头 3')],
      [paragraphNode(text: '内容 1'), paragraphNode(text: '内容 2'), paragraphNode(text: '内容 3')],
      [paragraphNode(text: '内容 4'), paragraphNode(text: '内容 5'), paragraphNode(text: '内容 6')],
    ]).node;

    final transaction = editorState.transaction
      ..insertNode([1], tableNode);
    editorState.apply(transaction);

    expect(doc.root.children.length, equals(2));
    expect(doc.root.children[1].type, equals(TableBlockKeys.type));
  });
}
