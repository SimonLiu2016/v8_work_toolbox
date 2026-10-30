import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:V8WorkToolbox/tools/it_meeting_listening/models/rehearsal_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/material_importer.dart';

/// 材料导入的四个 spec 场景：MD 导入、HTML 导入、格式被拒、空内容被拒。
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('material_import_test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<File> write(String name, String content) async {
    final f = File('${tmp.path}/$name');
    await f.writeAsString(content);
    return f;
  }

  group('MD 导入', () {
    test('解析为结构化文本并记录出处', () async {
      final file = await write('weekly-sync.md', '''
# 本周进展

订单服务迁移到 **gRPC**，延迟从 [120ms](http://x) 降到 80ms。
![架构图](arch.png)

## 风险

支付网关的 503 错误率上升。
''');
      final material = await MaterialImporter.importFile(file.path);

      expect(material.title, 'weekly-sync');
      expect(material.fileName, 'weekly-sync.md');
      expect(material.sourcePath, file.path);
      expect(material.charCount, greaterThan(0));
      // 清洗后保留术语与数字，剥掉图片与链接语法
      expect(material.text, contains('gRPC'));
      expect(material.text, contains('120ms'));
      expect(material.text.contains('架构图'), isFalse);
      expect(material.text.contains('http://x'), isFalse);
    });

    test('同一份文件重复导入得到同一 id，改内容得到新 id', () async {
      final file = await write('a.md', 'first');
      final m1 = await MaterialImporter.importFile(file.path);
      final m2 = await MaterialImporter.importFile(file.path);
      expect(m1.id, m2.id);

      await file.writeAsString('second');
      final m3 = await MaterialImporter.importFile(file.path);
      expect(m3.id, isNot(m1.id));
    });
  });

  group('HTML 导入', () {
    test('转 Markdown 后解析为结构化文本', () async {
      final file = await write('agenda.html', '''
<html><body>
<h1>Q4 容量评审</h1>
<p>当前集群 <strong>72</strong> 节点，需要扩容到 96。</p>
<script>alert(1)</script>
</body></html>
''');
      final material = await MaterialImporter.importFile(file.path);

      expect(material.fileName, 'agenda.html');
      expect(material.text, contains('Q4 容量评审'));
      expect(material.text, contains('72'));
      expect(material.text, contains('96'));
      expect(material.text.contains('alert'), isFalse);
    });

    test('非 UTF-8 字节不炸出乱码异常', () async {
      final file = File('${tmp.path}/latin1.html');
      await file.writeAsBytes(latin1.encode('<p>café</p>'));
      final material = await MaterialImporter.importFile(file.path);
      expect(material.text, contains('caf'));
    });
  });

  group('失败原因具体', () {
    test('不支持的格式被拒绝', () async {
      final file = await write('deck.pdf', '%PDF-1.4');
      expect(
        () => MaterialImporter.importFile(file.path),
        throwsA(isA<MaterialImportException>()
            .having((e) => e.message, 'message', contains('仅支持 MD 与 HTML'))),
      );
    });

    test('解析结果为空时明确报错', () async {
      final file = await write('blank.md', '   \n\n  \n');
      expect(
        () => MaterialImporter.importFile(file.path),
        throwsA(isA<MaterialImportException>()
            .having((e) => e.message, 'message', contains('内容为空'))),
      );
    });

    test('文件不存在时明确报错', () async {
      expect(
        () => MaterialImporter.importFile('${tmp.path}/nope.md'),
        throwsA(isA<MaterialImportException>()
            .having((e) => e.message, 'message', contains('不存在'))),
      );
    });
  });

  group('截断', () {
    test('超长材料截断并明确标注', () async {
      final long = 'x' * 30000;
      final out = MaterialImporter.truncateForPrompt(long, maxChars: 1000);
      expect(out.length, lessThan(1100));
      expect(out, contains('仅分析前 1000 字符'));
    });

    test('短材料原样返回', () async {
      expect(MaterialImporter.truncateForPrompt('short'), 'short');
    });
  });

  group('模型序列化', () {
    test('RehearsalMaterial 往返一致', () {
      final m = RehearsalMaterial(
        id: 'mat_1',
        title: 't',
        sourcePath: '/x/y.md',
        fileName: 'y.md',
        text: 'hello',
        importedAt: DateTime(2026),
      );
      final restored = RehearsalMaterial.fromJson(m.toJson());
      expect(restored.id, m.id);
      expect(restored.text, m.text);
    });

    test('RehearsalRole 按说话人反查', () {
      expect(RehearsalRole.fromSpeaker('Simon'), RehearsalRole.simon);
      expect(RehearsalRole.fromSpeaker('josh'), RehearsalRole.josh);
      expect(RehearsalRole.fromSpeaker('moderator'), isNull);
      expect(RehearsalRole.xiaofeng.isClientSide, isTrue);
      expect(RehearsalRole.songyang.isClientSide, isFalse);
    });
  });
}
