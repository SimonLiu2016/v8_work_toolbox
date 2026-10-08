/// 局域网侦察：接口识别、ARP 发现、nmap 深度扫描与 XML 解析。
library;

import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

import '../models/security_enums.dart';
import 'security_process_runner.dart';

/// 一个活跃网络接口及其 CIDR。
class NetworkInterface {
  final String name;
  final String ipv4;

  /// 如 `192.168.1.0/24`。
  final String cidr;
  final String? netmask;
  final bool isUp;

  const NetworkInterface({
    required this.name,
    required this.ipv4,
    required this.cidr,
    this.netmask,
    this.isUp = true,
  });

  String get label {
    final slash = cidr.split('/');
    return '$name · ${slash.length == 2 ? slash[1] : cidr}';
  }
}

/// 从 `ifconfig` 输出里解析活跃接口。
///
/// 只保留带 IPv4、状态 UP、且非 loopback 的接口——`lo0` 的 127.0.0.1 对渗透没意义，
/// 但它每次都出现在输出里，不过滤就会占据默认选中项。
abstract final class NetworkInterfaceDetector {
  static Future<List<NetworkInterface>> detect({
    Future<String> Function(String, List<String>, {Duration timeout})? runner,
  }) async {
    final run =
        runner ??
        (exe, args, {Duration timeout = const Duration(seconds: 5)}) async {
          final r = await runCaptured(exe, args, timeout: timeout);
          return r.stdout;
        };
    // macOS 优先 ifconfig；失败再试 ip route（Linux 风格，用户可能改了 PATH）。
    var out = await run('ifconfig', const [], timeout: const Duration(seconds: 5));
    var list = _parseIfconfig(out);
    if (list.isEmpty) {
      out = await run('ip', [
        '-o',
        '-4',
        'addr',
        'show',
      ], timeout: const Duration(seconds: 5));
      list = _parseIpAddr(out);
    }
    return list;
  }

  /// 从 ifconfig 文本解析（测试直接喂文本）。
  static List<NetworkInterface> parseIfconfig(String text) => _parseIfconfig(text);

  static List<NetworkInterface> _parseIfconfig(String text) {
    final result = <NetworkInterface>[];
    // 接口块以行首非空白字符开头（"en0: flags=8863<UP,...> mtu 1500"），
    // 缩进行（\t inet ...）归属当前块。
    final blocks = <String>[];
    for (final line in text.split('\n')) {
      if (line.isEmpty) continue;
      if (line.startsWith(' ') || line.startsWith('\t')) {
        if (blocks.isNotEmpty) {
          blocks[blocks.length - 1] = '${blocks.last}\n$line';
        }
      } else {
        blocks.add(line);
      }
    }
    for (final block in blocks) {
      if (block.isEmpty) continue;
      final header = block.split('\n').first;
      final nameMatch = RegExp(r'^([A-Za-z0-9_]+):').firstMatch(header);
      if (nameMatch == null) continue;
      final name = nameMatch.group(1)!;
      if (name == 'lo0') continue;
      if (!header.contains('<UP') && !header.contains('UP,')) continue;

      final inetMatch = RegExp(r'inet (\d+\.\d+\.\d+\.\d+)').firstMatch(block);
      if (inetMatch == null) continue;
      final ip = inetMatch.group(1)!;

      String? netmask;
      final maskMatch = RegExp(
        r'netmask (0x[0-9a-fA-F]+|\d+\.\d+\.\d+\.\d+)',
      ).firstMatch(block);
      final prefixMatch = RegExp(r'inet \d+\.\d+\.\d+\.\d+/(\d+)').firstMatch(block);
      if (maskMatch != null) {
        netmask = maskMatch.group(1)!;
      }
      int? prefix;
      if (prefixMatch != null) {
        prefix = int.tryParse(prefixMatch.group(1)!);
      } else if (netmask != null) {
        prefix = prefixFromNetmask(netmask);
      }
      result.add(
        NetworkInterface(
          name: name,
          ipv4: ip,
          cidr: prefix == null ? ip : '$ip/$prefix',
          netmask: netmask,
        ),
      );
    }
    return result;
  }

