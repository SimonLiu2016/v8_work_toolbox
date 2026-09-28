import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/agent_loop.dart';

void main() {
  group('AgentLoop.parseToolCall', () {
    test('解析标准 tool_call 代码块', () {
      const reply = '我先查一下。\n\n```tool_call\n'
          '{"name": "notebook_search", "arguments": {"query": "豆浆机"}}\n'
          '```\n';
      final call = AgentLoop.parseToolCall(reply);
      expect(call, isNotNull);
      expect(call!['name'], 'notebook_search');
      expect((call['arguments'] as Map)['query'], '豆浆机');
    });

    test('无工具调用返回 null', () {
      expect(AgentLoop.parseToolCall('直接回答，不调用工具。'), isNull);
    });

    test('JSON 非法返回 null 而非抛异常', () {
      const reply = '```tool_call\n{not valid json}\n```';
      expect(AgentLoop.parseToolCall(reply), isNull);
    });

    test('缺 name 字段返回 null', () {
      const reply = '```tool_call\n{"arguments": {}}\n```';
      expect(AgentLoop.parseToolCall(reply), isNull);
    });

    test('缺 arguments 时调用方按空 map 处理', () {
      const reply = '```tool_call\n{"name": "web_search"}\n```';
      final call = AgentLoop.parseToolCall(reply);
      expect(call, isNotNull);
      expect(call!['name'], 'web_search');
      expect(call['arguments'], isNull);
    });

    test('多行 arguments 可解析', () {
      const reply = '```tool_call\n{\n  "name": "scrape",\n'
          '  "arguments": {\n    "url": "https://example.com"\n  }\n}\n```';
      final call = AgentLoop.parseToolCall(reply);
      expect(call!['name'], 'scrape');
      expect((call['arguments'] as Map)['url'], 'https://example.com');
    });

    test('解析 XML <tool_call> 标签格式', () {
      const reply = '<tool_call>\n'
          '{"name": "web_search", "arguments": {"query": "Google"}}\n'
          '</tool_call>';
      final call = AgentLoop.parseToolCall(reply);
      expect(call, isNotNull);
      expect(call!['name'], 'web_search');
      expect((call['arguments'] as Map)['query'], 'Google');
    });

    test('解析省略闭合标签的 <tool_call> 格式 (实际线上模型输出)', () {
      const reply = '<tool_call> { "name": "web_search", "arguments": { "query": "Google latest news 2025 AI products", "limit": 10 } }';
      final call = AgentLoop.parseToolCall(reply);
      expect(call, isNotNull);
      expect(call!['name'], 'web_search');
      expect((call['arguments'] as Map)['query'], 'Google latest news 2025 AI products');
      expect((call['arguments'] as Map)['limit'], 10);
    });

    test('过滤 <think> 思考链内容并成功提取工具调用', () {
      const reply = '<think>用户想了解最新新闻，我需要先搜索一下。</think>\n'
          '<tool_call>{"name": "web_search", "arguments": {"query": "最新科技资讯"}}</tool_call>';
      final call = AgentLoop.parseToolCall(reply);
      expect(call, isNotNull);
      expect(call!['name'], 'web_search');
      expect((call['arguments'] as Map)['query'], '最新科技资讯');
    });

    test('归一化 parameters 与 args 别名为 arguments', () {
      const reply1 = '<tool_call>{"name": "web_search", "parameters": {"query": "AI"}}</tool_call>';
      final call1 = AgentLoop.parseToolCall(reply1);
      expect(call1!['arguments'], isNotNull);
      expect((call1['arguments'] as Map)['query'], 'AI');

      const reply2 = '```json\n{"name": "web_search", "args": {"query": "Rust"}}\n```';
      final call2 = AgentLoop.parseToolCall(reply2);
      expect(call2!['arguments'], isNotNull);
      expect((call2['arguments'] as Map)['query'], 'Rust');
    });

    test('解析裸 JSON 格式工具调用', () {
      const reply = '好的，我帮您搜索：\n{"name": "web_search", "arguments": {"query": "Flutter"}}';
      final call = AgentLoop.parseToolCall(reply);
      expect(call, isNotNull);
      expect(call!['name'], 'web_search');
      expect((call['arguments'] as Map)['query'], 'Flutter');
    });
  });

  group('AgentTool 与 prompt 渲染', () {
    test('toPromptLine 含名称、描述与参数模式', () {
      const tool = AgentTool(
        name: 'notebook_search',
        description: '在笔记本中检索',
        inputSchema: {'query': 'string'},
      );
      final line = tool.toPromptLine();
      expect(line, contains('notebook_search'));
      expect(line, contains('在笔记本中检索'));
      expect(line, contains('query'));
    });

    test('renderTools 拼接多个工具', () {
      final out = AgentLoop.renderTools(const [
        AgentTool(name: 'a', description: 'A'),
        AgentTool(name: 'b', description: 'B'),
      ]);
      expect(out, contains('- a:'));
      expect(out, contains('- b:'));
    });

    test('renderHistory 限制轮数并保留最近', () {
      final history = List.generate(
        10,
        (i) => (isUser: i.isEven, content: 'msg$i'),
      );
      final out = AgentLoop.renderHistory(history, maxTurns: 3);
      expect(out, contains('msg9'));
      expect(out, contains('msg7'));
      expect(out, isNot(contains('msg0')));
    });
  });

  group('AgentToolOutcome', () {
    test('成功时 feedText 为文本本身', () {
      const o = AgentToolOutcome.success('结果内容');
      expect(o.isError, isFalse);
      expect(o.feedText, '结果内容');
    });

    test('失败时 feedText 含错误说明', () {
      const o = AgentToolOutcome.failure('连接超时');
      expect(o.isError, isTrue);
      expect(o.feedText, contains('工具执行失败'));
      expect(o.feedText, contains('连接超时'));
    });

    test('失败时 error 为空则给出兜底文案', () {
      const o = AgentToolOutcome.failure(null);
      expect(o.feedText, contains('未知错误'));
    });
  });
}
