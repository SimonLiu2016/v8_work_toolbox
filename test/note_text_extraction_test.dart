import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/appflowy_codec.dart';

/// 回归守卫：笔记存储格式在 AppFlowy 迁移后是 `{"document":{...}}` 对象，
/// 而**不是** Quill Delta 数组（字段名 deltaJson 是历史遗留）。
///
/// 曾因用 `jsonDecode(...) as List` 解析该格式，异常被静默吞掉返回空串，
/// 导致 FTS 正文全空（307 条笔记只有标题可搜）、RAG 片段全空。
/// 本测试锁定：AppFlowy 格式必须能提取出正文。
void main() {
  group('AppFlowyCodec.jsonToPlainText（正文提取唯一入口）', () {
    test('AppFlowy document 格式能提取正文', () {
      const appflowyJson = '{"document":{"type":"page","children":['
          '{"type":"paragraph","data":{"delta":[{"insert":"我在京东买了豆浆机，'
          '同时买了5年换新服务。"}]}},'
          '{"type":"paragraph","data":{"delta":[{"insert":"订单号 JD123456"}]}}'
          ']}}';
      final text = AppFlowyCodec.jsonToPlainText(appflowyJson);
      expect(text, contains('豆浆机'), reason: 'AppFlowy 格式必须能提取正文');
      expect(text, contains('5年换新'));
      expect(text, contains('JD123456'));
      expect(text, isNotEmpty, reason: '绝不能再静默返回空串');
    });

    test('Quill Delta 数组格式仍兼容', () {
      const quillJson = '[{"insert":"旧格式正文\\n"}]';
      final text = AppFlowyCodec.jsonToPlainText(quillJson);
      expect(text, contains('旧格式正文'));
    });

    test('空输入返回空串而非抛异常', () {
      expect(AppFlowyCodec.jsonToPlainText(''), '');
      expect(AppFlowyCodec.jsonToPlainText(null), '');
      expect(AppFlowyCodec.jsonToPlainText('   '), '');
    });

    test('损坏 JSON 不抛异常（parseToDocument 会回退为 markdown 解析）', () {
      // parseToDocument 对非 JSON 输入有 markdown 回退（导入场景需要），
      // 故损坏内容会被当作纯文本读出而非报错。对索引而言这是可接受的降级
      // ——总比静默返回空串好。关键是**不抛异常**。
      expect(() => AppFlowyCodec.jsonToPlainText('{不是合法 json'), returnsNormally);
      expect(() => AppFlowyCodec.jsonToPlainText('[[['), returnsNormally);
    });

    test('提取结果可用于 CJK bigram 索引（端到端衔接）', () {
      const appflowyJson = '{"document":{"type":"page","children":['
          '{"type":"paragraph","data":{"delta":[{"insert":"延保服务"}]}}'
          ']}}';
      final text = AppFlowyCodec.jsonToPlainText(appflowyJson);
      expect(text, isNotEmpty);
      // 若这里为空，下游 FTS 的 content 列就会是空的
      expect(text.trim().length, greaterThan(0));
    });
  });
}