  static List<NetworkInterface> _parseIpAddr(String text) {
    final result = <NetworkInterface>[];
    for (final line in text.split('\n')) {
      final match = RegExp(
        r'^\d+:\s+([A-Za-z0-9_]+)\s+inet\s+(\d+\.\d+\.\d+\.\d+)/(\d+)',
      ).firstMatch(line);
      if (match == null) continue;
      final name = match.group(1)!;
      if (name == 'lo') continue;
      final ip = match.group(2)!;
      final prefix = match.group(3)!;
      result.add(NetworkInterface(name: name, ipv4: ip, cidr: '$ip/$prefix'));
    }
    return result;
  }

  /// `0xffffff00` 或 `255.255.255.0` → 24。
  static int? prefixFromNetmask(String netmask) {
    if (netmask.startsWith('0x')) {
      final value = int.tryParse(netmask.substring(2), radix: 16);
      if (value == null) return null;
      var bits = 0;
      for (var i = 31; i >= 0; i--) {
        if ((value >> i) & 1 == 1) bits++;
      }
      return bits;
    }
    final octets = netmask.split('.');
    if (octets.length != 4) return null;
    var bits = 0;
    for (final o in octets) {
      final v = int.tryParse(o);
      if (v == null) return null;
      bits += _popcount(v);
    }
    return bits;
  }

  static int _popcount(int v) {
    var n = v;
    var count = 0;
    while (n > 0) {
      count += n & 1;
      n >>= 1;
    }
    return count;
  }

  /// 将 CIDR 展开为目标主机 IP 列表（默认上限 512 个，避免超大网段泛洪）。
  static List<String> expandCidrToIps(String cidr, {int maxHosts = 512}) {
    final trimmed = cidr.trim();
    if (!trimmed.contains('/')) {
      if (RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(trimmed)) {
        return [trimmed];
      }
      return const [];
    }
    final parts = trimmed.split('/');
    final ipStr = parts[0];
    final prefix = int.tryParse(parts[1]) ?? 24;
    if (prefix < 16 || prefix > 32) return const [];

    final ipInt = _ipToInt(ipStr);
    if (ipInt == null) return const [];

    final mask = prefix == 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
    final network = ipInt & mask;
    final broadcast = network | (~mask & 0xFFFFFFFF);

    final result = <String>[];
    if (prefix >= 31) {
      for (var i = network; i <= broadcast && result.length < maxHosts; i++) {
        result.add(_intToIp(i));
      }
    } else {
      for (var i = network + 1; i < broadcast && result.length < maxHosts; i++) {
        result.add(_intToIp(i));
      }
    }
    return result;
  }

  /// 检查某 IP 是否处于指定 CIDR 网段内。
  static bool isIpInCidr(String ip, String cidr) {
    final trimmed = cidr.trim();
    if (!trimmed.contains('/')) return ip == trimmed;
    final parts = trimmed.split('/');
    final prefix = int.tryParse(parts[1]) ?? 32;
    final ipInt = _ipToInt(ip);
    final cidrIpInt = _ipToInt(parts[0]);
    if (ipInt == null || cidrIpInt == null) return false;
    final mask = prefix == 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
    return (ipInt & mask) == (cidrIpInt & mask);
  }

  static int? _ipToInt(String ip) {
    final octets = ip.split('.');
    if (octets.length != 4) return null;
    var result = 0;
    for (final o in octets) {
      final v = int.tryParse(o);
      if (v == null || v < 0 || v > 255) return null;
      result = (result << 8) | v;
    }
    return result & 0xFFFFFFFF;
  }

  static String _intToIp(int value) {
    final v = value & 0xFFFFFFFF;
    return '${(v >> 24) & 0xFF}.${(v >> 16) & 0xFF}.${(v >> 8) & 0xFF}.${v & 0xFF}';
  }
}

/// ARP 发现到的一台主机。
class ArpHost {
  final String ip;
  final String? mac;

  /// OUI 反查的厂商名。
  final String? vendor;

