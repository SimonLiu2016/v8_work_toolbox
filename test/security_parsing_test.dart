/// 安全工具箱解析函数的纯文本回归测试。
///
/// 这些解析全部吃的是外部工具的真实输出（nmap XML、nuclei JSONL、NVD/KEV
/// JSON、MAC 前缀、版本号），格式一旦漂移就静默返回空——所以用真实样本钉住。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/models/security_enums.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/models/security_models.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/services/lan_recon_services.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/services/script_generator_services.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/services/threat_intel_services.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/services/report_services.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/services/vuln_scan_services.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/services/web_recon_services.dart';

void main() {
  group('ifconfig 解析', () {
    test('提取活跃接口与 CIDR，跳过 lo0', () {
      const text = '''
lo0: flags=8049<UP,LOOPBACK,RUNNING,MULTICAST> mtu 33152
	inet 127.0.0.1 netmask 0xff000000
en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
	inet 192.168.1.23 netmask 0xffffff00 broadcast 192.168.1.255
en8: flags=8963<UP,BROADCAST,SMART,RUNNING,PROMISC,SIMPLEX,MULTICAST> mtu 1514
	inet 10.0.0.5 netmask 0xffff0000
utun3: flags=8051<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1500
	inet 10.8.0.2 --> 10.8.0.2 netmask 0xffffffff
''';
      final list = NetworkInterfaceDetector.parseIfconfig(text);
      // utun3 是 VPN 隧道，有 IPv4 且 UP——按 spec「所有活跃接口」应当出现。
      expect(list.map((i) => i.name), ['en0', 'en8', 'utun3']);
      expect(list.first.ipv4, '192.168.1.23');
      // hex netmask → /24
      expect(list.first.cidr, '192.168.1.23/24');
      // en8(10.0.0.5/16) 之后是 utun3(10.8.0.2/32)。
      expect(list[1].cidr, '10.0.0.5/16');
      expect(list.last.cidr, '10.8.0.2/32');
    });

    test('netmask 点分十进制也认', () {
      const text =
          'en0: flags=8863<UP,BROADCAST> mtu 1500\n	inet 10.1.2.3 netmask 255.255.255.0';
      final list = NetworkInterfaceDetector.parseIfconfig(text);
      expect(list.single.cidr, '10.1.2.3/24');
    });

    test('inet 已带 /prefix 时不再推算', () {
      const text =
          'en0: flags=8863<UP,BROADCAST> mtu 1500\n	inet 192.168.10.7/26 netmask 0xffffff00';
      final list = NetworkInterfaceDetector.parseIfconfig(text);
      expect(list.single.cidr, '192.168.10.7/26');
    });

    test('netmask 换算', () {
      expect(NetworkInterfaceDetector.prefixFromNetmask('0xffffff00'), 24);
      expect(NetworkInterfaceDetector.prefixFromNetmask('255.255.0.0'), 16);
      expect(NetworkInterfaceDetector.prefixFromNetmask('255.255.255.255'), 32);
      expect(NetworkInterfaceDetector.prefixFromNetmask('garbage'), isNull);
    });
  });

  group('arp-scan 解析', () {
    test('IP/MAC/Vendor 三列', () {
      const text = '''
Interface: en0, datalink type: EN10MB (Ethernet)
Starting arp-scan 1.10.0
192.168.1.1	00:11:22:33:44:55	TP-LINK TECHNOLOGIES CO.,LTD.
192.168.1.105	ab:cd:ef:01:02:03	Apple, Inc.

3 packets received, 3 packets sent
''';
      final hosts = ArpScanService.parseArpScan(text);
      expect(hosts.length, 2);
      expect(hosts[0].ip, '192.168.1.1');
      expect(hosts[0].mac, '00:11:22:33:44:55');
      expect(hosts[0].vendor, 'TP-LINK TECHNOLOGIES CO.,LTD.');
      expect(hosts[1].vendor, 'Apple, Inc.');
    });

    test('厂商为空时不塞空串', () {
      final hosts = ArpScanService.parseArpScan(
        '192.168.1.9	aa:bb:cc:dd:ee:ff',
      );
      expect(hosts.single.vendor, isNull);
    });
  });

  group('系统 ARP 缓存与 CIDR 工具', () {
    test('CIDR 展开为 IP 列表', () {
      final ips24 = NetworkInterfaceDetector.expandCidrToIps('192.168.1.0/24');
      expect(ips24.length, 254);
      expect(ips24.first, '192.168.1.1');
      expect(ips24.last, '192.168.1.254');

      final single = NetworkInterfaceDetector.expandCidrToIps('192.168.1.50');
      expect(single, ['192.168.1.50']);
    });

    test('IP CIDR 归属判定', () {
      expect(NetworkInterfaceDetector.isIpInCidr('192.168.1.93', '192.168.1.0/24'), isTrue);
      expect(NetworkInterfaceDetector.isIpInCidr('192.168.1.1', '192.168.1.0/24'), isTrue);
      expect(NetworkInterfaceDetector.isIpInCidr('10.253.1.1', '192.168.1.0/24'), isFalse);
      expect(NetworkInterfaceDetector.isIpInCidr('192.168.2.1', '192.168.1.0/24'), isFalse);
    });

    test('解析系统 arp -a 真实输出并提取硬件与 OUI 厂商', () {
      const arpOutput = '''
? (192.168.1.0) at ff:ff:ff:ff:ff:ff on en0 ifscope [ethernet]
? (192.168.1.1) at e8:12:2d:5f:22:f7 on en0 ifscope [ethernet]
? (192.168.1.2) at (incomplete) on en0 ifscope [ethernet]
? (192.168.1.77) at 2a:b6:70:b1:5c:76 on en0 ifscope [ethernet]
? (192.168.1.93) at f2:c2:f6:2b:77:3c on en0 ifscope permanent [ethernet]
? (192.168.1.225) at a8:a0:92:cb:73:9f on en0 ifscope [ethernet]
? (192.168.1.255) at ff:ff:ff:ff:ff:ff on en0 ifscope [ethernet]
mdns.mcast.net (224.0.0.251) at 1:0:5e:0:0:fb on en0 ifscope permanent [ethernet]
? (10.0.0.1) at 00:11:22:33:44:55 on en8 [ethernet]
''';

      final hosts = ArpScanService.parseSystemArpTable(
        arpOutput,
        cidr: '192.168.1.0/24',
      );

      // 应过滤 incomplete, 广播, 组播以及 10.0.0.1 (跨网段)
      expect(hosts.length, 4);
      final ipMap = {for (final h in hosts) h.ip: h};

      expect(ipMap.containsKey('192.168.1.1'), isTrue);
      expect(ipMap['192.168.1.1']!.mac, 'e8:12:2d:5f:22:f7');
      expect(ipMap['192.168.1.1']!.vendor, 'TP-Link');

      expect(ipMap.containsKey('192.168.1.77'), isTrue);
      expect(ipMap['192.168.1.77']!.mac, '2a:b6:70:b1:5c:76');
      expect(ipMap['192.168.1.77']!.vendor, 'Apple');

      expect(ipMap.containsKey('192.168.1.93'), isTrue);
      expect(ipMap['192.168.1.93']!.mac, 'f2:c2:f6:2b:77:3c');
      expect(ipMap['192.168.1.93']!.vendor, 'Apple');

      expect(ipMap.containsKey('192.168.1.225'), isTrue);
      expect(ipMap['192.168.1.225']!.mac, 'a8:a0:92:cb:73:9f');
      expect(ipMap['192.168.1.225']!.vendor, 'Huawei');
    });

    test('ArpScanService.scan 优先使用 UDP 激发与系统 ARP 缓存提取', () async {
      var proberCalled = false;
      const arpOutput = '''
? (192.168.1.1) at e8:12:2d:5f:22:f7 on en0 ifscope [ethernet]
? (192.168.1.93) at f2:c2:f6:2b:77:3c on en0 ifscope permanent [ethernet]
''';

      final logs = <String>[];
      final hosts = await ArpScanService.scan(
        cidr: '192.168.1.0/24',
        prober: (targets) async {
          proberCalled = true;
          expect(targets.contains('192.168.1.1'), isTrue);
        },
        runner: (exe, args, {timeout = const Duration(seconds: 5)}) async {
          if (exe == 'arp') return arpOutput;
          if (exe == 'ifconfig') {
            return 'en0: flags=8863<UP,BROADCAST> mtu 1500\n\tinet 192.168.1.93 netmask 0xffffff00';
          }
          throw StateError('不应调用 $exe');
        },
        onLog: logs.add,
      );

      expect(proberCalled, isTrue);
      expect(hosts.length, 2);
      expect(hosts.map((h) => h.ip), containsAll(['192.168.1.1', '192.168.1.93']));
      expect(logs.any((l) => l.contains('系统 ARP 表发现')), isTrue);
    });
  });

  group('nmap XML 解析', () {
    const xml = '''<?xml version="1.0"?>
<nmaprun>
  <host>
    <status state="up"/>
    <address addr="192.168.1.105" addrtype="ipv4"/>
    <address addr="A4:83:E7:11:22:33" addrtype="mac" vendor="Apple, Inc."/>
    <hostnames><hostname name="macbook.local" type="PTR"/></hostnames>
    <ports>
      <port protocol="tcp" portid="22"><state state="open"/><service name="ssh" product="OpenSSH" version="9.6"/></port>
      <port protocol="tcp" portid="62000"><state state="closed"/><service name="iphone-sync"/></port>
    </ports>
    <os><osmatch name="macOS 14.5" accuracy="100"/></os>
  </host>
  <host>
    <status state="down"/>
    <address addr="192.168.1.200" addrtype="ipv4"/>
  </host>
</nmaprun>''';

    test('主机、端口、OS、厂商都对', () {
      final hosts = NmapService.parseNmapXml(xml);
      expect(hosts.length, 2);
      final mac = hosts.first;
      expect(mac.ip, '192.168.1.105');
      expect(mac.mac, 'A4:83:E7:11:22:33');
      expect(mac.vendor, 'Apple, Inc.');
      expect(mac.hostname, 'macbook.local');
      expect(mac.osName, 'macOS 14.5');
      expect(mac.ports.length, 2);
      expect(mac.ports.first.service, 'ssh');
      expect(mac.ports.first.version, '9.6');
      expect(mac.isUp, isTrue);
      expect(hosts.last.isUp, isFalse);
    });

    test('端口摘要', () {
      final hosts = NmapService.parseNmapXml(xml);
      final summary = NmapService.portSummary(hosts.first.ports);
      expect(summary, contains('ssh'));
      expect(summary, contains('iphone-sync'));
    });

    test('XML 被截断时返回空而不是抛', () {
      expect(NmapService.parseNmapXml('<?xml version="1.0"?><nmaprun><host>'),
          isEmpty);
    });

    test('高危端口 → high 风险等级', () {
      final host = ScannedHost(
        ip: '10.0.0.2',
        ports: const [ScannedPort(port: 445, protocol: 'tcp', service: 'smb')],
      );
      expect(riskLevelForHost(host), Severity.high.key);
    });

    test('只有无害端口 → low', () {
      final host = ScannedHost(
        ip: '10.0.0.3',
        ports: const [ScannedPort(port: 8080, protocol: 'tcp', service: 'http')],
      );
      expect(riskLevelForHost(host), Severity.low.key);
    });
  });

  group('nmap -sn 主机发现 XML', () {
    test('只取 IP/MAC/厂商/主机名', () {
      final hosts = ArpScanService.parseNmapHostDiscovery('''
<nmaprun><host>
<address addr="192.168.1.1" addrtype="ipv4"/>
<address addr="00:11:22:33:44:55" addrtype="mac" vendor="TP-LINK"/>
<hostnames><hostname name="router.lan"/></hostnames>
</host></nmaprun>''');
      expect(hosts.single.ip, '192.168.1.1');
      expect(hosts.single.vendor, 'TP-LINK');
      expect(hosts.single.hostname, 'router.lan');
    });
  });

  group('JSONL 解析', () {
    test('跳过非 JSON 行与不完整行', () {
      final rows = parseJsonLines(
        'not json\n{"a":1}\n{"broken":\n  \n{"b":2}',
      );
      expect(rows.length, 2);
      expect(rows.first['a'], 1);
      expect(rows.last['b'], 2);
    });
  });

  group('httpx 解析', () {
    test('状态码 / 标题 / 技术栈', () {
      final results = HttpxResult.parseJson('''
{"url":"https://a.example.com","status_code":200,"title":"Home","webserver":"nginx","tech":["Nginx","PHP"],"host":"a.example.com","a":["1.2.3.4"]}
{"url":"https://b.example.com","status_code":403,"title":"Forbidden"}
''');
      expect(results.length, 2);
      expect(results.first.statusCode, 200);
      expect(results.first.tech, ['Nginx', 'PHP']);
      expect(results.first.ip, '1.2.3.4');
      expect(results.last.statusCode, 403);
      final meta = results.first.toMetadata();
      expect(meta['tech_stack'], ['Nginx', 'PHP']);
      expect(meta['status_code'], 200);
    });
  });

  group('gau / ffuf / katana 解析', () {
    test('gau 只收 http(s) 行', () {
      final urls = GauResult.parse(
        'https://a.example.com/x\nhttp://b.example.com/y\nnot-a-url\n',
      );
      expect(urls.map((u) => u.url), [
        'https://a.example.com/x',
        'http://b.example.com/y',
      ]);
    });

    test('ffuf JSON 行', () {
      final findings = FfufFinding.parseJson(
        '{"url":"https://a/admin","status":200,"length":1234}',
      );
      expect(findings.single.status, 200);
      expect(findings.single.length, 1234);
    });

    test('katana 端点从 request.endpoint 取', () {
      final results = KatanaResult.parseJson(
        '{"request":{"endpoint":"/api/v1/users"},"source":"crawl"}',
      );
      expect(results.single.url, '/api/v1/users');
    });
  });

  group('nuclei 解析', () {
    test('severity / CVE / CVSS 从 classification 取', () {
      final finding = NucleiFinding.parseRow({
        'template-id': 'CVE-2024-1234',
        'matched-at': 'https://a.example.com',
        'info': {
          'name': 'Apache RCE',
          'severity': 'CRITICAL',
          'description': 'desc',
          'classification': {
            'cve-id': ['CVE-2024-1234'],
            'cvss-score': [9.8],
          },
        },
      });
      expect(finding, isNotNull);
      expect(finding!.severity, 'critical');
      expect(finding.cveId, 'CVE-2024-1234');
      expect(finding.cvssScore, 9.8);
      expect(finding.severityLevel, Severity.critical);
    });

    test('CVE 缺失时从 tags 里抠', () {
      final finding = NucleiFinding.parseRow({
        'template-id': 'x',
        'info': {'name': 'n', 'severity': 'high', 'tags': 'cve,rce,cve-2023-9999'},
      });
      expect(finding!.cveId, 'CVE-2023-9999');
    });

    test('没有 info 块返回 null', () {
      expect(NucleiFinding.parseRow({'template-id': 'x'}), isNull);
    });

    test('模板分类清单覆盖 spec 六类', () {
      expect(NucleiCategory.values.map((c) => c.key), [
        'cves',
        'exposures',
        'misconfiguration',
        'default-logins',
        'network',
        'technologies',
      ]);
    });
  });

  group('NVD / KEV 解析', () {
    test('NVD 取 CVSS 3.x 与英文描述', () {
      final cves = ThreatIntelFeedService.parseNvd('''
{"vulnerabilities":[{"cve":{"id":"CVE-2024-0001","published":"2026-01-01T00:00:00.000",
"descriptions":[{"lang":"en","value":"Foo before 1.2 allows RCE"}],
"metrics":{"cvssMetricV31":[{"cvssData":{"baseScore":9.8,"baseSeverity":"CRITICAL"}}]}}}]}
''');
      expect(cves.single.id, 'CVE-2024-0001');
      expect(cves.single.cvssScore, 9.8);
      expect(cves.single.severity, 'critical');
      expect(cves.single.published?.year, 2026);
    });

    test('KEV 返回 CVE 集合', () {
      final ids = ThreatIntelFeedService.parseKev('''
{"vulnerabilities":[{"cveID":"CVE-2021-44228"},{"cveID":"CVE-2023-4966"}]}
''');
      expect(ids, {'CVE-2021-44228', 'CVE-2023-4966'});
    });

    test('KEV 源损坏时返回空集合', () {
      expect(ThreatIntelFeedService.parseKev('not json'), isEmpty);
    });
  });

  group('资产交叉比对', () {
    PentestAsset asset(String address, String metaJson) => PentestAsset(
      id: address,
      sessionId: 's',
      type: AssetType.host,
      address: address,
      metadataJson: metaJson,
      riskLevel: 'unknown',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    ThreatIntelEntry cve(String id, String desc) => ThreatIntelEntry(
      cveId: id,
      title: desc,
      cvssScore: 9.0,
      severity: 'critical',
      description: desc,
      isKev: false,
      syncedAt: DateTime.now(),
    );

    test('产品名 + 版本命中', () {
      final matches = IntelCrossMatcher.match(
        [
          asset('10.0.0.1', '{"os":"Apache httpd 2.4.51"}'),
          asset('10.0.0.2', '{"os":"Windows 10"}'),
        ],
        [cve('CVE-2024-1111', 'Apache httpd 2.4.x before 2.4.58 allows X')],
      );
      expect(matches.length, 1);
      expect(matches.single.assetAddress, '10.0.0.1');
      expect(matches.single.cveId, 'CVE-2024-1111');
    });

    test('抽不出关键词的描述宁可漏报', () {
      final matches = IntelCrossMatcher.match(
        [asset('10.0.0.1', '{}')],
        [cve('CVE-2024-2222', '一个没有版本号的中文描述')],
      );
      expect(matches, isEmpty);
    });
  });

  group('脚本模板库', () {
    test('内置模板 ≥ 10 个且覆盖六类场景', () {
      final categories = BuiltInTemplates.all.map((t) => t.category).toSet();
      expect(BuiltInTemplates.all.length, greaterThanOrEqualTo(10));
      expect(
        categories,
        containsAll(['反弹 Shell', '端口扫描', '口令爆破', 'Payload 生成']),
      );
    });

    test('模板占位符标注齐全', () {
      final reverseShell = BuiltInTemplates.all.firstWhere(
        (t) => t.id == 'builtin-reverse-shell-py',
      );
      expect(reverseShell.placeholders, ['LHOST', 'LPORT']);
      expect(reverseShell.body, contains('{{LHOST}}'));
      expect(reverseShell.body, contains('{{LPORT}}'));
    });

    test('JSON 往返不丢字段', () {
      final template = BuiltInTemplates.all.first;
      final encoded = jsonEncode(template.toJson());
      final restored = ScriptTemplate.fromJson(
          jsonDecode(encoded) as Map<String, dynamic>)!;
      expect(restored.id, template.id);
      expect(restored.body, template.body);
      expect(restored.language, template.language);
      expect(restored.placeholders, template.placeholders);
      expect(restored.builtIn, template.builtIn);
    });

    test('抠代码块', () {
      expect(
        extractCodeBlock('前面\n```python\nprint(1)\n```\n后面'),
        'print(1)',
      );
      // 无围栏时退化为全文
      expect(extractCodeBlock('print(1)'), 'print(1)');
    });
  });

  group('报告工具', () {
    test('执行摘要与技术报告构建', () {
      final session = PentestSession(
        id: 's1',
        name: '内部靶场测试',
        type: 'intranet',
        scopeJson: '["192.168.1.0/24"]',
        status: 'active',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      final asset = PentestAsset(
        id: 'a1',
        sessionId: 's1',
        type: AssetType.host,
        address: '192.168.1.50',
        metadataJson: '{"os":"Linux"}',
        riskLevel: 'high',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      final f = PentestFinding(
        id: 'f1',
        sessionId: 's1',
        title: 'MS17-010 漏洞',
        severity: 'critical',
        cveId: 'CVE-2017-0144',
        cvssScore: 9.8,
        status: 'open',
        source: 'nuclei',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      final bundle = const ReportDataAggregator().aggregate(
        session: session,
        assets: [asset],
        findings: [f],
        timeline: const [],
      );

      final execMd = buildExecutiveMarkdownReport(
        bundle: bundle,
        executiveSummary: '本次测试发现 1 项严重安全风险。',
        remediation: '建议立即应用安全补丁。',
      );
      expect(execMd, contains('渗透测试报告（执行摘要）'));
      expect(execMd, contains('一、管理层摘要'));
      expect(execMd, contains('本次测试发现 1 项严重安全风险。'));
      expect(execMd, contains('三、优先整改建议'));

      final techMd = buildMarkdownReport(
        bundle: bundle,
        executiveSummary: '本次测试发现 1 项严重安全风险。',
        narrative: '通过永恒之蓝利用实现 RCE。',
        remediation: '建议立即应用安全补丁。',
      );
      expect(techMd, contains('渗透测试报告'));
      expect(techMd, contains('三、漏洞发现'));
      expect(techMd, contains('MS17-010 漏洞'));
      expect(techMd, contains('四、技术叙述'));
    });

    test('版本号取最大值 +1', () {
      final versions = [
        ReportVersionRecord(
          id: '1',
          sessionId: 's',
          version: 1,
          format: 'x',
          content: '',
          createdAt: DateTime(2026, 1, 1),
        ),
        ReportVersionRecord(
          id: '2',
          sessionId: 's',
          version: 3,
          format: 'x',
          content: '',
          createdAt: DateTime(2026, 1, 2),
        ),
      ];
      expect(nextVersion(versions), 4);
      expect(nextVersion(const []), 1);
    });

    test('超上限时保留最新的 10 个', () {
      final versions = [
        for (var i = 0; i < 12; i++)
          ReportVersionRecord(
            id: '$i',
            sessionId: 's',
            version: i,
            format: 'x',
            content: '',
            createdAt: DateTime(2026, 1, 1 + i),
          ),
      ];
      final prune = versionsToPrune(versions);
      expect(prune, ['0', '1']);
    });

    test('未超上限不删', () {
      final versions = [
        ReportVersionRecord(
          id: '1',
          sessionId: 's',
          version: 1,
          format: 'x',
          content: '',
          createdAt: DateTime(2026, 1, 1),
        ),
      ];
      expect(versionsToPrune(versions), isEmpty);
    });

    test('内容编码往返', () {
      final encoded = encodeReportContent(
        executiveSummary: 'summary',
        narrative: 'narr',
        remediation: 'fix',
      );
      final decoded = decodeReportContent(encoded);
      expect(decoded['executive_summary'], 'summary');
      expect(decoded['remediation'], 'fix');
    });

    test('损坏的内容不抛', () {
      expect(decodeReportContent('not json'), isEmpty);
    });
  });
}
