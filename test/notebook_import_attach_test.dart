import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/appflowy_codec.dart';
import 'package:V8WorkToolbox/tools/notebook/markdown_converter.dart';

/// 回归：文档导入"保留源文件为附件"的三个缺陷。
///
/// 1. `markdownToDelta` 每行正文被完整追加两遍
/// 2. 向文档末尾追加附件节点时抛 `UnsupportedError: Cannot add to a
///    fixed-length list`（`parseToDocument` 返回的 root.children 是
///    `growable: false` 的缓存快照，`.add()` 直接失败）
/// 3. 缺陷 2 使附件节点从未写入正文，导入提示"已导入 0 篇，失败 1 篇"
///    而笔记与附件记录都已落库（孤儿笔记）
void main() {
  group('markdownToDelta 不重复追加正文', () {
    test('无格式单行只产生一个 text op', () {
      final ops = jsonDecode(MarkdownConverter.markdownToDelta('普通段落行\n')) as List;
      final texts = ops.whereType<Map>().where((o) => o['insert'] is String && o['insert'] != '\n').toList();
      expect(texts.length, 1, reason: '无格式行不应被追加两遍');
      expect(texts.first['insert'], '普通段落行');
    });

    test('多行文档每行只出现一次', () {
      const md = '## 标题\n\n第一段内容\n\n第二段内容\n';
      final ops = jsonDecode(MarkdownConverter.markdownToDelta(md)) as List;
      final texts = ops
          .whereType<Map>()
          .where((o) => o['insert'] is String && o['insert'] != '\n')
          .map((o) => o['insert'] as String)
          .toList();
      // 标题 + 两个段落 = 3 个 text op，而非 3 + 2 个重复
      expect(texts, ['标题', '第一段内容', '第二段内容']);
    });

    test('短行（如表单标签）同样不重复', () {
      final ops = jsonDecode(MarkdownConverter.markdownToDelta('Password :\n')) as List;
      final texts = ops.whereType<Map>().where((o) => o['insert'] == 'Password :').toList();
      expect(texts.length, 1);
    });

    test('含内联格式的行仍正确拆分且不重复', () {
      final ops = jsonDecode(MarkdownConverter.markdownToDelta('这是 **加粗** 的行\n')) as List;
      final texts = ops
          .whereType<Map>()
          .where((o) => o['insert'] is String && o['insert'] != '\n')
          .map((o) => o['insert'] as String)
          .toList();
      expect(texts, ['这是 ', '加粗', ' 的行']);
    });
  });

  group('AppFlowyCodec.appendAttachmentNode', () {
    test('追加附件节点不抛异常且节点数 +1', () {
      final json = MarkdownConverter.markdownToDelta('正文段落\n');
      expect(
        () => AppFlowyCodec.appendAttachmentNode(
          json,
          attachmentId: 'att-1',
          filename: 'a.pdf',
          sizeBytes: 368682,
        ),
        returnsNormally,
        reason: 'root.children 为固定长度列表，.add() 会抛 UnsupportedError',
      );

      final out = AppFlowyCodec.appendAttachmentNode(
        json,
        attachmentId: 'att-1',
        filename: 'a.pdf',
        sizeBytes: 368682,
      );
      final before = AppFlowyCodec.parseToDocument(json).root.children.length;
      final after = AppFlowyCodec.parseToDocument(out).root.children.length;
      expect(after, before + 1);
    });

    test('附件节点位于末尾且元数据完整', () {
      final json = MarkdownConverter.markdownToDelta('# 标题\n\n正文\n');
      final out = AppFlowyCodec.appendAttachmentNode(
        json,
        attachmentId: 'att-42',
        filename: 'User ID Acknowledgement Form.pdf',
        sizeBytes: 1234,
      );
      final children = AppFlowyCodec.parseToDocument(out).root.children;
      final last = children.last;
      expect(last.type, 'attachment');
      final data = last.attributes;
      expect(data['attachmentId'], 'att-42');
      expect(data['filename'], 'User ID Acknowledgement Form.pdf');
      expect(data['sizeBytes'], 1234);
      expect(data['localPath'], isNull, reason: '节点不应缓存路径，路径由 attachments 表解析');
    });

    test('原有正文在追加附件后完整保留', () {
      final json = MarkdownConverter.markdownToDelta('# 标题\n\n正文内容\n');
      final out = AppFlowyCodec.appendAttachmentNode(
        json,
        attachmentId: 'att-1',
        filename: 'a.pdf',
        sizeBytes: 1,
      );
      final text = AppFlowyCodec.documentToPlainText(AppFlowyCodec.parseToDocument(out));
      expect(text, contains('标题'));
      expect(text, contains('正文内容'));
    });
  });
}