  /// 主机名（nmap -sn 的 rDNS 结果）。
  final String? hostname;

  const ArpHost({required this.ip, this.mac, this.vendor, this.hostname});
}

/// ARP 主机发现。
///
/// 优先免 Root 的「UDP 探针激发 + 系统内核 ARP 缓存（arp -a）读取」，
/// 穿透主机防火墙且无需特权，秒级发现全部存活终端并提取真实 MAC/厂商；
/// 失败或特殊场景下回落至 nmap 多协议存活 Ping 及外部 arp-scan。
abstract final class ArpScanService {
  /// 并发向目标 IP 扇出轻量无害 UDP 探针以激发内核发送以太网 ARP Request。
  static Future<void> triggerUdpProbe(
    List<String> targets, {
    List<int> ports = const [137, 5353, 80],
    Duration waitDuration = const Duration(milliseconds: 600),
    Future<void> Function(List<String> targets)? customProber,
  }) async {
    if (targets.isEmpty) return;
    if (customProber != null) {
      await customProber(targets);
      return;
    }
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final payload = const <int>[0];
      for (final ip in targets) {
        try {
          final addr = InternetAddress(ip);
          for (final port in ports) {
            socket.send(payload, addr, port);
          }
        } catch (_) {}
      }
      await Future.delayed(waitDuration);
      socket.close();
    } catch (_) {}
  }

  /// 根据 MAC 地址前缀匹配常见硬件厂商（OUI）。
  static String? lookupVendor(String mac) {
    final clean = mac.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
    if (clean.length < 6) return null;
    final prefix = clean.substring(0, 6);

    const vendorMap = <String, String>{
      // Apple
      '0017f2': 'Apple', '001cb3': 'Apple', '001e52': 'Apple', '002312': 'Apple',
      '002500': 'Apple', '002608': 'Apple', '00264a': 'Apple', '0026b0': 'Apple',
      '3c0754': 'Apple', '3c15c2': 'Apple', '3c2eff': 'Apple', '406c8f': 'Apple',
      '70ee50': 'Apple', '88665a': 'Apple', 'a483e7': 'Apple', 'bcd074': 'Apple',
      'f01898': 'Apple', 'f4f15a': 'Apple', 'f2c2f6': 'Apple', '2ab670': 'Apple',
      'b6d48c': 'Apple', 'b2d718': 'Apple', 'acde48': 'Apple',
      // TP-Link
      'e8122d': 'TP-Link', '50d4f7': 'TP-Link', '000aeb': 'TP-Link', '001478': 'TP-Link',
      '0019e0': 'TP-Link', '002127': 'TP-Link', '0023cd': 'TP-Link', '002586': 'TP-Link',
      '147590': 'TP-Link', '14cc20': 'TP-Link', '18a6f7': 'TP-Link', '20dce6': 'TP-Link',
      '30b5c2': 'TP-Link', '388345': 'TP-Link', '50c7bf': 'TP-Link', '54e6fc': 'TP-Link',
      '6032b1': 'TP-Link', '647002': 'TP-Link', '6c5ab0': 'TP-Link', '70af6a': 'TP-Link',
      '7405a5': 'TP-Link', '74ea3a': 'TP-Link', '784476': 'TP-Link', '808917': 'TP-Link',
      '8416f9': 'TP-Link', '8c210a': 'TP-Link', '9094e4': 'TP-Link', '984827': 'TP-Link',
      'a0f3c1': 'TP-Link', 'ac84c6': 'TP-Link', 'b0487a': 'TP-Link', 'b09575': 'TP-Link',
      'c025e9': 'TP-Link', 'c04a00': 'TP-Link', 'c46e1f': 'TP-Link', 'd807b6': 'TP-Link',
      'd84732': 'TP-Link', 'dcfe18': 'TP-Link', 'e4c32a': 'TP-Link', 'ec086b': 'TP-Link',
      'ec172f': 'TP-Link', 'f483cd': 'TP-Link', 'f4ec38': 'TP-Link', 'f81a67': 'TP-Link',
      // Huawei / Honor
      'a8a092': 'Huawei', '001882': 'Huawei', '001e10': 'Huawei', '002568': 'Huawei',
      '00259e': 'Huawei', '00e0fc': 'Huawei', '0425c5': 'Huawei', '047970': 'Huawei',
      '04c06f': 'Huawei', '0819a6': 'Huawei', '086361': 'Huawei', '0c37dc': 'Huawei',
      '0c45ba': 'Huawei', '0c96bf': 'Huawei', '101b54': 'Huawei', '104400': 'Huawei',
      '104780': 'Huawei', '14579f': 'Huawei', '14d11f': 'Huawei', '18c58a': 'Huawei',
      '18ded7': 'Huawei', '1c1d67': 'Huawei', '1c8e5c': 'Huawei', '2008ed': 'Huawei',
      '200bc7': 'Huawei', '202bc1': 'Huawei', '203db2': 'Huawei', '205476': 'Huawei',
      '244427': 'Huawei', '246968': 'Huawei', '247f3c': 'Huawei', '283152': 'Huawei',
      '2841c6': 'Huawei', '286ed4': 'Huawei', '2c97b1': 'Huawei', '308730': 'Huawei',
      '342eb4': 'Huawei', '34cdbe': 'Huawei', '38f889': 'Huawei', '3c4711': 'Huawei',
      '404d8e': 'Huawei', '4455b1': 'Huawei', '4482e5': 'Huawei', '48435a': 'Huawei',
      '4846fb': 'Huawei', '487b6b': 'Huawei', '4c5499': 'Huawei', '4c8b30': 'Huawei',
      '50016b': 'Huawei', '5004b8': 'Huawei', '5425ea': 'Huawei', '548998': 'Huawei',
      '54b121': 'Huawei', '582af7': 'Huawei', '5c546d': 'Huawei', '600810': 'Huawei',
      '60de44': 'Huawei', '688f84': 'Huawei', '68a03e': 'Huawei', '6cb749': 'Huawei',
      '7054f5': 'Huawei', '70723c': 'Huawei', '707be8': 'Huawei', '74882a': 'Huawei',
      '781d4a': 'Huawei', '786a89': 'Huawei', '78d752': 'Huawei', '7c1cf1': 'Huawei',
      // Xiaomi
      '04cf8c': 'Xiaomi', '0c9838': 'Xiaomi', '102ab3': 'Xiaomi', '14f65a': 'Xiaomi',
      '185936': 'Xiaomi', '2034fb': 'Xiaomi', '286c07': 'Xiaomi', '34800d': 'Xiaomi',
      '38a4ed': 'Xiaomi', '3cbd3e': 'Xiaomi', '50642b': 'Xiaomi', '584498': 'Xiaomi',
      '640980': 'Xiaomi', '68dfdd': 'Xiaomi', '742344': 'Xiaomi', '7802f8': 'Xiaomi',
      '7c49eb': 'Xiaomi', '8cbebe': 'Xiaomi', '98fae3': 'Xiaomi', 'a4c361': 'Xiaomi',
      'acc1ee': 'Xiaomi', 'b0e5ed': 'Xiaomi', 'c40bcb': 'Xiaomi', 'd4970b': 'Xiaomi',
      'e4aaea': 'Xiaomi', 'ec4118': 'Xiaomi', 'f0b429': 'Xiaomi', 'f4f5db': 'Xiaomi',
      // Intel
      '001b21': 'Intel', '001e64': 'Intel', '00216a': 'Intel', '002314': 'Intel',
      '0024d7': 'Intel', '3413e8': 'Intel', '3cfdfe': 'Intel', '4851b7': 'Intel',
      '4c796e': 'Intel', '6805ca': 'Intel', '7c2adb': 'Intel', '8086f2': 'Intel',
      // Cisco
      '00000c': 'Cisco', '000142': 'Cisco', '000143': 'Cisco', '000163': 'Cisco',
      '000164': 'Cisco', '000196': 'Cisco', '000197': 'Cisco', '0001c7': 'Cisco',
      // Raspberry Pi
      'b827eb': 'Raspberry Pi', 'dca632': 'Raspberry Pi', 'e45f01': 'Raspberry Pi', '28cdc1': 'Raspberry Pi',
      // Espressif (IoT)
      '240ac4': 'Espressif', '246f28': 'Espressif', '30aea4': 'Espressif', '3c71bf': 'Espressif',
      '840d8e': 'Espressif', '84f3eb': 'Espressif', 'a4cf12': 'Espressif', 'bcddc2': 'Espressif',
      // Ruijie
      '001aa9': 'Ruijie', '002713': 'Ruijie', '14144b': 'Ruijie',
    };

    return vendorMap[prefix];
  }

  /// 解析系统 `arp -a` 或 `arp -an` 文本输出。
  static List<ArpHost> parseSystemArpTable(String text, {String? cidr}) {
    final hosts = <ArpHost>[];
    final seenIps = <String>{};

    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.contains('incomplete')) continue;

      // 提取 IP 地址：支持 (192.168.1.1) 或裸 IP 格式
      final ipMatch = RegExp(
        r'(?:^|[\s\(])(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})(?:[\s\)]|$)',
      ).firstMatch(line);
      if (ipMatch == null) continue;
      final ip = ipMatch.group(1)!;

      // 提取 MAC 物理地址：支持 at xx:xx 或 lladdr xx:xx
      final macMatch = RegExp(
        r'(?:at|lladdr)\s+([0-9a-fA-F]{1,2}(?::[0-9a-fA-F]{1,2}){5})',
      ).firstMatch(line);
      if (macMatch == null) continue;
      final rawMac = macMatch.group(1)!;

      // 规范化 MAC 为 2 位十六进制冒号分隔
      final normalizedMac = rawMac
          .split(':')
          .map((p) => p.padLeft(2, '0').toLowerCase())
          .join(':');

      // 过滤广播与多播 MAC
      if (normalizedMac == 'ff:ff:ff:ff:ff:ff' ||
          normalizedMac.startsWith('01:00:5e')) {
        continue;
      }

      // 过滤组播、广播与子网基地址
      if (ip.startsWith('224.') ||
          ip.startsWith('239.') ||
          ip.endsWith('.255') ||
          ip.endsWith('.0')) {
        continue;
      }

      // 若指定了目标网段，仅收录处于该网段的 IP
      if (cidr != null && !NetworkInterfaceDetector.isIpInCidr(ip, cidr)) {
        continue;
      }

      if (seenIps.add(ip)) {
        // 尝试提取主机名（如 router (192.168.1.1)）
        String? hostname;
        final hostMatch = RegExp(r'^([A-Za-z0-9_\-\.]+)\s+\(').firstMatch(line);
        if (hostMatch != null && hostMatch.group(1) != '?') {
          hostname = hostMatch.group(1);
        }

        final vendor = lookupVendor(normalizedMac);
        hosts.add(
          ArpHost(
            ip: ip,
            mac: normalizedMac,
            vendor: vendor,
            hostname: hostname,
          ),
        );
      }
    }
    return hosts;
  }

  /// 扫描局域网存活主机。
  static Future<List<ArpHost>> scan({
    String? cidr,
    bool useArpScan = false,
    Future<String> Function(String, List<String>, {Duration timeout})? runner,
    void Function(String line)? onLog,
    Future<void> Function(List<String>)? prober,
  }) async {
    final run =
        runner ??
        (exe, args, {Duration timeout = const Duration(seconds: 90)}) async {
          final r = await runCaptured(exe, args, timeout: timeout);
          return r.stdout;
        };
    final targetCidr = cidr ?? '192.168.1.0/24';

    // ── 阶段 1：免 Root 模式（UDP 扇出激发 + 读取系统内核 ARP 缓存） ──
    onLog?.call('发送 UDP 探针激发子网链路层 ARP 响应 ($targetCidr)…');
    final ips = NetworkInterfaceDetector.expandCidrToIps(targetCidr);
    if (ips.isNotEmpty) {
      await triggerUdpProbe(ips, customProber: prober);
    }

    onLog?.call('读取系统内核 ARP 缓存表…');
    final arpOut = await run('arp', const ['-a'], timeout: const Duration(seconds: 5));
    final cachedHosts = parseSystemArpTable(arpOut, cidr: targetCidr);

    // 补充本机接口（若处于该网段但未在 ARP 表中呈现）
    final hostMap = <String, ArpHost>{for (final h in cachedHosts) h.ip: h};
    try {
      final ifaces = await NetworkInterfaceDetector.detect(runner: runner);
      for (final iface in ifaces) {
        if (NetworkInterfaceDetector.isIpInCidr(iface.ipv4, targetCidr) &&
            !hostMap.containsKey(iface.ipv4)) {
          hostMap[iface.ipv4] = ArpHost(
            ip: iface.ipv4,
            hostname: 'localhost',
          );
        }
      }
    } catch (_) {}

    if (hostMap.isNotEmpty) {
      final result = hostMap.values.toList();
      onLog?.call('系统 ARP 表发现 ${result.length} 台在线设备');
      return result;
    }

    // ── 阶段 2：特权 arp-scan 模式（用户环境已配置/具备特权时按需使用） ──
    if (useArpScan &&
        (resolveExecutable('arp-scan') != null || runner != null)) {
      try {
        onLog?.call('尝试 arp-scan 探测…');
        final out = await run('arp-scan', [
          targetCidr,
          '--localnet',
        ], timeout: const Duration(seconds: 15));
        final hosts = parseArpScan(out);
        if (hosts.isNotEmpty) {
          onLog?.call('arp-scan 发现 ${hosts.length} 台在线设备');
          return hosts;
        }
      } catch (_) {}
    }

    // ── 阶段 3：nmap 多协议存活 Ping 回落 ──
    onLog?.call('回落至 nmap 多协议存活探测 ($targetCidr)…');
    final out = await run('nmap', [
      '-sn',
      '-PS22,80,443,8080,5000,7000',
      '-PU53,137,5353',
      '-PE',
      targetCidr,
      '-oX',
      '-',
    ], timeout: const Duration(seconds: 60));
    final nmapHosts = parseNmapHostDiscovery(out);
    onLog?.call('nmap 探测到 ${nmapHosts.length} 台在线主机');
    return nmapHosts;
  }

  /// 解析 arp-scan 文本输出：
  /// `192.168.1.1\t00:11:22:33:44:55\tTP-LINK TECHNOLOGIES CO.,LTD.`
  static List<ArpHost> parseArpScan(String text) {
    final hosts = <ArpHost>[];
    for (final line in text.split('\n')) {
      final match = RegExp(
        r'^(\d+\.\d+\.\d+\.\d+)\s+([0-9a-fA-F:]{17})\s*(.*)$',
      ).firstMatch(line.trim());
      if (match == null) continue;
      hosts.add(
        ArpHost(
          ip: match.group(1)!,
          mac: match.group(2)!,
          vendor: match.group(3)!.trim().isEmpty ? null : match.group(3)!.trim(),
        ),
      );
    }
    return hosts;
  }

  /// 解析 `nmap -sn -oX -` 的 XML（只取 address/hostnames）。
  static List<ArpHost> parseNmapHostDiscovery(String xmlText) {
    try {
      final doc = XmlDocument.parse(xmlText);
      final hosts = <ArpHost>[];
      for (final host in doc.findAllElements('host')) {
        String? ip;
        String? mac;
        String? vendor;
        for (final address in host.findElements('address')) {
          final type = address.getAttribute('addrtype');
          if (type == 'ipv4') ip = address.getAttribute('addr');
          if (type == 'mac') {
            mac = address.getAttribute('addr');
            vendor = address.getAttribute('vendor');
          }
        }
        if (ip == null) continue;
        String? hostname;
        for (final names in host.findElements('hostnames')) {
          for (final name in names.findElements('hostname')) {
            hostname ??= name.getAttribute('name');
          }
        }
        hosts.add(ArpHost(ip: ip, mac: mac, vendor: vendor, hostname: hostname));
      }
      return hosts;
    } catch (_) {
      // XML 被截断/非 XML 输出时返回空，让上层按"无结果"处理而不是崩溃。
      return const [];
    }
  }
}

