import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/appflowy_codec.dart';
import 'package:V8WorkToolbox/tools/notebook/markdown_converter.dart';

/// 数一数 document 里 attachment 节点的个数。
int _attachmentCount(String deltaJson) {
  final doc = AppFlowyCodec.parseToDocument(deltaJson);
  return doc.root.children.where((n) => n.type == 'attachment').length;
}

/// 取出第 [index] 个段落节点的纯文本。
String _paragraphText(String deltaJson, int index) {
  final doc = AppFlowyCodec.parseToDocument(deltaJson);
  return doc.root.children.elementAt(index).delta?.toPlainText().trim() ?? '';
}

void main() {
  group('replacePlaceholderWithAttachment', () {
    test('占位段落被替换为 attachment 节点，且位置保持', () {
      const placeholder = '{{attachment:local:image1.png}}';
      final json = MarkdownConverter.markdownToDelta(
        '第一段\n\n$placeholder\n\n第三段',
      );
      expect(_attachmentCount(json), 0);

      final out = AppFlowyCodec.replacePlaceholderWithAttachment(
        json,
        placeholder: placeholder,
        attachmentId: 'att-abc',
        filename: 'image1.png',
        sizeBytes: 4096,
        mime: 'image/png',
      );

      // 附件节点出现
      expect(_attachmentCount(out), 1);
      // 占位文字消失
      expect(out, isNot(contains(placeholder)));
      expect(_paragraphText(out, 0), '第一段');
      expect(_paragraphText(out, 1), isNot(placeholder));
      expect(_attachmentCount(out), 1);
      // 位置：附件节点应在中间，第三段仍在最后
      expect(_paragraphText(out, 2), '第三段');
    });

    test('无匹配占位时原样返回', () {
      final json = MarkdownConverter.markdownToDelta('只有文字，没有占位');
      final out = AppFlowyCodec.replacePlaceholderWithAttachment(
        json,
        placeholder: '{{attachment:local:nope.png}}',
        attachmentId: 'att-1',
        filename: 'nope.png',
        sizeBytes: 10,
        mime: 'image/png',
      );
      // 注意不能断言字符串相等：入参是 quill delta 序列化，
      // 出参经过 parseToDocument → documentToJson 是 appflowy document 序列化，
      // 同一文档的两种编码。断言"没有附件节点"即可。
      expect(_attachmentCount(out), 0);
      expect(out, contains('只有文字，没有占位'));
    });

    test('mime 写入节点属性（附件块据此渲染图片预览）', () {
      const placeholder = '{{attachment:local:a.png}}';
      final json = MarkdownConverter.markdownToDelta(placeholder);
      final out = AppFlowyCodec.replacePlaceholderWithAttachment(
        json,
        placeholder: placeholder,
        attachmentId: 'att-x',
        filename: 'a.png',
        sizeBytes: 20,
        mime: 'image/png',
      );
      final doc = AppFlowyCodec.parseToDocument(out);
      final node = doc.root.children.firstWhere((n) => n.type == 'attachment');
      expect(node.attributes['attachmentId'], 'att-x');
      expect(node.attributes['filename'], 'a.png');
      expect(node.attributes['mime'], 'image/png');
      expect(node.attributes['sizeBytes'], 20);
    });
  });
}
