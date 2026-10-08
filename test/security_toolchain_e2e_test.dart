
/// 工具链端到端冒烟测试（spec 13.3 的自动化部分）。
///
/// 依赖真实 nmap，所以机器上没装时整个 group 跳过——CI 与没装 homebrew 的
/// 开发机都不该因此红。目标固定为 127.0.0.1：不需要特权，也不触网，
/// 但完整走过「解析路径 → 启动进程 → XML 解析 → 结构化输出」这条链路。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/services/lan_recon_services.dart';

void main() {
  final hasNmap = NmapService.isAvailable();

  group(
    '工具链端到端（需要真实 nmap）',
    () {
      test('接口识别返回本机网段', () async {
        final ifaces = await NetworkInterfaceDetector.detect();
        // 至少有 lo0 之外的接口（CI 容器可能只有 lo，故只断言不抛且返回列表）。
        expect(ifaces, isA<List<NetworkInterface>>());
        for (final i in ifaces) {
          expect(i.name.isNotEmpty, isTrue);
          expect(i.ipv4, matches(RegExp(r'^\d+\.\d+\.\d+\.\d+$')));
        }
      });

      test('nmap 扫描 127.0.0.1 并解析出结构化结果', () async {
        final hosts = await NmapService.scan(
          target: '127.0.0.1',
          mode: NmapScanMode.quick,
          withServiceVersion: false,
          withOsDetect: false,
        );
        expect(hosts, isNotEmpty);
        final host = hosts.firstWhere((h) => h.ip == '127.0.0.1');
        expect(host.isUp, isTrue);
        expect(host.ports, isA<List<ScannedPort>>());
        expect(riskLevelForHost(host), isA<String>());
      });
    },
    skip: hasNmap ? null : '本机未安装 nmap，跳过工具链端到端测试',
  );
}