/// nmap 深度扫描模式。
enum NmapScanMode {
  quick('快速', '-F', 'Top 100 端口'),
  standard('标准', '', 'Top 1000 端口'),
  fullPorts('全端口', '-p-', '1-65535');

  final String label;
  final String flag;
  final String hint;

  const NmapScanMode(this.label, this.flag, this.hint);
}

/// 一台主机上的一个开放端口。
class ScannedPort {
  final int port;
  final String protocol;
  final String service;
  final String? product;
  final String? version;
  final String? state;

  const ScannedPort({
    required this.port,
    required this.protocol,
    required this.service,
    this.product,
    this.version,
    this.state,
  });

  Map<String, dynamic> toJson() => {
    'port': port,
    'protocol': protocol,
    'service': service,
    'product': product,
    'version': version,
  };

  String get label =>
      '$port/$protocol ${version == null || version!.isEmpty ? service : '$service $version'}';
}

/// nmap 对一台主机的完整结果。
class ScannedHost {
  final String ip;
  final String? hostname;
  final String? mac;
  final String? vendor;
  final String? osName;
  final String? osAccuracy;
  final List<ScannedPort> ports;
  final bool isUp;

  const ScannedHost({
    required this.ip,
    this.hostname,
    this.mac,
    this.vendor,
    this.osName,
    this.osAccuracy,
    this.ports = const [],
    this.isUp = true,
  });

