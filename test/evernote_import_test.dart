import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/evernote_import_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('EvernoteImportService can detect local Evernote installation', () async {
    final info = await EvernoteImportService.instance.detectLocalEvernote();
    expect(info.detected, isTrue);
    expect(info.notebookCount, greaterThan(0));
    expect(info.noteCount, greaterThan(0));
  });

  test('EvernoteImportService resolves notes file with default notebook name and unencrypted content', () async {
    const notesPath = '/Users/simon/Desktop/我的笔记.notes';
    if (!File(notesPath).existsSync()) {
      markTestSkipped('测试文件 $notesPath 不存在');
      return;
    }

    final result = await Process.run('python3', [
      'scripts/evernote_import.py',
      'parse_notes',
      '--file',
      notesPath,
    ]);

    expect(result.exitCode, equals(0));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('markdownToDelta preserves code blocks, todos, headings, and image embeds', () {
    const md = '''
# 架构总览

这是一段带有 **加粗** 和 `代码` 的正文。

```
def hello_world():
    print("hello")
```

- [ ] 待完成事项
- [x] 已完成事项
- 常规列表项

![示意图](en-media://a1b2c3d4e5f6)
''';

    final attachmentMap = {
      'a1b2c3d4e5f6': '/local/path/to/diagram.png',
    };

    final deltaStr = EvernoteImportService.instance.markdownToDelta(md, attachmentMap);
    expect(deltaStr, contains('"code-block":true'));
    expect(deltaStr, contains('def hello_world():'));
    expect(deltaStr, contains('"list":"unchecked"'));
    expect(deltaStr, contains('"list":"checked"'));
    expect(deltaStr, contains('"header":1'));
    expect(deltaStr, contains('"image":"/local/path/to/diagram.png"'));
    expect(deltaStr, contains('"bold":true'));
    expect(deltaStr, contains('"code":true'));
  });
}
