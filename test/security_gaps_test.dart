/// `close-security-toolbox-gaps` 的回归测试。
///
/// 覆盖本次补齐的接线与数据来源修复：
/// - Agent executor 的分发、守卫、参数解析（不起真实进程）
/// - sqlmap 结果文件解析与 DBMS 归属、stdout 回退
/// - ffuf 字典双前缀定位
/// - 情报 Finding 去重
/// - API Key 脱敏 / 日报列表裁剪
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/services/digest_store.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/services/security_agent_executor.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/services/security_agent_service.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/services/security_pipeline_service.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/services/security_session_controller.dart';
import 'package:drift/native.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/database/security_database.dart' hide PentestSession;
import 'package:V8WorkToolbox/tools/security_toolbox/models/security_models.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/models/security_enums.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/services/security_repositories.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/services/security_settings_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/services/hydra_service.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/services/offline_remediation_advisor.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/services/vuln_scan_services.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/services/web_credential_service.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/services/web_recon_services.dart';

/// 内存库：测试里不起真实 SQLite 文件，也绕开 macOS 上缺失的 sqflite 平台通道。
Future<SecurityDatabase> openTestDatabase() async {
  final db = SecurityDatabase.forTesting(NativeDatabase.memory());
  // SQLite 默认忽略外键；不开则 finding.assetId 的 SET NULL 不生效。
  await db.customStatement('PRAGMA foreign_keys = ON;');
  return db;
}

/// 构造一个挂内存库的 controller（不探测工具、不跑 AI）。
Future<SecuritySessionController> buildTestController(
  SecurityDatabase db,
) async {
  final controller = SecuritySessionController.withDatabase(db);
  await controller.refreshSessions();
  return controller;
}

