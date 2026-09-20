import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:V8WorkToolbox/tools/notebook/note_database.dart';
import 'package:V8WorkToolbox/tools/notebook/notebook_kb_service.dart';

/// NotebookKbService 的检索与上下文构建测试。
///
/// 不触网、不调 LLM：只验证 retrieve 的命中与片段构建、ask 的无匹配分支、
/// 以及喂给模型的上下文是否含资产/凭证信息（这是豆浆机场景的关键）。
///
/// ask 的成功分支依赖 AiService，由集成手工验证覆盖（任务 2.3.2）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KbFragment 模型', () {
    test('isAsset 判定', () {
      const plain = KbFragment(noteId: 'n', title: 't', snippet: 's');
      expect(plain.isAsset, isFalse);

      final asset = KbFragment(
        noteId: 'n',
        title: 't',
        snippet: 's',
        assetCategory: '延保服务',
      );
      expect(asset.isAsset, isTrue);
    });
  });

  group('上下文构建（喂给 LLM 的内容）', () {
    test('含资产类别、到期日与凭证附件', () {
      final ctx = NotebookKbService.instance.debugBuildContext([
        KbFragment(
          noteId: 'n1',
          title: '豆浆机延保',
          snippet: '我在京东买了豆浆机，买了5年换新服务',
          assetCategory: '延保服务',
          assetExpiryDate: DateTime(2029, 9, 20),
          credentialFiles: ['订单截图.png'],
        ),
      ]);
      expect(ctx, contains('豆浆机延保'));
      expect(ctx, contains('延保服务'));
      expect(ctx, contains('2029-09-20'));
      expect(ctx, contains('订单截图.png'),
          reason: '凭证文件名必须进上下文，否则模型无法指引用户定位凭证');
    });

    test('普通笔记不含资产字段行', () {
      final ctx = NotebookKbService.instance.debugBuildContext([
        const KbFragment(noteId: 'n2', title: '随手记', snippet: '今天天气不错'),
      ]);
      expect(ctx, contains('随手记'));
      expect(ctx, isNot(contains('资产类别')));
      expect(ctx, isNot(contains('凭证附件')));
    });
  });

  group('检索边界', () {
    test('空查询返回空列表', () async {
      expect(await NotebookKbService.instance.retrieve(''), isEmpty);
      expect(await NotebookKbService.instance.retrieve('   '), isEmpty);
    });

    test('纯标点查询返回空而非抛异常', () async {
      expect(await NotebookKbService.instance.retrieve('，。！'), isEmpty);
    });

    test('ask 空问题返回 noMatch 而非抛异常', () async {
      final a = await NotebookKbService.instance.ask('');
      expect(a.noMatch, isTrue);
      expect(a.text, isNotEmpty);
    });
  });
}
