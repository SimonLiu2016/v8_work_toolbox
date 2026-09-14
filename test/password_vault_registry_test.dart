import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/registry.dart';
import 'package:V8WorkToolbox/tools/tool_definition.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('密码工具注册', () {
    test('注册为 password-vault 且分类为 system（普通小工具，不在隐私空间）', () {
      final tool = ToolRegistry.findById('password-vault');
      expect(tool, isNotNull);
      expect(tool!.title, '密码工具');
      expect(tool.category, ToolCategory.system);
      expect(tool.openInNewWindow, isTrue);
    });

    test('出现在公开工具列表（全部工具视图可见）', () {
      final public = ToolRegistry.publicTools;
      expect(public.any((t) => t.id == 'password-vault'), isTrue);
    });

    test('全局搜索默认可搜到', () {
      final results = ToolRegistry.search('密码');
      expect(results.any((t) => t.id == 'password-vault'), isTrue);
    });

    test('全局搜索按标题匹配', () {
      final results = ToolRegistry.search('密码工具');
      expect(results.any((t) => t.id == 'password-vault'), isTrue);
    });

    test('隐私分类下没有密码工具', () {
      final privacy = ToolRegistry.getByCategory(ToolCategory.privacy);
      expect(privacy.any((t) => t.id == 'password-vault'), isFalse);
    });

    test('system 分类下包含密码工具', () {
      final system = ToolRegistry.getByCategory(ToolCategory.system);
      expect(system.any((t) => t.id == 'password-vault'), isTrue);
    });

    test('buildPage 返回非空 Widget', () {
      final tool = ToolRegistry.findById('password-vault')!;
      final widget = tool.buildPage(
        _FakeBuildContext(),
      );
      expect(widget, isA<Widget>());
    });
  });
}

class _FakeBuildContext extends BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
