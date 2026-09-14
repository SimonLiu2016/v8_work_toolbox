import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

class MindMapBlockKeys {
  static const String type = 'mindmap';
  static const String data = 'data';
}

Node mindMapNode({required String data}) {
  return Node(
    type: MindMapBlockKeys.type,
    attributes: {
      MindMapBlockKeys.data: data,
    },
  );
}

class MindMapBlockComponentBuilder extends BlockComponentBuilder {
  MindMapBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return MindMapBlockComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (context, state) => actionBuilder(
        blockComponentContext,
        state,
      ),
      actionTrailingBuilder: (context, state) => actionTrailingBuilder(
        blockComponentContext,
        state,
      ),
    );
  }
}

class MindMapBlockComponentWidget extends BlockComponentStatefulWidget {
  const MindMapBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<MindMapBlockComponentWidget> createState() => _MindMapBlockComponentWidgetState();
}

class _MindMapBlockComponentWidgetState extends State<MindMapBlockComponentWidget>
    with BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.blue.shade50,
      child: Text('Mindmap: ${widget.node.attributes[MindMapBlockKeys.data]}'),
    );
  }
}

void main() {
  testWidgets('custom mindmap block component builder works', (tester) async {
    final doc = Document(
      root: pageNode(
        children: [
          paragraphNode(text: 'Hello'),
          mindMapNode(data: 'test-data'),
        ],
      ),
    );
    final editorState = EditorState(document: doc);

    final builders = {
      ...standardBlockComponentBuilderMap,
      MindMapBlockKeys.type: MindMapBlockComponentBuilder(),
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppFlowyEditor(
            editorState: editorState,
            blockComponentBuilders: builders,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mindmap: test-data'), findsOneWidget);
  });
}
