import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/markdown_converter.dart';

void main() {
  group('MarkdownConverter Delta → Markdown', () {
    test('空文档', () {
      final delta = '[{"insert":"\\n"}]';
      final md = MarkdownConverter.deltaToMarkdown(delta);
      expect(md.trim(), isEmpty);
    });

    test('纯文本段落', () {
      final delta = '[{"insert":"Hello World\\n"}]';
      final md = MarkdownConverter.deltaToMarkdown(delta);
      expect(md.contains('Hello World'), isTrue);
    });

    test('标题 h1-h3', () {
      final delta = '[{"insert":"H1"},{"insert":"\\n","attributes":{"header":1}},'
          '{"insert":"H2"},{"insert":"\\n","attributes":{"header":2}},'
          '{"insert":"H3"},{"insert":"\\n","attributes":{"header":3}}]';
      final md = MarkdownConverter.deltaToMarkdown(delta);
      expect(md.contains('# H1'), isTrue);
      expect(md.contains('## H2'), isTrue);
      expect(md.contains('### H3'), isTrue);
    });

    test('加粗文本', () {
      final delta = '[{"insert":"bold text","attributes":{"bold":true}},{"insert":"\\n"}]';
      final md = MarkdownConverter.deltaToMarkdown(delta);
      expect(md.contains('**bold text**'), isTrue);
    });

    test('斜体文本', () {
      final delta = '[{"insert":"italic text","attributes":{"italic":true}},{"insert":"\\n"}]';
      final md = MarkdownConverter.deltaToMarkdown(delta);
      expect(md.contains('*italic text*'), isTrue);
    });

    test('行内代码', () {
      final delta = '[{"insert":"code","attributes":{"code":true}},{"insert":"\\n"}]';
      final md = MarkdownConverter.deltaToMarkdown(delta);
      expect(md.contains('`code`'), isTrue);
    });

    test('删除线', () {
      final delta = '[{"insert":"deleted","attributes":{"strike":true}},{"insert":"\\n"}]';
      final md = MarkdownConverter.deltaToMarkdown(delta);
      expect(md.contains('~~deleted~~'), isTrue);
    });

    test('无序列表', () {
      final delta = '[{"insert":"item1"},{"insert":"\\n","attributes":{"list":"bullet"}},'
          '{"insert":"item2"},{"insert":"\\n","attributes":{"list":"bullet"}}]';
      final md = MarkdownConverter.deltaToMarkdown(delta);
      expect(md.contains('- item1'), isTrue);
      expect(md.contains('- item2'), isTrue);
    });

    test('链接', () {
      final delta = '[{"insert":"click","attributes":{"link":"https://example.com"}},{"insert":"\\n"}]';
      final md = MarkdownConverter.deltaToMarkdown(delta);
      expect(md.contains('[click](https://example.com)'), isTrue);
    });

    test('图片 embed', () {
      final delta = '[{"insert":{"image":"/path/to/img.png"}},{"insert":"\\n"}]';
      final md = MarkdownConverter.deltaToMarkdown(delta);
      expect(md.contains('![](/path/to/img.png)'), isTrue);
    });
  });

  group('MarkdownConverter Markdown → Delta', () {
    test('纯文本段落', () {
      final delta = MarkdownConverter.markdownToDelta('Hello World');
      expect(delta.contains('Hello World'), isTrue);
    });

    test('标题 h1', () {
      final delta = MarkdownConverter.markdownToDelta('# Title');
      expect(delta.contains('Title'), isTrue);
      expect(delta.contains('"header":1'), isTrue);
    });

    test('标题 h2', () {
      final delta = MarkdownConverter.markdownToDelta('## Subtitle');
      expect(delta.contains('Subtitle'), isTrue);
      expect(delta.contains('"header":2'), isTrue);
    });

    test('加粗', () {
      final delta = MarkdownConverter.markdownToDelta('**bold**');
      expect(delta.contains('bold'), isTrue);
      expect(delta.contains('"bold":true'), isTrue);
    });

    test('斜体', () {
      final delta = MarkdownConverter.markdownToDelta('*italic*');
      expect(delta.contains('italic'), isTrue);
      expect(delta.contains('"italic":true'), isTrue);
    });

    test('行内代码', () {
      final delta = MarkdownConverter.markdownToDelta('`code`');
      expect(delta.contains('code'), isTrue);
      expect(delta.contains('"code":true'), isTrue);
    });

    test('删除线', () {
      final delta = MarkdownConverter.markdownToDelta('~~deleted~~');
      expect(delta.contains('deleted'), isTrue);
      expect(delta.contains('"strike":true'), isTrue);
    });

    test('无序列表', () {
      final delta = MarkdownConverter.markdownToDelta('- item\n- item2');
      expect(delta.contains('"list":"bullet"'), isTrue);
    });

    test('有序列表', () {
      final delta = MarkdownConverter.markdownToDelta('1. first\n2. second');
      expect(delta.contains('"list":"ordered"'), isTrue);
    });

    test('链接', () {
      final delta = MarkdownConverter.markdownToDelta('[text](url)');
      expect(delta.contains('text'), isTrue);
      expect(delta.contains('"link":"url"'), isTrue);
    });

    test('引用块', () {
      final delta = MarkdownConverter.markdownToDelta('> quote');
      expect(delta.contains('quote'), isTrue);
      expect(delta.contains('"blockquote":true'), isTrue);
    });

    test('代码块', () {
      final delta = MarkdownConverter.markdownToDelta('```js\ncode\n```');
      expect(delta.contains('code'), isTrue);
      expect(delta.contains('"code_block"') || delta.contains('"code-block"'), isTrue);
    });

    test('水平分割线', () {
      final delta = MarkdownConverter.markdownToDelta('---');
      expect(delta.contains('"divider":true'), isTrue);
    });
  });

  group('MarkdownConverter 表格', () {
    test('Delta 表格 embed 渲染为 GFM 管道表格', () {
      final delta = jsonEncode([
        {
          'insert': {
            'table': {
              'rows': [
                [
                  {'text': '姓名', 'style': 'header'},
                  {'text': '年龄', 'style': 'header'},
                ],
                [
                  {'text': '张三', 'style': ''},
                  {'text': '30', 'style': ''},
                ],
                [
                  {'text': '李四', 'style': ''},
                  {'text': '25', 'style': ''},
                ],
              ]
            }
          }
        },
        {'insert': '\n'}
      ]);
      final md = MarkdownConverter.deltaToMarkdown(delta);
      expect(md.contains('姓名'), isTrue, reason: '首行应为表头行');
      expect(md.contains('年龄'), isTrue);
      expect(md.contains('---'), isTrue, reason: '应有分隔行');
      expect(md.contains('张三'), isTrue);
      expect(md.contains('30'), isTrue);
      expect(md.contains('李四'), isTrue);
      expect(md.contains('25'), isTrue);
    });

    test('Markdown 表格解析为 table embed', () {
      final md = '|姓名 |年龄|\n| --- | --- |\n|张三 |30|';
      final delta = MarkdownConverter.markdownToDelta(md);
      expect(delta.contains('"table"'), isTrue, reason: '应生成 table embed');
      expect(delta.contains('"rows"'), isTrue);
      expect(delta.contains('张三'), isTrue);
    });

    test('表格往返保持行列内容', () {
      const md = '|A |B|\n| --- | --- |\n|1 |2|';
      final md2 = MarkdownConverter.deltaToMarkdown(MarkdownConverter.markdownToDelta(md));
      expect(md2.contains('A'), isTrue);
      expect(md2.contains('B'), isTrue);
      expect(md2.contains('1'), isTrue);
      expect(md2.contains('2'), isTrue);
      expect(md2.contains('---'), isTrue, reason: '往返后仍应保留表格分隔行');
    });

    test('单元格内的竖线被转义', () {
      final delta = jsonEncode([
        {
          'insert': {
            'table': {
              'rows': [
                [
                  {'text': 'a|b', 'style': ''}
                ]
              ]
            }
          }
        },
        {'insert': '\n'}
      ]);
      final md = MarkdownConverter.deltaToMarkdown(delta);
      expect(md.contains(r'a\|b'), isTrue, reason: '竖线应转义，否则列数错乱');
    });
  });

  group('MarkdownConverter 往返一致性', () {
    test('标题往返', () {
      const original = '# Title\n\n## Subtitle\n\n';
      final delta = MarkdownConverter.markdownToDelta(original);
      final md = MarkdownConverter.deltaToMarkdown(delta);
      expect(md.contains('# Title'), isTrue);
      expect(md.contains('## Subtitle'), isTrue);
    });

    test('加粗往返', () {
      final delta = MarkdownConverter.markdownToDelta('**bold** text');
      final md = MarkdownConverter.deltaToMarkdown(delta);
      expect(md.contains('**bold**'), isTrue);
    });

    test('列表往返', () {
      final delta = MarkdownConverter.markdownToDelta('- item1\n- item2\n');
      final md = MarkdownConverter.deltaToMarkdown(delta);
      expect(md.contains('- item1'), isTrue);
      expect(md.contains('- item2'), isTrue);
    });
  });
}
