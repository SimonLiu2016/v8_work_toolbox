import 'package:flutter_test/flutter_test.dart';
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
  _stageTargetPrompt();

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

void _stageTargetPrompt() {
  group('目标笔记提问 prompt 构建 (buildTargetPrompt)', () {
    test('构建包含选定笔记全文和凭证附件的 prompt', () {
      final now = DateTime.now();
      final targetNote = Note(
        id: 'note-target-1',
        title: '新用户入职业务流程',
        deltaJson: '# 新员工入职指南\n\n1. 领取办公电脑\n2. 配置 VPN 与账号\n3. 提交行政审批',
        isPinned: false,
        isDeleted: false,
        createdAt: now,
        updatedAt: now,
        assetCategory: '行政指引',
        assetExpiryDate: DateTime(2027, 1, 1),
      );

      final prompt = NotebookKbService.buildTargetPrompt(
        targetNotes: [targetNote],
        question: '总结入职业务流程并指出需要完善的步骤',
        credentialMap: {
          'note-target-1': ['入职审批表.pdf', '网络配置单.png'],
        },
      );

      expect(prompt, contains('新用户入职业务流程'));
      expect(prompt, contains('【选定目标笔记 1】'));
      expect(prompt, contains('行政指引'));
      expect(prompt, contains('2027-01-01'));
      expect(prompt, contains('入职审批表.pdf、网络配置单.png'));
      expect(prompt, contains('领取办公电脑'));
      expect(prompt, contains('总结入职业务流程并指出需要完善的步骤'));
      expect(prompt, contains('可使用提供的工具'));
    });

    test('长笔记超过 30,000 字符时被安全截断', () {
      final now = DateTime.now();
      final hugeContent = '很长的段落内容' * 6000; // > 36000 chars
      final targetNote = Note(
        id: 'note-huge-1',
        title: '长篇日志',
        deltaJson: hugeContent,
        isPinned: false,
        isDeleted: false,
        createdAt: now,
        updatedAt: now,
      );

      final prompt = NotebookKbService.buildTargetPrompt(
        targetNotes: [targetNote],
        question: '分析全文',
      );

      expect(prompt, contains('注意：该笔记内容过长，已截取前 30000 字符'));
      expect(prompt.length, lessThan(35000));
    });

    test('保留 kbTools 包含 notebook_search, web_search, scrape', () {
      final toolNames = NotebookKbService.kbTools.map((t) => t.name).toList();
      expect(toolNames, containsAll(['notebook_search', 'web_search', 'scrape']));
    });
  });
}

