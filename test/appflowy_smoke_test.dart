import 'package:flutter_test/flutter_test.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

void main() {
  test('AppFlowy Editor smoke test', () {
    final doc = markdownToDocument('''
# Title

This is **bold** and *italic*.

- [ ] Todo item
- [x] Done item

| Header 1 | Header 2 |
| --- | --- |
| Cell 1 | Cell 2 |

```dart
void main() {}
```
''');
    expect(doc.root.children.isNotEmpty, isTrue);
    final md = documentToMarkdown(doc);
    expect(md.contains('Title'), isTrue);
    expect(md.contains('Todo item'), isTrue);

    final json = doc.toJson();
    final docFromJson = Document.fromJson(json);
    expect(docFromJson.root.children.length, equals(doc.root.children.length));
  });
}
