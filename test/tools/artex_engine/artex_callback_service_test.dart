import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/artex_engine/services/artex_callback_service.dart';

/// 本机真实 `ifconfig` 的关键片段（2026-10-12 实测）。
///
/// 覆盖：物理网卡 en0/en5、回环 lo0、TUN 虚拟网关 utun88、Docker 的 vmnet
/// 网桥 bridge100、AirDrop awdl0、热点 ap1、以及一个 DOWN 状态的 en4。
const String kSampleIfconfig = '''
lo0: flags=8049<UP,LOOPBACK,RUNNING,MULTICAST> mtu 16384
\tinet 127.0.0.1 netmask 0xff000000
gif0: flags=8010<POINTOPOINT,MULTICAST> mtu 1280
stf0: flags=0<> mtu 1280
en5: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
en4: flags=8963<BROADCAST,SMART,RUNNING,PROMISC,SIMPLEX> mtu 1500
en3: flags=8963<BROADCAST,SMART,RUNNING,PROMISC,SIMPLEX> mtu 1500
en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
\tinet 192.168.1.3 netmask 0xffffff00 broadcast 192.168.1.255
awdl0: flags=8843<UP,BROADCAST,RUNNING,MULTICAST> mtu 1500
llw0: flags=8843<UP,BROADCAST,RUNNING,MULTICAST> mtu 1500
utun0: flags=8051<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1500
utun88: flags=8051<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1500
\tinet 10.253.1.1 --> 10.253.1.1 netmask 0xffffffff
bridge0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
bridge100: flags=8a63<UP,BROADCAST,ALLMULTICAST,SIMPLEX,MULTICAST> mtu 1500
\tinet 192.168.64.1 netmask 0xffffff00 broadcast 192.168.64.255
vmenet0: flags=8963<UP,BROADCAST,SMART,RUNNING,PROMISC,SIMPLEX> mtu 1500
ap1: flags=8843<UP,BROADCAST,RUNNING,MULTICAST> mtu 1500
''';

const String kSampleIpAddr = '''
1: lo    inet 127.0.0.1/8 scope host lo\       valid_lft forever preferred_lft forever
2: eth0    inet 192.168.1.3/24 brd 192.168.1.255 scope global eth0\       valid_lft forever preferred_lft forever
3: tun0    inet 10.8.0.2/24 scope global tun0\       valid_lft forever preferred_lft forever
4: docker0    inet 172.17.0.1/16 brd 172.17.255.255 scope global docker0\       valid_lft forever preferred_lft forever
''';

void main() {
  group('parseIfconfig', () {
    test('只返回物理网卡，排除回环/隧道/网桥/热点', () {
      final list = ArtexCallbackService.parseIfconfig(kSampleIfconfig);
      // en0(192.168.1.3) 与 en5 在样本里没有 inet 行，en4/en3 不是 UP。
      expect(list, ['192.168.1.3']);
    });

    test('排除所有虚拟接口类型', () {
      expect(ArtexCallbackService.debugIsVirtual('lo0'), isTrue);
      expect(ArtexCallbackService.debugIsVirtual('utun88'), isTrue);
      expect(ArtexCallbackService.debugIsVirtual('bridge100'), isTrue);
      expect(ArtexCallbackService.debugIsVirtual('vmenet0'), isTrue);
      expect(ArtexCallbackService.debugIsVirtual('awdl0'), isTrue);
      expect(ArtexCallbackService.debugIsVirtual('llw0'), isTrue);
      expect(ArtexCallbackService.debugIsVirtual('gif0'), isTrue);
      expect(ArtexCallbackService.debugIsVirtual('stf0'), isTrue);
      expect(ArtexCallbackService.debugIsVirtual('ap1'), isTrue);
      expect(ArtexCallbackService.debugIsVirtual('en0'), isFalse);
      expect(ArtexCallbackService.debugIsVirtual('en5'), isFalse);
      expect(ArtexCallbackService.debugIsVirtual('eth0'), isFalse);
    });

    test('不完整接口块（UP 但无 inet 行）被跳过', () {
      const text = '''
en5: flags=8863<UP,BROADCAST,RUNNING> mtu 1500
en0: flags=8863<UP,BROADCAST,RUNNING> mtu 1500
\tinet 10.1.2.3 netmask 0xffffff00
''';
      expect(ArtexCallbackService.parseIfconfig(text), ['10.1.2.3']);
    });

    test('多物理网卡按名字排序，en0 优先于 en5', () {
      const text = '''
en5: flags=8863<UP,BROADCAST,RUNNING> mtu 1500
\tinet 10.9.9.9 netmask 0xffffff00
en0: flags=8863<UP,BROADCAST,RUNNING> mtu 1500
\tinet 192.168.1.3 netmask 0xffffff00
''';
      expect(ArtexCallbackService.parseIfconfig(text), [
        '192.168.1.3',
        '10.9.9.9',
      ]);
    });

    test('非 UP 的物理网卡被跳过', () {
      const text = '''
en4: flags=8963<BROADCAST,SMART,RUNNING> mtu 1500
\tinet 10.4.4.4 netmask 0xffffff00
''';
      expect(ArtexCallbackService.parseIfconfig(text), isEmpty);
    });

    test('空文本返回空列表', () {
      expect(ArtexCallbackService.parseIfconfig(''), isEmpty);
    });
  });

  group('parseIpAddr', () {
    test('排除 lo 与 tun/docker 虚拟接口', () {
      final list = ArtexCallbackService.parseIpAddr(kSampleIpAddr);
      expect(list, ['192.168.1.3']);
    });
  });

  group('detectCandidates', () {
    test('注入的 runner 抛异常时返回空列表而不是崩溃', () async {
      final list = await ArtexCallbackService.detectCandidates(
        runner: (exe, args) async => throw Exception('ifconfig not found'),
      );
      expect(list, isEmpty);
    });

    test('ifconfig 无物理网卡时回退 ip -o -4 addr', () async {
      final list = await ArtexCallbackService.detectCandidates(
        runner: (exe, args) async {
          if (exe == 'ifconfig') return kSampleIfconfig.replaceAll('en0', 'enX');
          if (exe == 'ip') return kSampleIpAddr;
          return '';
        },
      );
      expect(list, ['192.168.1.3']);
    });
  });

  group('detectSingle', () {
    test('有候选时返回排序第一个', () async {
      final single = await ArtexCallbackService.detectSingle(
        runner: (exe, args) async => kSampleIfconfig,
      );
      expect(single, '192.168.1.3');
    });

    test('无候选时返回 null', () async {
      final single = await ArtexCallbackService.detectSingle(
        runner: (exe, args) async => '',
      );
      expect(single, isNull);
    });
  });
}
