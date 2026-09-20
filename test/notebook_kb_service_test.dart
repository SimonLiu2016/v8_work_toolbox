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

  _stage3();

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

/// 阶段三：AI 整理建议的解析层测试。
///
/// suggestTags/suggestLinks 依赖真实 LLM，此处只测**确定性解析**——
/// 模型输出如何被解析成建议、以及"AI 不写库"这一契约的执行边界。
void _stage3() {
  group('parseTagSuggestions', () {
    test('解析 JSON 数组', () {
      final out = NotebookKbService.parseTagSuggestions('["延保","家电","凭证"]');
      expect(out, ['延保', '家电', '凭证']);
    });

    test('剔除已有标签（不重复）', () {
      final out = NotebookKbService.parseTagSuggestions(
        '["延保","家电"]',
        excluded: {'延保'},
      );
      expect(out, ['家电']);
    });

    test('结果内去重', () {
      final out = NotebookKbService.parseTagSuggestions('["延保","延保","家电"]');
      expect(out, ['延保', '家电']);
    });

    test('模型附带解释文字时仍能提取数组', () {
      final out = NotebookKbService.parseTagSuggestions(
        '我建议这些标签：\n["延保","家电"]\n希望有帮助。',
      );
      expect(out, ['延保', '家电']);
    });

    test('无数组返回空', () {
      expect(NotebookKbService.parseTagSuggestions('不方便建议'), isEmpty);
    });

    test('非法 JSON 返回空而非抛异常', () {
      expect(NotebookKbService.parseTagSuggestions('["未闭合'), isEmpty);
    });
  });

  group('parseLinkSuggestions', () {
    test('解析合法关联建议', () {
      final out = NotebookKbService.parseLinkSuggestions(
        '[{"noteId":"n2","reason":"同一订单"}]',
        validIds: {'n2', 'n3'},
        titleOf: {'n2': '豆浆机订单'},
      );
      expect(out.length, 1);
      expect(out.first.noteId, 'n2');
      expect(out.first.title, '豆浆机订单');
      expect(out.first.reason, '同一订单');
    });

    test('剔除不在候选池中的 id（防模型臆造）', () {
      final out = NotebookKbService.parseLinkSuggestions(
        '[{"noteId":"不存在","reason":"x"}]',
        validIds: {'n2'},
      );
      expect(out, isEmpty, reason: '模型可能臆造 id，必须按候选池白名单过滤');
    });

    test('剔除已有连接（不重复建边）', () {
      final out = NotebookKbService.parseLinkSuggestions(
        '[{"noteId":"n2","reason":"x"}]',
        validIds: {'n2'},
        excludedIds: {'n2'},
      );
      expect(out, isEmpty);
    });

    test('结果内去重', () {
      final out = NotebookKbService.parseLinkSuggestions(
        '[{"noteId":"n2","reason":"a"},{"noteId":"n2","reason":"b"}]',
        validIds: {'n2'},
      );
      expect(out.length, 1);
    });

    test('模型返回空数组表示无相关', () {
      final out = NotebookKbService.parseLinkSuggestions('[]', validIds: {'n2'});
      expect(out, isEmpty);
    });

    test('非法 JSON 返回空而非抛异常', () {
      expect(
        NotebookKbService.parseLinkSuggestions('[{未闭合', validIds: {'n2'}),
        isEmpty,
      );
    });
  });
}
