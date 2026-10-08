/// 安全工具箱工具链检测与注册的回归测试。
///
/// 覆盖三处容易静默失配的地方：
/// 1. 工具清单的完整性（14 个工具、brew 名与可执行名分开的那些）
/// 2. 版本三态判定的边界（字典序 vs 数值序）
/// 3. 工具注册的分类与可见性
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/registry.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/models/security_enums.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/services/security_process_runner.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/services/security_tool_registry.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/services/tool_status_checker.dart';

void main() {
  group('受管工具清单', () {
    test('包含 spec 要求的 15 个工具', () {
      expect(SecurityToolRegistry.tools.length, 15);
      final ids = SecurityToolRegistry.tools.map((t) => t.id).toSet();
      expect(
        ids,
        containsAll([
          'nmap',
          'arp-scan',
          'masscan',
          'nuclei',
          'subfinder',
          'httpx',
          'katana',
          'ffuf',
          'sqlmap',
          'gau',
          'metasploit',
          'bettercap',
          'netexec',
          'searchsploit',
          'hydra',
        ]),
      );
    });

    test('searchsploit 的 brew 包名是 exploitdb（可执行名与包名不同的唯一一个）', () {
      final tool = SecurityToolRegistry.byId('searchsploit');
      expect(tool, isNotNull);
      expect(tool!.brewName, 'exploitdb');
      expect(tool.executable, 'searchsploit');
    });

    test('每个工具都有 brew 名、可执行名与用途分类', () {
      for (final tool in SecurityToolRegistry.tools) {
        expect(tool.brewName.isNotEmpty, isTrue, reason: tool.id);
        expect(tool.executable.isNotEmpty, isTrue, reason: tool.id);
        expect(ToolPurpose.values, contains(tool.purpose), reason: tool.id);
      }
    });

    test('工具 id 唯一', () {
      final ids = SecurityToolRegistry.tools.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('按用途筛选', () {
      expect(
        toolsForPurpose(ToolPurpose.lanRecon).map((t) => t.id),
        containsAll(['nmap', 'arp-scan', 'masscan', 'bettercap']),
      );
    });

    test('包含 /opt/metasploit-framework/bin 目录解析支持', () {
      expect(kSecurityAppBinDirs, contains('/opt/metasploit-framework/bin'));
      expect(kSecurityAppBinDirs, contains('/opt/metasploit-framework/embedded/bin'));
      expect(augmentedPath, contains('/opt/metasploit-framework/bin'));

      final msfPath = resolveExecutable('msfconsole');
      // 如果机器上安装了 Rapid7 Metasploit，应能成功解析出绝对路径
      if (msfPath != null) {
        expect(msfPath, contains('msfconsole'));
      }
    });
  });

  group('版本三态判定', () {
    const tool = SecurityTool(
      id: 'nmap',
      displayName: 'Nmap',
      brewName: 'nmap',
      executable: 'nmap',
      purpose: ToolPurpose.lanRecon,
      minVersion: '7.0',
    );

    test('版本号按数值比较，不是字符串比较', () {
      // "1.10" 在字典序里小于 "1.9"，数值序相反。
      expect(ToolStatusChecker.compareVersions('1.10', '1.9'), greaterThan(0));
      expect(ToolStatusChecker.compareVersions('7.94', '7.0'), greaterThan(0));
      expect(ToolStatusChecker.compareVersions('6.0', '7.0'), lessThan(0));
      expect(ToolStatusChecker.compareVersions('7.0', '7.0'), 0);
    });

    test('满足最低版本 → ready', () {
      expect(
        ToolStatusChecker.classify(tool, '7.94'),
        ToolStatus.ready,
      );
    });

    test('低于最低版本 → outdated', () {
      expect(ToolStatusChecker.classify(tool, '6.5'), ToolStatus.outdated);
    });

    test('没有 minVersion 的工具永不过期', () {
      const noMin = SecurityTool(
        id: 'arp-scan',
        displayName: 'arp-scan',
        brewName: 'arp-scan',
        executable: 'arp-scan',
        purpose: ToolPurpose.lanRecon,
      );
      expect(ToolStatusChecker.classify(noMin, '0.1'), ToolStatus.ready);
      expect(ToolStatusChecker.classify(noMin, null), ToolStatus.ready);
    });

    test('版本号解析失败时不升级为 outdated', () {
      // 工具输出 help 文本时 extractVersion 可能抠出无关数字或 null。
      expect(ToolStatusChecker.classify(tool, null), ToolStatus.ready);
    });

    test('从任意输出里抠版本号', () {
      expect(
        ToolStatusChecker.extractVersion('Nmap version 7.94 ( https://nmap.org )'),
        '7.94',
      );
      expect(
        ToolStatusChecker.extractVersion('nuclei version 3.2.9'),
        '3.2.9',
      );
    });

    test('缺省段补 0（7.0 等价 7.0.0）', () {
      expect(
        ToolStatusChecker.compareVersions('7.0', '7.0.0'),
        0,
      );
    });
  });

  group('状态板', () {
    test('按状态计数', () {
      final board = ToolStatusBoard(
        probes: const {
          'a': ToolProbe(toolId: 'a', status: ToolStatus.ready),
          'b': ToolProbe(toolId: 'b', status: ToolStatus.missing),
          'c': ToolProbe(toolId: 'c', status: ToolStatus.outdated),
        },
        brewAvailable: true,
        checkedAt: DateTime(2026, 1, 1),
      );
      expect(board.readyCount, 1);
      expect(board.missingCount, 1);
      expect(board.outdatedCount, 1);
      expect(board.allReady, isFalse);
    });

    test('空板不算 allReady', () {
      expect(ToolStatusBoard.empty.allReady, isFalse);
    });
  });

  group('严重等级', () {
    test('CVSS 分档（9 / 7 / 4 三档）', () {
      expect(Severity.fromCvss(9.5), Severity.critical);
      expect(Severity.fromCvss(8.1), Severity.high);
      expect(Severity.fromCvss(5.5), Severity.medium);
      expect(Severity.fromCvss(2.0), Severity.low);
      expect(Severity.fromCvss(null), Severity.info);
    });

    test('未知 key 回落 info 而不是抛异常', () {
      expect(Severity.fromKey('does-not-exist'), Severity.info);
      expect(Severity.fromKey(null), Severity.info);
    });

    test('sortIndex 越小越严重', () {
      expect(
        Severity.critical.sortIndex < Severity.high.sortIndex,
        isTrue,
      );
    });
  });

  group('安全工具注册', () {
    test('注册为 security-toolbox 且分类为 security', () {
      final tool = ToolRegistry.findById('security-toolbox');
      expect(tool, isNotNull);
      expect(tool!.category, ToolCategory.security);
      expect(tool.title, '安全工具箱');
    });

    test('不属于隐私空间（公开可见）', () {
      final tool = ToolRegistry.findById('security-toolbox')!;
      expect(ToolRegistry.publicTools, contains(tool));
      expect(ToolRegistry.getByCategory(ToolCategory.security), contains(tool));
    });

    test('buildPage 返回非空 Widget', () {
      final tool = ToolRegistry.findById('security-toolbox')!;
      expect(tool.buildPage(_FakeContext()), isA<Widget>());
    });

    test('新增 security 分类未破坏既有分类数量', () {
      expect(ToolCategory.values.length, 7);
      expect(ToolCategory.security.label, '安全工具');
    });

    test('工具渠道与安装策略配置准确', () {
      final netexec = SecurityToolRegistry.byId('netexec')!;
      expect(netexec.installMethod, InstallMethod.pipx);
      expect(netexec.installNote, contains('pipx'));

      final metasploit = SecurityToolRegistry.byId('metasploit')!;
      expect(metasploit.installMethod, InstallMethod.manual);
      expect(metasploit.manualInstallUrl, isNotNull);

      final httpx = SecurityToolRegistry.byId('httpx')!;
      expect(httpx.installMethod, InstallMethod.brew);
      expect(httpx.installNote, contains('Go'));

      final nmap = SecurityToolRegistry.byId('nmap')!;
      expect(nmap.installMethod, InstallMethod.brew);
    });
  });
}

/// buildPage 只需要一个 BuildContext 用来定位 InheritedWidget；这里用真实
/// 的 widget 树上下文太重，所以走测试框架的空壳实现。
class _FakeContext extends Object implements BuildContext {
  @override
  bool get debugDoingBuild => false;

  @override
  bool get mounted => true;

  @override
  InheritedWidget dependOnInheritedElement(
    InheritedElement ancestor, {
    Object? aspect,
  }) => throw UnimplementedError();

  @override
  T? dependOnInheritedWidgetOfExactType<T extends InheritedWidget>({
    Object? aspect,
  }) => null;

  @override
  Size? get size => null;

  @override
  Widget get widget => throw UnimplementedError();

  @override
  void visitAncestorElements(bool Function(Element) visitor) {}

  @override
  void visitChildElements(void Function(Element) visitor) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