void main() {
  // ---------------------------------------------------------------------------
  // sqlmap 结构化解析（tasks 2.1–2.3）
  // ---------------------------------------------------------------------------

  group('sqlmap 结果文件解析', () {
    test('从 data 数组提取参数、注入技术与 DBMS', () {
      final dir = Directory.systemTemp.createTempSync('sqlmap_test_');
      try {
        final file = File('${dir.path}/result.json');
        file.writeAsStringSync(
          jsonEncode({
            'data': [
              {
                'parameter': 'id',
                'place': 'GET',
                'dbms': 'MySQL',
                'title': 'AND boolean-based blind',
              },
            ],
          }),
        );
        // mtime 必须是"本次运行之后"——脚本用 now 之前的文件模拟会被时间窗滤掉。
        file.setLastModifiedSync(DateTime.now());

        final findings = SqlmapService.parseResultFileForTest(
          file,
          'https://a.example.com/p?id=1',
        );
        expect(findings, hasLength(1));
        expect(findings.single.parameter, 'id');
        expect(findings.single.technique, 'GET');
        expect(findings.single.dbms, 'MySQL');
        expect(findings.single.title, contains('MySQL'));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('DBMS 从嵌套 value 里也能取到', () {
      final dir = Directory.systemTemp.createTempSync('sqlmap_test2_');
      try {
        final file = File('${dir.path}/result.json');
        file.writeAsStringSync(
          jsonEncode({
            'data': [
              {
                'value': {'parameter': 'q', 'place': 'POST', 'dbms': 'PostgreSQL'},
              },
            ],
          }),
        );
        file.setLastModifiedSync(DateTime.now());
        final findings = SqlmapService.parseResultFileForTest(
          file,
          'https://b.example.com/s?q=1',
        );
        expect(findings.single.parameter, 'q');
        expect(findings.single.dbms, 'PostgreSQL');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('畸形 JSON 返回空而不是抛', () {
      final dir = Directory.systemTemp.createTempSync('sqlmap_test3_');
      try {
        final file = File('${dir.path}/broken.json');
        file.writeAsStringSync('{"data": [');
        expect(
          SqlmapService.parseResultFileForTest(file, 'u'),
          isEmpty,
        );
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('多个参数各自拿到自己的 DBMS（不贴 list.last）', () {
      final dir = Directory.systemTemp.createTempSync('sqlmap_test4_');
      try {
        final file = File('${dir.path}/result.json');
        file.writeAsStringSync(
          jsonEncode({
            'data': [
              {'parameter': 'a', 'place': 'GET', 'dbms': 'MySQL'},
              {'parameter': 'b', 'place': 'GET', 'dbms': 'SQLite'},
            ],
          }),
        );
        file.setLastModifiedSync(DateTime.now());
        final findings = SqlmapService.parseResultFileForTest(file, 'u');
        expect(findings, hasLength(2));
        expect(findings[0].dbms, 'MySQL');
        expect(findings[1].dbms, 'SQLite');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('stdout 回退：DBMS 贴给该 URL 的每一条而不是最后一条', () {
      final findings = SqlmapService.parseStdoutForTest(
        'Parameter: id (GET)\n'
        'Parameter: name (GET)\n'
        'back-end DBMS: MySQL >= 5.6\n',
        'https://c.example.com/p?id=1&name=x',
      );
      expect(findings, hasLength(2));
      expect(findings[0].dbms, 'MySQL >= 5.6');
      expect(findings[1].dbms, 'MySQL >= 5.6');
    });

    test('stdout 回退：无可注入行时返回空', () {
      expect(
        SqlmapService.parseStdoutForTest('all tested parameters do not appear', 'u'),
        isEmpty,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // ffuf 字典定位（tasks 2.5–2.6）
  // ---------------------------------------------------------------------------

  group('ffuf 默认字典定位', () {
    test('按传入前缀顺序查找，命中即返回', () {
      // 用 /usr/bin 与 /usr/lib 这类必然存在但不含 seclists 的目录当前缀，
      // 验证"找不到返回 null"的分支。
      expect(
        FfufService.resolveDefaultWordlist(
          prefixes: ['/usr/bin', '/usr/lib'],
        ),
        null,
      );
    });

    test('真实文件命中时返回该路径', () {
      final dir = Directory.systemTemp.createTempSync('ffuf_wl_');
      try {
        final target = File(
          '${dir.path}/seclists/Discovery/Web-Content/common.txt',
        );
        target.parent.createSync(recursive: true);
        target.writeAsStringSync('admin\napi\n');
        expect(
          FfufService.resolveDefaultWordlist(prefixes: [dir.path]),
          target.path,
        );
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('第一个前缀没有时继续找第二个', () {
      final a = Directory.systemTemp.createTempSync('ffuf_a_');
      final b = Directory.systemTemp.createTempSync('ffuf_b_');
      try {
        final target = File(
          '${b.path}/seclists/Discovery/Web-Content/common.txt',
        );
        target.parent.createSync(recursive: true);
        target.writeAsStringSync('x\n');
        expect(
          FfufService.resolveDefaultWordlist(prefixes: [a.path, b.path]),
          target.path,
        );
      } finally {
        a.deleteSync(recursive: true);
        b.deleteSync(recursive: true);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // 情报 Finding 去重（tasks 4.1 / 4.4）
  // ---------------------------------------------------------------------------

  group('情报 Finding 去重', () {
    test('同 资产+CVE 判定已存在，cveId 为空不去重', () async {
      final db = await openTestDatabase();
      try {
        final sessions = SessionRepository(db);
        final findings = FindingRepository(db);
        final session = await sessions.create(
          name: 's',
          type: 'web',
          scope: ['example.com'],
        );
        await findings.add(
          sessionId: session.id,
          cveId: 'CVE-2024-0001',
          title: '情报匹配',
          severity: 'high',
          source: 'intel_match',
        );

        expect(
          await findings.existsForAssetCve(session.id, null, 'CVE-2024-0001'),
          isFalse,
          reason: 'assetId 为空时无法定位资产，不参与去重',
        );
        // assetId 为空的场景由 UI 层保证不会传入。
        final assets = AssetRepository(db);
        final asset = await assets.upsert(
          sessionId: session.id,
          type: 'url',
          address: 'example.com',
        );
        expect(
          await findings.existsForAssetCve(session.id, asset.id, 'CVE-2024-0001'),
          isFalse,
          reason: '该 Finding 的 assetId 为空，按 assetId 查不到',
        );
        expect(
          await findings.existsForAssetCve(session.id, asset.id, 'CVE-9999-9999'),
          isFalse,
        );
        expect(
          await findings.existsForAssetCve(session.id, asset.id, null),
          isFalse,
          reason: 'CVE 为空不可比',
        );
      } finally {
        await db.close();
      }
    });

    test('同一资产上已有该 CVE 的 Finding 时判重为 true', () async {
      final db = await openTestDatabase();
      try {
        final sessions = SessionRepository(db);
        final findings = FindingRepository(db);
        final assets = AssetRepository(db);
        final session = await sessions.create(
          name: 's2',
          type: 'web',
          scope: ['b.example.com'],
        );
        final asset = await assets.upsert(
          sessionId: session.id,
          type: 'url',
          address: 'b.example.com',
        );
        await findings.add(
          sessionId: session.id,
          assetId: asset.id,
          cveId: 'CVE-2024-0002',
          title: '情报匹配',
          severity: 'critical',
          source: 'intel_match',
        );
        expect(
          await findings.existsForAssetCve(session.id, asset.id, 'CVE-2024-0002'),
          isTrue,
        );
        expect(
          await findings.existsForAssetCve(session.id, asset.id, 'CVE-2024-0003'),
          isFalse,
        );
      } finally {
        await db.close();
      }
    });
  });

  // ---------------------------------------------------------------------------
  // API Key 脱敏与日报列表裁剪（tasks 3.3 / 4.8）
  // ---------------------------------------------------------------------------

  group('maskApiKey', () {
    test('空串显示未配置', () {
      expect(maskApiKey(''), '未配置');
      expect(maskApiKey('   '), '未配置');
    });

    test('过短的 key 不泄露任何片段', () {
      expect(maskApiKey('ab'), '****');
      expect(maskApiKey('abcd'), '****');
    });

    test('正常 key 仅留末 4 位', () {
      expect(maskApiKey('abcdef123456'), '****3456');
    });
  });

  // ---------------------------------------------------------------------------
  // Agent executor 的分发与守卫（task 1.14）
  // ---------------------------------------------------------------------------

  group('SecurityAgentExecutor', () {
    test('无会话时返回引导文案且不写库', () async {
      final db = await openTestDatabase();
      try {
        final controller = await buildTestController(db);
        final outcome = await SecurityAgentExecutor(controller).call(
          'run_nmap',
          {'target': '127.0.0.1'},
        );
        expect(outcome.isError, isFalse);
        expect(outcome.text, contains('没有会话'));
        expect(controller.logs, isEmpty,
            reason: '守卫分支不该产生任何日志或数据库写入');
      } finally {
        await db.close();
      }
    });

    test('未知工具名返回 failure 而不是 success', () async {
      final db = await openTestDatabase();
      try {
        final controller = await buildTestController(db);
        await controller.createSession(
          name: 's',
          type: 'lan',
          scope: ['127.0.0.1'],
        );
        final outcome = await SecurityAgentExecutor(controller).call(
          'run_not_a_tool',
          const {},
        );
        expect(outcome.isError, isTrue);
        expect(outcome.error, contains('未知工具'));
      } finally {
        await db.close();
      }
    });

    test('缺少必填参数返回 failure 且指明参数名', () async {
      final db = await openTestDatabase();
      try {
        final controller = await buildTestController(db);
        await controller.createSession(
          name: 's',
          type: 'lan',
          scope: ['127.0.0.1'],
        );
        // nuclei 未安装 → 走不到参数校验之后，先验证 nmap 的 target 校验。
        final outcome = await SecurityAgentExecutor(controller).call(
          'run_subfinder',
          const {},
        );
        expect(outcome.isError, isTrue);
        expect(outcome.error, contains('domain'));
      } finally {
        await db.close();
      }
    });

    test('get_session_findings 无发现时给出可读结论', () async {
      final db = await openTestDatabase();
      try {
        final controller = await buildTestController(db);
        await controller.createSession(
          name: 's',
          type: 'lan',
          scope: ['127.0.0.1'],
        );
        final outcome = await SecurityAgentExecutor(controller).call(
          'get_session_findings',
          const {},
        );
        expect(outcome.isError, isFalse);
        expect(outcome.text, contains('没有漏洞发现'));
      } finally {
        await db.close();
      }
    });

    test('返回文本不超过 500 字符（context 保护）', () async {
      final db = await openTestDatabase();
      try {
        final controller = await buildTestController(db);
        await controller.createSession(
          name: 's',
          type: 'lan',
          scope: ['127.0.0.1'],
        );
        // Finding 不存在时是短文案；有 Finding 时也必须在 500 内。
        for (var i = 0; i < 40; i++) {
          await controller.findings.add(
            sessionId: controller.current!.id,
            title: 'Finding-$i-${'x' * 40}',
            severity: 'high',
            source: 'nuclei',
          );
        }
        await controller.reloadSessionData();
        final outcome = await SecurityAgentExecutor(controller).call(
          'get_session_findings',
          const {},
        );
        expect(outcome.text.length, lessThanOrEqualTo(520),
            reason: '500 + 截断标记');
      } finally {
        await db.close();
      }
    });

    test('SecurityAgentService 状态重置与报告保存', () {
      final service = SecurityAgentService.instance;
      service.reset();
      expect(service.state, AgentRunState.idle);
      expect(service.currentTool, isNull);
      expect(service.finalReport, isNull);
      expect(service.steps, isEmpty);
    });

    test('SecurityAgentService 多会话状态隔离与切换', () {
      final service = SecurityAgentService.instance;
      service.switchSession('session-1');
      service.finalReport = '会话 1 的渗透报告';
      service.state = AgentRunState.done;

      service.switchSession('session-2');
      expect(service.finalReport, isNull);
      expect(service.state, AgentRunState.idle);

      service.finalReport = '会话 2 的报告';
      service.switchSession('session-1');
      expect(service.finalReport, '会话 1 的渗透报告');
      expect(service.state, AgentRunState.done);

      service.removeSession('session-1');
      expect(service.finalReport, isNull);
    });

    test('SecurityAgentService 会话草稿隔离与切换', () {
      final service = SecurityAgentService.instance;
      service.switchSession('sess-a');
      service.taskDraft = '自定义任务 A';

      service.switchSession('sess-b');
      expect(service.taskDraft, isNull);

      service.taskDraft = '自定义任务 B';
      service.switchSession('sess-a');
      expect(service.taskDraft, '自定义任务 A');

      // reset 默认不清除草稿
      service.reset('sess-a');
      expect(service.taskDraft, '自定义任务 A');

      // clearDraft=true 时清除草稿
      service.reset('sess-a', true);
      expect(service.taskDraft, isNull);
    });

    test('SecurityAgentService 推荐预设任务自动生成与优先读取草稿', () {
      final service = SecurityAgentService.instance;
      final webSession = PentestSession(
        id: 'web-1',
        name: '91',
        type: SessionType.web,
        scopeJson: jsonEncode(['91porn.com']),
        status: SessionStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final lanSession = PentestSession(
        id: 'lan-1',
        name: 'LAN',
        type: SessionType.lan,
        scopeJson: jsonEncode(['192.168.1.0/24']),
        status: SessionStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // 无草稿时自动生成推荐预设
      final webTask = service.resolveDefaultTask(webSession);
      expect(webTask, contains('91porn.com'));
      expect(webTask, contains('subfinder'));

      final lanTask = service.resolveDefaultTask(lanSession);
      expect(lanTask, contains('192.168.1.0/24'));
      expect(lanTask, contains('ARP 发现'));

      // 设置草稿后优先返回草稿
      service.setTaskDraft('web-1', '我自定义的扫描任务');
      expect(service.resolveDefaultTask(webSession), '我自定义的扫描任务');
    });
  });

  group('DigestStore', () {
    test('空内容不落盘', () async {
      final dir = Directory.systemTemp.createTempSync('digest_');
      try {
        DigestStore.debugOverrideDir = dir;
        await DigestStore.instance.append('   ');
        expect(await DigestStore.instance.recent(), isEmpty);
      } finally {
        DigestStore.debugOverrideDir = null;
        dir.deleteSync(recursive: true);
      }
    });

    test('写入后 recent 返回，新的在前', () async {
      final dir = Directory.systemTemp.createTempSync('digest2_');
      try {
        DigestStore.debugOverrideDir = dir;
        await DigestStore.instance.append('第一条');
        await Future.delayed(const Duration(milliseconds: 5));
        await DigestStore.instance.append('第二条');
        final list = await DigestStore.instance.recent();
        expect(list, hasLength(2));
        expect(list.first.text, '第二条');
        expect(list.first.headline, '第二条');
      } finally {
        DigestStore.debugOverrideDir = null;
        dir.deleteSync(recursive: true);
      }
    });

    test('超 7 天的记录被裁掉', () async {
      final dir = Directory.systemTemp.createTempSync('digest3_');
      try {
        DigestStore.debugOverrideDir = dir;
        File('${dir.path}/news_digests.json').writeAsStringSync(
          jsonEncode([
            {
              'id': 'old',
              'text': '九天前',
              'created_at': DateTime.now()
                  .subtract(const Duration(days: 9))
                  .millisecondsSinceEpoch,
            },
            {
              'id': 'new',
              'text': '今天',
              'created_at': DateTime.now().millisecondsSinceEpoch,
            },
          ]),
        );
        final list = await DigestStore.instance.recent();
        expect(list, hasLength(1));
        expect(list.single.id, 'new');
        // 裁剪应已落盘
        final onDisk = jsonDecode(
          File('${dir.path}/news_digests.json').readAsStringSync(),
        ) as List;
        expect(onDisk, hasLength(1));
      } finally {
        DigestStore.debugOverrideDir = null;
        dir.deleteSync(recursive: true);
      }
    });

    test('文件损坏时退化为空列表', () async {
      final dir = Directory.systemTemp.createTempSync('digest4_');
      try {
        DigestStore.debugOverrideDir = dir;
        File('${dir.path}/news_digests.json').writeAsStringSync('not json');
        expect(await DigestStore.instance.recent(), isEmpty);
      } finally {
        DigestStore.debugOverrideDir = null;
        dir.deleteSync(recursive: true);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // 资产性能优化与级联会话删除测试
  // ---------------------------------------------------------------------------

  group('资产性能优化与级联删除', () {
    test('PentestAsset.metadata 内存缓存测试', () {
      final jsonStr = jsonEncode({'status_code': 200, 'server': 'nginx'});
      final asset = PentestAsset(
        id: 'ast-1',
        sessionId: 's-1',
        type: AssetType.url,
        address: 'https://example.com',
        riskLevel: 'low',
        metadataJson: jsonStr,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final firstAccess = asset.metadata;
      final secondAccess = asset.metadata;
      expect(identical(firstAccess, secondAccess), isTrue,
          reason: '多次访问 metadata 应命中同一内存对象，避免重复 jsonDecode');
      expect(firstAccess['status_code'], 200);

      // copyWith 同 metadataJson 应沿用缓存
      final copiedSame = asset.copyWith(riskLevel: 'high');
      expect(identical(copiedSame.metadata, firstAccess), isTrue);

      // copyWith 新 metadataJson 应解析新数据
      final newJson = jsonEncode({'status_code': 404});
      final copiedNew = asset.copyWith(metadataJson: newJson);
      expect(copiedNew.metadata['status_code'], 404);
    });

    test('批量删除会话、级联清理资产与发现物，以及当前会话自动回退', () async {
      final db = await openTestDatabase();
      final controller = await buildTestController(db);

      try {
        final s1 = await controller.createSession(
          name: 'Session 1',
          type: SessionType.web,
          scope: ['https://s1.example.com'],
        );
        final s2 = await controller.createSession(
          name: 'Session 2',
          type: SessionType.lan,
          scope: ['192.168.1.0/24'],
        );

        // 为 Session 1 添加多个资产与发现物
        for (var i = 0; i < 20; i++) {
          final asset = await controller.assets.upsert(
            sessionId: s1.id,
            type: AssetType.url,
            address: 'https://sub$i.s1.example.com',
            metadata: {'index': i},
          );
          await controller.findings.add(
            sessionId: s1.id,
            source: 'nuclei',
            title: 'Vuln $i',
            severity: Severity.medium.key,
            assetId: asset.id,
          );
        }

        // 为 Session 2 添加少量资产
        final s2Asset = await controller.assets.upsert(
          sessionId: s2.id,
          type: AssetType.host,
          address: '192.168.1.100',
        );

        // 选中 Session 1
        await controller.selectSession(s1.id);
        expect(controller.current?.id, s1.id);
        expect(controller.assetList, hasLength(20));
        expect(controller.findingList, hasLength(20));

        // 删除 Session 1
        await controller.deleteSession(s1.id);

        // 验证 Session 1 相关数据已被完全删除
        final remainingSessions = await controller.sessions.all();
        expect(remainingSessions.map((s) => s.id), isNot(contains(s1.id)));
        expect(await controller.assets.forSession(s1.id), isEmpty);
        expect(await controller.findings.forSession(s1.id), isEmpty);

        // 验证 Session 2 数据完好无损
        final s2Assets = await controller.assets.forSession(s2.id);
        expect(s2Assets, hasLength(1));
        expect(s2Assets.single.id, s2Asset.id);

        // 验证 controller.current 自动平滑回退至剩余会话 Session 2
        expect(controller.current?.id, s2.id);

        // 删除 Session 2，列表清空后 controller.current 应为 null
        await controller.deleteSession(s2.id);
        expect(controller.sessionList, isEmpty);
        expect(controller.current, isNull);
      } finally {
        await db.close();
      }
    });
  });

  // ---------------------------------------------------------------------------
  // 防御型 AI、拒答检测与离线报告降级 (tasks 1.1–2.3)
  // ---------------------------------------------------------------------------

  group('防御型 AI 提示词与拒答降级', () {
    test('拒答检测识别典型商业模型安全拦截文本', () {
      expect(
        SecurityAgentService.isRefusalResponse(
          '我无法协助你对特定目标进行渗透测试、漏洞扫描或生成安全评估报告。',
        ),
        isTrue,
      );
      expect(
        SecurityAgentService.isRefusalResponse(
          '我不能执行此操作，因为这违反了安全策略。建议通过合法途径进行测试。',
        ),
        isTrue,
      );
      expect(
        SecurityAgentService.isRefusalResponse(
          'As an AI model, I cannot assist with offensive security operations.',
        ),
        isTrue,
      );
      expect(
        SecurityAgentService.isRefusalResponse(''),
        isTrue,
      );

      // 正常的安全加固与审计建议报告不应被误判为拒答
      expect(
        SecurityAgentService.isRefusalResponse(
          '### 安全加固与合规审计报告\n\n1. 资产暴露面评估：发现 3 个对外 HTTP 端点，建议收敛管理接口。',
        ),
        isFalse,
      );
      expect(
        SecurityAgentService.isRefusalResponse(
          '建议在 Nginx 配置中增加 Strict-Transport-Security 与 Content-Security-Policy 标头。',
        ),
        isFalse,
      );
    });

    test('本地离线报告自动生成结构完整且中立的 Markdown 审计建议', () {
      final session = PentestSession(
        id: 'sess-offline-test',
        name: '生产环境基线审计',
        type: SessionType.web,
        scopeJson: '["internal.corp.local"]',
        status: SessionStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final assets = [
        PentestAsset(
          id: 'a1',
          sessionId: session.id,
          type: AssetType.url,
          address: 'https://internal.corp.local',
          metadataJson: '{"status_code": 200, "tech_stack": ["Nginx", "Vue.js"]}',
          riskLevel: 'low',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        PentestAsset(
          id: 'a2',
          sessionId: session.id,
          type: AssetType.url,
          address: 'https://api.internal.corp.local',
          metadataJson: '{"status_code": 403}',
          riskLevel: 'low',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      final findings = [
        PentestFinding(
          id: 'f1',
          sessionId: session.id,
          source: 'nuclei',
          title: 'Spring Cloud Gateway RCE',
          severity: Severity.critical.key,
          cveId: 'CVE-2022-22947',
          status: FindingStatus.open,
          assetId: 'a1',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        PentestFinding(
          id: 'f2',
          sessionId: session.id,
          source: 'nuclei',
          title: 'Missing Security Headers',
          severity: Severity.low.key,
          status: FindingStatus.open,
          assetId: 'a1',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      final report = SecurityAgentService.buildOfflineFallbackReport(
        session,
        assets,
        findings,
      );

      expect(report, contains('安全基线巡检与系统防御加固报告'));
      expect(report, contains('internal.corp.local'));
      expect(report, contains('已发现存活资产**: `2` 个'));
      expect(report, contains('检测到的脆弱性风险**: `2` 项'));
      expect(report, contains('高危风险**: `1` 项'));
      expect(report, contains('收敛公网暴露面'));
      expect(report, contains('跟进官方补丁更新'));
      expect(report, contains('加固传输与应用防护'));
    });

    test('任务预设采用系统防御与合规审计口吻，避免攻击性词汇', () {
      final webTask = webOneClickTask('example.com');
      expect(webTask, contains('安全基线'));
      expect(webTask, contains('暴露面'));
      expect(webTask, contains('防御加固建议'));
      expect(webTask, isNot(contains('全面评估 baidu.com 的 Web 安全：subfinder 枚举子域名 → httpx 探测存活资产 → katana 爬取端点 → nuclei 扫描漏洞 → sqlmap 检测注入点')));

      final lanTask = lanOneClickTask('192.168.1.0/24');
      expect(lanTask, contains('安全基线'));
      expect(lanTask, contains('暴露面排查'));
      expect(lanTask, contains('防御加固建议'));
    });
  });

  group('SecurityPipelineService 原生流水线控制', () {
    test('流水线单例初始状态为非运行中，cancel 安全复位', () {
      final pipeline = SecurityPipelineService.instance;
      expect(pipeline.isRunning, isFalse);

      // 当非运行态调用 cancel 时不应报错
      pipeline.cancel();
      expect(pipeline.isRunning, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Nuclei 标签映射与控制台最新日志切片 (fix-nuclei-scan-execution-and-console-logs)
  // ---------------------------------------------------------------------------

  group('Nuclei 参数映射与流式日志', () {
    test('NucleiCategory 正确映射标准 Nuclei Tags', () {
      expect(NucleiCategory.cves.tag, 'cve');
      expect(NucleiCategory.exposures.tag, 'exposure');
      expect(NucleiCategory.misconfiguration.tag, 'misconfig');
      expect(NucleiCategory.defaultLogins.tag, 'default-login');
      expect(NucleiCategory.network.tag, 'network');
      expect(NucleiCategory.technologies.tag, 'tech');
    });

    test('NucleiService.buildArgs 生成正确的 -tags 参数并移除 -silent', () {
      final defaultArgs = NucleiService.buildArgs([NucleiCategory.cves]);
      expect(defaultArgs, contains('-jsonl'));
      expect(defaultArgs, contains('-no-color'));
      expect(defaultArgs, isNot(contains('-silent')));
      expect(defaultArgs, contains('-tags'));
      expect(defaultArgs, contains('cve'));
      expect(defaultArgs, isNot(contains('-t')));

      final multiArgs = NucleiService.buildArgs([
        NucleiCategory.cves,
        NucleiCategory.misconfiguration,
        NucleiCategory.exposures,
      ]);
      expect(multiArgs, contains('-tags'));
      expect(multiArgs, contains('cve,misconfig,exposure'));
    });
  });

  group('SecuritySessionController recentLogs 切片与清空', () {
    test('recentLogs 在日志较少时返回全部，在日志较多时截取最新的尾部', () async {
      final db = await openTestDatabase();
      try {
        final controller = await buildTestController(db);

        // 空日志
        expect(controller.recentLogs(), isEmpty);

        // 添加 10 条日志
        for (var i = 0; i < 10; i++) {
          controller.log('Log entry $i');
        }
        expect(controller.recentLogs(), hasLength(10));
        expect(controller.recentLogs().first, 'Log entry 0');
        expect(controller.recentLogs().last, 'Log entry 9');

        // 添加超过 100 条日志（共 120 条）
        for (var i = 10; i < 120; i++) {
          controller.log('Log entry $i');
        }
        expect(controller.logs, hasLength(120));

        // 默认保留最近 100 条（即 entry 20 到 119）
        final recent = controller.recentLogs(100);
        expect(recent, hasLength(100));
        expect(recent.first, 'Log entry 20');
        expect(recent.last, 'Log entry 119');

        // 清空日志
        controller.clearLogs();
        expect(controller.logs, isEmpty);
        expect(controller.recentLogs(), isEmpty);
      } finally {
        await db.close();
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Nuclei 周期统计流、严重度过滤与资产提取 (optimize-nuclei-progress-stats-and-finding-attribution)
  // ---------------------------------------------------------------------------

  group('Nuclei 周期统计流与资产提取', () {
    test('extractHost 准确提取各种形式的主机名与 IP，剥除协议与端口', () {
      expect(NucleiService.extractHost('www.v8en.com:22'), 'www.v8en.com');
      expect(NucleiService.extractHost('192.168.1.1:8080'), '192.168.1.1');
      expect(
        NucleiService.extractHost('https://api.v8en.com:8443/login.php?id=1'),
        'api.v8en.com',
      );
      expect(
        NucleiService.extractHost('http://sub.domain.com/path'),
        'sub.domain.com',
      );
      expect(NucleiService.extractHost('v8en.com'), 'v8en.com');
      expect(NucleiService.extractHost('   mail.v8en.com:25  '), 'mail.v8en.com');
      expect(NucleiService.extractHost(''), '');
    });

    test('formatStatsLine 正确识别并格式化 Nuclei 统计 JSON', () {
      final statsMap = {
        'percent': '35',
        'requests': '350',
        'total': '1000',
        'rps': '70',
        'matched': '3',
        'duration': '0:00:05',
      };
      final line = NucleiService.formatStatsLine(statsMap);
      expect(line, isNotNull);
      expect(line, contains('[扫描进度] 35%'));
      expect(line, contains('请求: 350/1000'));
      expect(line, contains('(70 req/s)'));
      expect(line, contains('发现: 3'));
      expect(line, contains('耗时: 0:00:05'));

      // 发现物或普通事件 JSON 不应被误判为统计帧
      final findingMap = {
        'template-id': 'ssh-detect',
        'info': {'name': 'OpenSSH Detect', 'severity': 'info'},
      };
      expect(NucleiService.formatStatsLine(findingMap), isNull);
    });

    test('buildArgs 正确包含 -stats, -si 与 -s 严重度等级', () {
      final argsWithStatsAndSev = NucleiService.buildArgs(
        [NucleiCategory.cves],
        severities: [Severity.critical, Severity.high, Severity.medium],
        enableStats: true,
        statsIntervalSeconds: 5,
      );
      expect(argsWithStatsAndSev, contains('-stats'));
      expect(argsWithStatsAndSev, contains('-si'));
      expect(argsWithStatsAndSev, contains('5'));
      expect(argsWithStatsAndSev, contains('-s'));
      expect(argsWithStatsAndSev, contains('critical,high,medium'));

      final argsWithoutStats = NucleiService.buildArgs(
        [NucleiCategory.cves],
        enableStats: false,
      );
      expect(argsWithoutStats, isNot(contains('-stats')));
      expect(argsWithoutStats, isNot(contains('-s')));
    });
  });

  // ---------------------------------------------------------------------------
  // 离线加固建议引擎与批量处置 (enhance-vuln-ai-remediation-and-batch-actions)
  // ---------------------------------------------------------------------------

  group('OfflineRemediationAdvisor 离线防御加固建议', () {
    test('对 SSH 暴露漏洞生成特定加固与访问控制建议', () {
      final finding = PentestFinding(
        id: 'f-ssh',
        sessionId: 's1',
        title: 'OpenSSH Service - Detect',
        severity: Severity.info.key,
        status: FindingStatus.open,
        source: FindingSource.nuclei,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final advice = OfflineRemediationAdvisor.build(
        finding: finding,
        targetHost: 'www.v8en.com:22',
      );

      expect(advice, contains('www.v8en.com:22'));
      expect(advice, contains('PermitRootLogin'));
      expect(advice, contains('PasswordAuthentication no'));
      expect(advice, contains('fail2ban'));
      expect(advice, contains('网络 ACL'));
    });

    test('对 SQL 注入漏洞生成预编译与最小权限建议', () {
      final finding = PentestFinding(
        id: 'f-sqli',
        sessionId: 's1',
        title: 'MySQL Blind SQL Injection',
        severity: Severity.high.key,
        status: FindingStatus.open,
        source: FindingSource.sqlmap,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final advice = OfflineRemediationAdvisor.build(
        finding: finding,
        targetHost: 'https://v8en.com/item.php?id=1',
      );

      expect(advice, contains('预编译参数化查询'));
      expect(advice, contains('Prepared Statements'));
      expect(advice, contains('最小权限'));
      expect(advice, contains('WAF'));
    });

    test('对已知 CVE 生成官方补丁与 NVD 查询指引', () {
      final finding = PentestFinding(
        id: 'f-cve',
        sessionId: 's1',
        title: 'Spring Cloud Gateway RCE',
        severity: Severity.critical.key,
        cveId: 'CVE-2022-22947',
        status: FindingStatus.open,
        source: FindingSource.nuclei,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final advice = OfflineRemediationAdvisor.build(
        finding: finding,
        targetHost: 'gateway.v8en.com:8080',
      );

      expect(advice, contains('CVE-2022-22947'));
      expect(advice, contains('https://nvd.nist.gov/vuln/detail/CVE-2022-22947'));
      expect(advice, contains('官方安全公告'));
      expect(advice, contains('最新安全稳定版本'));
    });

    test('buildBatchSummary 正确聚合共性脆弱点并生成 Markdown 结构报告', () {
      final findings = [
        PentestFinding(
          id: 'f1',
          sessionId: 's1',
          title: 'OpenSSH Service - Detect',
          severity: Severity.info.key,
          status: FindingStatus.open,
          source: FindingSource.nuclei,
          assetId: 'a1',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        PentestFinding(
          id: 'f2',
          sessionId: 's1',
          title: 'OpenSSH Service - Detect',
          severity: Severity.info.key,
          status: FindingStatus.open,
          source: FindingSource.nuclei,
          assetId: 'a2',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        PentestFinding(
          id: 'f3',
          sessionId: 's1',
          title: 'MySQL Blind SQL Injection',
          severity: Severity.high.key,
          status: FindingStatus.open,
          source: FindingSource.sqlmap,
          assetId: 'a1',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      final assets = [
        PentestAsset(
          id: 'a1',
          sessionId: 's1',
          type: AssetType.host,
          address: '1.1.1.1',
          metadataJson: '{}',
          riskLevel: 'unknown',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        PentestAsset(
          id: 'a2',
          sessionId: 's1',
          type: AssetType.host,
          address: '2.2.2.2',
          metadataJson: '{}',
          riskLevel: 'unknown',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      final report = OfflineRemediationAdvisor.buildBatchSummary(
        sessionName: '演示巡检会话',
        findings: findings,
        assets: assets,
      );

      expect(report, contains('《系统安全基线排查与漏洞加固全量处置清单》'));
      expect(report, contains('演示巡检会话'));
      expect(report, contains('高危风险 (High)**：`1` 项'));
      expect(report, contains('低危/信息 (Low/Info)**：`2` 项'));
      expect(report, contains('OpenSSH Service - Detect【信息，影响 2 个目标】'));
    });
  });

  group('FindingRepository.batchSetStatus 与 Controller 批量更新', () {
    test('batchSetStatus 批量更新数据库中多个 Finding 的状态', () async {
      final db = await openTestDatabase();
      try {
        final controller = await buildTestController(db);
        final session = await controller.sessions.create(
          name: 'Batch Status Test',
          type: SessionType.web,
          scope: ['https://example.com'],
        );
        await controller.selectSession(session.id);

        final f1 = await controller.findings.add(
          sessionId: session.id,
          title: 'Vuln 1',
          severity: Severity.high.key,
          source: FindingSource.nuclei,
        );
        final f2 = await controller.findings.add(
          sessionId: session.id,
          title: 'Vuln 2',
          severity: Severity.critical.key,
          source: FindingSource.nuclei,
        );
        final f3 = await controller.findings.add(
          sessionId: session.id,
          title: 'Vuln 3',
          severity: Severity.medium.key,
          source: FindingSource.nuclei,
        );
        await controller.reloadSessionData();

        expect(controller.findingList.map((f) => f.status).toSet(), {FindingStatus.open});

        // 批量标记 f1, f2 为已确认 (verified)
        await controller.batchSetFindingStatus([f1.id, f2.id], FindingStatus.verified);

        final findingsAfter = controller.findingList;
        expect(findingsAfter.firstWhere((f) => f.id == f1.id).status, FindingStatus.verified);
        expect(findingsAfter.firstWhere((f) => f.id == f2.id).status, FindingStatus.verified);
        expect(findingsAfter.firstWhere((f) => f.id == f3.id).status, FindingStatus.open);

        // 批量标记 f1, f2, f3 为误报 (false_positive)
        await controller.batchSetFindingStatus([f1.id, f2.id, f3.id], FindingStatus.falsePositive);
        expect(controller.findingList.map((f) => f.status).toSet(), {FindingStatus.falsePositive});
      } finally {
        await db.close();
      }
    });
  });

  group('HydraService 命令行与弱口令解析', () {
    test('buildArgs 生成正确参数结构', () {
      final args = HydraService.buildArgs(
        userFilePath: '/tmp/users.txt',
        passFilePath: '/tmp/pass.txt',
        target: '192.168.1.10',
        service: 'ssh',
        port: 2222,
        threads: 6,
      );

      expect(args, containsAllInOrder(['-L', '/tmp/users.txt']));
      expect(args, containsAllInOrder(['-P', '/tmp/pass.txt']));
      expect(args, containsAllInOrder(['-t', '6']));
      expect(args, containsAllInOrder(['-s', '2222']));
      expect(args.last, 'ssh');
      expect(args[args.length - 2], '192.168.1.10');
    });

    test('parseOutputLine 正确提取标准格式命中行', () {
      const line = '[22][ssh] host: 192.168.1.50   login: admin   password: password123';
      final finding = HydraService.parseOutputLine(line);

      expect(finding, isNotNull);
      expect(finding!.target, '192.168.1.50');
      expect(finding.port, 22);
      expect(finding.service, 'ssh');
      expect(finding.username, 'admin');
      expect(finding.password, 'password123');
    });

    test('parseOutputLine 正确处理宽松格式', () {
      const line = 'host: 10.0.0.1   login: root   password: toor';
      final finding = HydraService.parseOutputLine(
        line,
        fallbackTarget: '10.0.0.1',
        fallbackService: 'ftp',
        fallbackPort: 21,
      );

      expect(finding, isNotNull);
      expect(finding!.target, '10.0.0.1');
      expect(finding.service, 'ftp');
      expect(finding.username, 'root');
      expect(finding.password, 'toor');
    });

    test('parseOutputLine 忽略非命中行与进度行', () {
      expect(HydraService.parseOutputLine('[STATUS] 10 tries / min'), isNull);
      expect(HydraService.parseOutputLine('Hydra (https://www.thc.org) starting at 2026-10-03'), isNull);
      expect(HydraService.parseOutputLine(''), isNull);
    });
  });

  group('WebFormCredentialService 表单探测与弱口令判定', () {
    test('isCandidateLoginUrl 正确识别常见登录 URL', () {
      expect(WebFormCredentialService.isCandidateLoginUrl('https://example.com/login'), isTrue);
      expect(WebFormCredentialService.isCandidateLoginUrl('https://example.com/admin/login.php'), isTrue);
      expect(WebFormCredentialService.isCandidateLoginUrl('https://example.com/user/signin'), isTrue);
      expect(WebFormCredentialService.isCandidateLoginUrl('https://example.com/auth/portal'), isTrue);
      expect(WebFormCredentialService.isCandidateLoginUrl('https://example.com/articles/123'), isFalse);
      expect(WebFormCredentialService.isCandidateLoginUrl('https://example.com/about-us'), isFalse);
    });

    test('parseLoginForm 正确提取 action、username、password 及 CSRF 字段', () {
      const html = '''
<!DOCTYPE html>
<html>
<body>
  <form action="/auth/do_login" method="POST">
    <input type="hidden" name="_csrf_token" value="secret_csrf_123">
    <input type="text" name="user_account" placeholder="Username">
    <input type="password" name="user_password" placeholder="Password">
    <button type="submit">登录</button>
  </form>
</body>
</html>
''';
      final form = WebFormCredentialService.parseLoginForm(html, 'https://example.com/login');
      expect(form, isNotNull);
      expect(form!.actionUrl, 'https://example.com/auth/do_login');
      expect(form.method, 'POST');
      expect(form.usernameField, 'user_account');
      expect(form.passwordField, 'user_password');
      expect(form.csrfField, '_csrf_token');
      expect(form.csrfToken, 'secret_csrf_123');
    });

    test('parseLoginForm 无密码框页面返回 null', () {
      const html = '<html><body><h1>Welcome</h1><input type="text" name="search"></body></html>';
      expect(WebFormCredentialService.parseLoginForm(html, 'https://example.com/'), isNull);
    });

    test('evaluateSuccess 判定逻辑：302 跳转、关键词命中与错误关键词排除', () {
      // 302 跳转判定成功
      expect(
        WebFormCredentialService.evaluateSuccess(
          statusCode: 302,
          body: '',
          headers: {'location': '/admin/dashboard'},
          originalUrl: 'https://example.com/login',
        ),
        'confirmed',
      );

      // 302 跳回 login 判定为失败
      expect(
        WebFormCredentialService.evaluateSuccess(
          statusCode: 302,
          body: '',
          headers: {'location': '/login?error=1'},
          originalUrl: 'https://example.com/login',
        ),
        isNull,
      );

      // 200 包含明确成功词判定为 confirmed
      expect(
        WebFormCredentialService.evaluateSuccess(
          statusCode: 200,
          body: '<html><body>欢迎管理员，<a href="/logout">退出登录</a></body></html>',
          headers: {},
          originalUrl: 'https://example.com/login',
        ),
        'confirmed',
      );

      // 200 包含错误词判定为失败（即使有少量混淆词）
      expect(
        WebFormCredentialService.evaluateSuccess(
          statusCode: 200,
          body: '{"code": 401, "msg": "密码错误，请重新输入"}',
          headers: {},
          originalUrl: 'https://example.com/login',
        ),
        isNull,
      );
    });

    test('scan 基于 MockClient 模拟探测并成功检出弱口令', () async {
      final mockClient = MockClient((request) async {
        if (request.method == 'GET' && request.url.path == '/login') {
          return http.Response(
            '''
<html>
<body>
  <form action="/login" method="POST">
    <input type="text" name="username">
    <input type="password" name="password">
  </form>
</body>
</html>
''',
            200,
          );
        }
        if (request.method == 'POST' && request.url.path == '/login') {
          // 模拟当传入 admin / 123456 时重定向成功
          if (request.body.contains('username=admin') && request.body.contains('password=123456')) {
            return http.Response('', 302, headers: {'location': '/dashboard'});
          }
          return http.Response('{"error": "密码错误"}', 200);
        }
        return http.Response('Not Found', 404);
      });

      final findings = await WebFormCredentialService.scan(
        candidateUrls: ['https://example.com/login'],
        httpClient: mockClient,
      );

      expect(findings, isNotEmpty);
      expect(findings.first.username, 'admin');
      expect(findings.first.password, '123456');
      expect(findings.first.confidence, 'confirmed');
    });
  });
}



