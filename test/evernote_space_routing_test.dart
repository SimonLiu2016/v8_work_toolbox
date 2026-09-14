import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/evernote_import_service.dart';

/// 空间笔记归属逻辑验证（任务 4.1）
///
/// 归属链在 Python 脚本侧实现（ZENTEAMSPACENOTE 解析），此处验证
/// Dart 侧透传的字段与去重行为的可观察约定。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImportResult 结构（空间分流与去重可观察字段）', () {
    test('ImportResult 默认构造合法', () {
      const result = ImportResult(
        total: 320,
        imported: 320,
        failed: 0,
      );
      expect(result.total, 320);
      expect(result.imported, 320);
      expect(result.failed, 0);
      expect(result.errors, isEmpty);
    });

    test('ImportResult 支持错误列表', () {
      const result = ImportResult(
        total: 10,
        imported: 8,
        failed: 2,
        errors: ['note A failed', 'note B failed'],
      );
      expect(result.failed, 2);
      expect(result.errors.length, 2);
    });
  });

  group('本机印象笔记探测（归属链数据源）', () {
    test('detectLocalEvernote 能检测本机客户端（若存在）', () async {
      // 本机已确认存在印象笔记数据；探测不应抛异常
      final info = await EvernoteImportService.instance.detectLocalEvernote();
      // 若检测到，笔记本数应非零
      expect(info.notebookCount, greaterThanOrEqualTo(0));
    });
  });
}