  Map<String, dynamic> toMetadata() => {
    if (mac != null) 'mac': mac,
    if (vendor != null) 'vendor': vendor,
    if (hostname != null) 'hostname': hostname,
    if (osName != null) 'os': osName,
    'ports': ports.map((p) => p.toJson()).toList(),
  };
}

/// nmap 服务与端口枚举。
abstract final class NmapService {
  /// nmap 是否可用（PATH 加固后的判断）。
  ///
  /// 测试用它决定是否跳过端到端用例——没装 nmap 的机器不该红。
  static bool isAvailable() => resolveExecutable('nmap') != null;

  /// 执行扫描并解析 XML。
  ///
  /// [onLog] 每次收到 stdout 行时回调（nmap 的进度打印到 stdout）。
  static Future<List<ScannedHost>> scan({
    required String target,
    NmapScanMode mode = NmapScanMode.standard,
    bool withServiceVersion = true,
    bool withOsDetect = false,
    Duration timeout = const Duration(minutes: 10),
    void Function(String line)? onLog,
    Future<String> Function(String, List<String>, {Duration timeout})? runner,
  }) async {
    if (runner == null && resolveExecutable('nmap') == null) {
      return const [];
    }
    final run =
        runner ??
        (exe, args, {Duration timeout = const Duration(minutes: 10)}) async {
          final r = await runCaptured(exe, args, timeout: timeout);
          return r.stdout;
        };
    final args = <String>[
      if (mode.flag.isNotEmpty) mode.flag,
      '--open',
      if (withServiceVersion) ...[ '-sV', '-sC' ],
      if (withOsDetect) '-O',
      '-oX',
      '-',
      target,
    ];
    final out = await run('nmap', args, timeout: timeout);
    return parseNmapXml(out);
  }

