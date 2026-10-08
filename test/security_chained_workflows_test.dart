/// 跨模块工作流串联与动作下钻 (chain-security-workflows) 的测试套件。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/database/security_database.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/models/security_models.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/models/security_enums.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/services/security_session_controller.dart';

Future<SecurityDatabase> openTestDatabase() async {
  final db = SecurityDatabase.forTesting(NativeDatabase.memory());
  await db.customStatement('PRAGMA foreign_keys = ON;');
  return db;
}

Future<SecuritySessionController> buildTestController(SecurityDatabase db) async {
  final controller = SecuritySessionController.withDatabase(db);
  await controller.refreshSessions();
  return controller;
}

void main() {
  group('NavigationIntent & AgentNextAction 数据模型', () {
    test('NavigationIntent 字段完整性与默认值', () {
      const intent = NavigationIntent(targetTab: 'vuln');
      expect(intent.targetTab, 'vuln');
      expect(intent.targetAsset, isNull);
      expect(intent.targetFinding, isNull);
      expect(intent.port, isNull);
      expect(intent.service, isNull);
      expect(intent.initialQuery, isNull);
      expect(intent.initialPrompt, isNull);
      expect(intent.extra, isEmpty);
    });

    test('AgentNextAction 构造与意图绑定', () {
      const intent = NavigationIntent(
        targetTab: 'exploit',
        initialQuery: 'CVE-2021-44228',
      );
      const action = AgentNextAction(
        title: '验证高危漏洞',
        description: '转至利用验证',
        actionLabel: '利用验证',
        intent: intent,
      );
      expect(action.title, '验证高危漏洞');
      expect(action.description, '转至利用验证');
      expect(action.actionLabel, '利用验证');
      expect(action.intent.targetTab, 'exploit');
      expect(action.intent.initialQuery, 'CVE-2021-44228');
    });

    test('PentestAsset.openPorts 解析 metadata 中的端口列表', () {
      final now = DateTime.now();
      final assetWithPorts = PentestAsset(
        id: 'asset-1',
        sessionId: 'sess-1',
        type: AssetType.host,
        address: '192.168.1.100',
        metadataJson: '{"ports":[{"port":80,"service":"http"},{"port":445,"service":"microsoft-ds"}]}',
        riskLevel: 'high',
        createdAt: now,
        updatedAt: now,
      );
      expect(assetWithPorts.openPorts.length, 2);
      expect(assetWithPorts.openPorts[0]['port'], 80);
      expect(assetWithPorts.openPorts[0]['service'], 'http');
      expect(assetWithPorts.openPorts[1]['port'], 445);
      expect(assetWithPorts.openPorts[1]['service'], 'microsoft-ds');

      final assetWithoutPorts = PentestAsset(
        id: 'asset-2',
        sessionId: 'sess-1',
        type: AssetType.host,
        address: '192.168.1.101',
        metadataJson: '{}',
        riskLevel: 'low',
        createdAt: now,
        updatedAt: now,
      );
      expect(assetWithoutPorts.openPorts, isEmpty);
    });
  });

  group('SecuritySessionController 导航与意图分发', () {
    late SecurityDatabase db;
    late SecuritySessionController controller;

    setUp(() async {
      db = await openTestDatabase();
      controller = await buildTestController(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('默认 activeTab 为 recon，无暂存意图', () {
      expect(controller.activeTab, 'recon');
      expect(controller.pendingIntent, isNull);
    });

    test('setActiveTab 切换 Tab 并通知监听者', () {
      var notified = false;
      controller.addListener(() => notified = true);

      controller.setActiveTab('vuln');
      expect(controller.activeTab, 'vuln');
      expect(notified, isTrue);
      expect(controller.pendingIntent, isNull);
    });

    test('navigateToTab 携带 NavigationIntent 并切换 Tab', () {
      var notifyCount = 0;
      controller.addListener(() => notifyCount++);

      final now = DateTime.now();
      final asset = PentestAsset(
        id: 'asset-10',
        sessionId: 'sess-10',
        type: AssetType.host,
        address: '192.168.1.50',
        metadataJson: '{}',
        riskLevel: 'medium',
        createdAt: now,
        updatedAt: now,
      );

      final intent = NavigationIntent(
        targetTab: 'exploit',
        targetAsset: asset,
        initialQuery: '192.168.1.50',
      );

      controller.navigateToTab('exploit', intent: intent);

      expect(controller.activeTab, 'exploit');
      expect(controller.pendingIntent, isNotNull);
      expect(controller.pendingIntent!.targetTab, 'exploit');
      expect(controller.pendingIntent!.targetAsset?.address, '192.168.1.50');
      expect(controller.pendingIntent!.initialQuery, '192.168.1.50');
      expect(notifyCount, 1);
    });

    test('consumeIntent 一次性消费并重置意图', () {
      const intent = NavigationIntent(
        targetTab: 'script',
        initialPrompt: '测试脚本 Prompt',
      );

      controller.navigateToTab('script', intent: intent);
      expect(controller.pendingIntent, isNotNull);

      final consumed = controller.consumeIntent();
      expect(consumed, isNotNull);
      expect(consumed!.targetTab, 'script');
      expect(consumed.initialPrompt, '测试脚本 Prompt');

      // 再次消费应为空
      final consumedAgain = controller.consumeIntent();
      expect(consumedAgain, isNull);
      expect(controller.pendingIntent, isNull);
    });
  });

  group('跨模块意图联动模拟', () {
    test('模拟从侦察资产触发漏洞利用验证全流程', () async {
      final now = DateTime.now();
      final asset = PentestAsset(
        id: 'asset-smb',
        sessionId: 'sess-1',
        type: AssetType.host,
        address: '192.168.1.200',
        metadataJson: '{"ports":[{"port":445,"service":"smb"}]}',
        riskLevel: 'critical',
        createdAt: now,
        updatedAt: now,
      );

      // 1. 模拟在 LanReconView 点击端口 445 -> 利用验证
      final intent = NavigationIntent(
        targetTab: 'exploit',
        targetAsset: asset,
        port: 445,
        service: 'smb',
        initialQuery: 'smb',
      );

      final db = await openTestDatabase();
      final controller = await buildTestController(db);
      controller.navigateToTab('exploit', intent: intent);

      expect(controller.activeTab, 'exploit');
      expect(controller.pendingIntent?.port, 445);
      expect(controller.pendingIntent?.service, 'smb');

      // 2. 模拟 ExploitView 加载并消费 intent
      final received = controller.consumeIntent();
      expect(received, isNotNull);
      expect(received!.targetAsset?.address, '192.168.1.200');
      expect(received.initialQuery, 'smb');
      expect(controller.pendingIntent, isNull);
      await db.close();
    });

    test('模拟从漏洞 Finding 触发脚本生成定制全流程', () async {
      final now = DateTime.now();
      final finding = PentestFinding(
        id: 'finding-log4j',
        sessionId: 'sess-1',
        assetId: 'asset-1',
        cveId: 'CVE-2021-44228',
        title: 'Apache Log4j RCE',
        severity: 'critical',
        cvssScore: 10.0,
        status: FindingStatus.open,
        evidence: '{"matched-at":"192.168.1.80:8080"}',
        source: FindingSource.nuclei,
        createdAt: now,
        updatedAt: now,
      );

      // 1. 模拟在 VulnScanView 点击“生成复测脚本”
      final intent = NavigationIntent(
        targetTab: 'script',
        targetFinding: finding,
        initialPrompt: '编写针对 Log4j (CVE-2021-44228) 的复测脚本',
      );

      final db = await openTestDatabase();
      final controller = await buildTestController(db);
      controller.navigateToTab('script', intent: intent);

      expect(controller.activeTab, 'script');

      // 2. 模拟 ScriptGeneratorView 消费
      final received = controller.consumeIntent();
      expect(received, isNotNull);
      expect(received!.targetFinding?.cveId, 'CVE-2021-44228');
      expect(received.initialPrompt, contains('Log4j'));
      expect(controller.pendingIntent, isNull);
      await db.close();
    });
  });
}
