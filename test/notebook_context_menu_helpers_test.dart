import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/note_store.dart';
import 'package:V8WorkToolbox/tools/notebook/ui/notebook_page.dart';

void main() {
  group('NoteStore.appendTodoTask', () {
    test('在已有内容末尾追加未勾选待办', () {
      const delta = '[{"insert":"正文内容"},{"insert":"\\n"}]';
      final result = NoteStore.appendTodoTask(delta);

      final ops = (jsonDecode(result) as List).cast<Map>();
      expect(ops.length, greaterThan(2));
      final taskInsert = ops[ops.length - 2];
      final taskBreak = ops.last;
      expect(taskInsert['insert'], equals('任务：'));
      expect(taskBreak['insert'], equals('\n'));
      expect(taskBreak['attributes'], equals({'list': 'unchecked'}));
    });

    test('原文末尾无换行时先补换行', () {
      const delta = '[{"insert":"末尾无换行的正文"}]';
      final result = NoteStore.appendTodoTask(delta);

      final ops = (jsonDecode(result) as List).cast<Map>();
      // 原文 + 补换行 + 任务文本 + 任务换行
      expect(ops.length, equals(4));
      expect(ops[1]['insert'], equals('\n'), reason: '应补一个换行使任务独立成行');
    });

    test('空文档也能追加任务', () {
      final result = NoteStore.appendTodoTask('[]');
      final ops = (jsonDecode(result) as List).cast<Map>();
      expect(ops.length, equals(2));
    });

    test('无法解析的 Delta 退化为空文档追加', () {
      final result = NoteStore.appendTodoTask('not-json');
      final ops = (jsonDecode(result) as List).cast<Map>();
      expect(ops.length, equals(2));
      expect(ops.last['attributes'], equals({'list': 'unchecked'}));
    });
  });

  group('NoteStore.uniqueExportPath', () {
    late Directory dir;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('unique_path_test_');
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('目标不存在时原样返回', () {
      final path = NoteStore.uniqueExportPath(dir.path, '报告.pdf');
      expect(path.endsWith('/报告.pdf'), isTrue);
    });

    test('重名时追加序号', () {
      File('${dir.path}/报告.pdf').createSync();
      File('${dir.path}/报告_1.pdf').createSync();

      final path = NoteStore.uniqueExportPath(dir.path, '报告.pdf');
      expect(path.endsWith('/报告_2.pdf'), isTrue);
    });

    test('无扩展名也能追加序号', () {
      File('${dir.path}/README').createSync();
      final path = NoteStore.uniqueExportPath(dir.path, 'README');
      expect(path.endsWith('/README_1'), isTrue);
    });
  });

  group('NotebookFocusBridge', () {
    test('注册与通知：焦点回调会被触发', () {
      var calls = 0;
      final cb = () => calls++;
      NotebookFocusBridge.instance.register(cb);
      NotebookFocusBridge.instance.notifyWindowFocused();
      NotebookFocusBridge.instance.notifyWindowFocused();
      expect(calls, equals(2));
      NotebookFocusBridge.instance.unregister(cb);
    });

    test('注销后不再被调用', () {
      var calls = 0;
      final cb = () => calls++;
      NotebookFocusBridge.instance.register(cb);
      NotebookFocusBridge.instance.unregister(cb);
      NotebookFocusBridge.instance.notifyWindowFocused();
      expect(calls, equals(0));
    });

    test('多个监听器都被通知', () {
      var a = 0;
      var b = 0;
      final cbA = () => a++;
      final cbB = () => b++;
      NotebookFocusBridge.instance.register(cbA);
      NotebookFocusBridge.instance.register(cbB);
      NotebookFocusBridge.instance.notifyWindowFocused();
      expect(a, equals(1));
      expect(b, equals(1));
      NotebookFocusBridge.instance.unregister(cbA);
      NotebookFocusBridge.instance.unregister(cbB);
    });
  });
}