  /// 解析 `nmap -oX -` 输出（测试直接喂 XML 文本）。
  static List<ScannedHost> parseNmapXml(String xmlText) {
    try {
      final doc = XmlDocument.parse(xmlText);
      final hosts = <ScannedHost>[];
      for (final hostEl in doc.findAllElements('host')) {
        final statusEl = hostEl.findElements('status').firstOrNull;
        final isUp = statusEl?.getAttribute('state') != 'down';
        String? ip;
        String? mac;
        String? vendor;
        for (final address in hostEl.findElements('address')) {
          switch (address.getAttribute('addrtype')) {
            case 'ipv4':
              ip = address.getAttribute('addr');
            case 'mac':
              mac = address.getAttribute('addr');
              vendor = address.getAttribute('vendor');
          }
        }
        if (ip == null) continue;

        String? hostname;
        for (final names in hostEl.findElements('hostnames')) {
          for (final name in names.findElements('hostname')) {
            hostname ??= name.getAttribute('name');
          }
        }

        String? osName;
        String? osAccuracy;
        for (final os in hostEl.findElements('os')) {
          for (final match in os.findElements('osmatch')) {
            osName ??= match.getAttribute('name');
            osAccuracy ??= match.getAttribute('accuracy');
            break;
          }
        }

        final ports = <ScannedPort>[];
        for (final portsEl in hostEl.findElements('ports')) {
          for (final portEl in portsEl.findElements('port')) {
            final stateEl = portEl.findElements('state').firstOrNull;
            final serviceEl = portEl.findElements('service').firstOrNull;
            ports.add(
              ScannedPort(
                port: int.tryParse(portEl.getAttribute('portid') ?? '') ?? 0,
                protocol: portEl.getAttribute('protocol') ?? 'tcp',
                service: serviceEl?.getAttribute('name') ?? 'unknown',
                product: serviceEl?.getAttribute('product'),
                version: serviceEl?.getAttribute('version'),
                state: stateEl?.getAttribute('state'),
              ),
            );
          }
        }

        hosts.add(
          ScannedHost(
            ip: ip,
            hostname: hostname,
            mac: mac,
            vendor: vendor,
            osName: osName,
            osAccuracy: osAccuracy,
            ports: ports,
            isUp: isUp,
          ),
        );
      }
      return hosts;
    } catch (_) {
      // 同上：XML 不完整时按无结果处理。
      return const [];
    }
  }

  /// 主机服务摘要（设备列表里的一行小字）。
  static String portSummary(List<ScannedPort> ports, {int max = 6}) {
    if (ports.isEmpty) return '无开放端口';
    final names = ports.map((p) => p.service).toSet().take(max).join(', ');
    final extra = ports.length > max ? ' +${ports.length - max}' : '';
    return '$names$extra';
  }
}

/// 把扫描结论映射为风险等级。
///
/// 有高危服务（SMB/RDP/ Telnet 等）→ high；有常见 Web/DB 端口 → medium；
/// 只有无害端口 → low；无端口 → info。
String riskLevelForHost(ScannedHost host) {
  if (host.ports.isEmpty) return Severity.info.key;
  const highRiskPorts = {445, 3389, 23, 5900, 6379, 9200, 27017};
  final hasHigh = host.ports.any((p) => highRiskPorts.contains(p.port));
  if (hasHigh) return Severity.high.key;
  const mediumPorts = {80, 443, 3306, 5432, 1433, 21, 22, 25};
  final hasMedium = host.ports.any((p) => mediumPorts.contains(p.port));
  if (hasMedium) return Severity.medium.key;
  return Severity.low.key;
}

/// 从主机推断设备类型图标（拓扑图节点用）。
String deviceTypeFor(ScannedHost host) {
  final os = (host.osName ?? '').toLowerCase();
  final vendor = (host.vendor ?? '').toLowerCase();
  if (vendor.contains('apple')) return 'phone';
  if (vendor.contains('tp-link') ||
      vendor.contains('router') ||
      vendor.contains('cisco') ||
      vendor.contains('ubiquiti')) {
    return 'router';
  }
  if (os.contains('windows')) return 'pc';
  if (os.contains('linux')) return 'pc';
  if (os.contains('android') || os.contains('ios')) return 'phone';
  if (host.ports.any((p) => p.port == 80 || p.port == 443)) return 'server';
  return 'device';
}

/// JSONL / JSON 行解析的公共工具（web recon 各服务共用）。
List<Map<String, dynamic>> parseJsonLines(String text) {
  final result = <Map<String, dynamic>>[];
  for (final line in text.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('{')) continue;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) result.add(Map<String, dynamic>.from(decoded));
    } catch (_) {
      // 单行 JSON 不完整（进程被 kill）时跳过该行。
    }
  }
  return result;
}
