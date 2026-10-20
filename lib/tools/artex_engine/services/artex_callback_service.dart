import 'dart:io';

import 'package:flutter/foundation.dart';


/// 宿主机上可用于内网回连的 IPv4 探测。
///
/// **为什么需要它**：ARTEX 的隧道 / 反弹 shell 要让内网目标机回连平台，
/// 回连地址来自 `ARTEX_CALLBACK_ADDR` 的 host 部分。写 `127.0.0.1` 或
/// Docker VM 的地址都会让目标机连不回来——必须是宿主机上可被内网路由到的
/// 物理网卡地址。
///
/// **为什么要解析 `ifconfig` 而不是用 `dart:io` 的 `NetworkInterface.list`**：
/// macOS 上 `NetworkInterface.name` 只有 `en0` / `lo0` 这样的 BSD 名，
/// 拿不到「物理 vs 虚拟」的区分。本机实测同时存在 `en0`(192.168.1.3)、
/// `en5`、`utun0-4`、`utun88`(198.18.0.1, TUN 虚拟网关)、`bridge0`、
/// `bridge100`(192.168.64.1, Docker 的 vmnet 网桥)、`awdl0`、`llw0`、
/// `vmenet0`、`ap1`。挑错一个，目标机就回不来。
///
/// 解析模式参照 `lib/tools/security_toolbox/services/lan_recon_services.dart`
/// 的 `NetworkInterfaceDetector`，但这里不跨工具 import——artex_engine 对
/// 其他工具保持零依赖，只取「第一个物理网卡 IPv4」这一件更小的事。
abstract final class ArtexCallbackService {
  ArtexCallbackService._();

  /// 虚拟接口名前缀。这些接口的 IPv4 都不能当回连地址。
  ///
  /// - `lo0` / `lo`：回环，目标机连不到
  /// - `utun*`：VPN/TUN 隧道（含 Clash 之类的虚拟网关）
  /// - `bridge*`：Docker Desktop 的 vmnet 网桥、Thunderbolt 桥接
  /// - `vmenet`：VMware 虚拟网卡
  /// - `awdl`：Apple Wireless Direct Link（AirDrop）
  /// - `llw`：Low Latency WAN
  /// - `gif*` / `stf*`：通用隧道接口 / 6to4
  /// - `ap1`：WiFi 热点
  /// - `ipsec*` / `ppp*` / `tun*` / `tap*`：其他隧道类
  static const List<String> _virtualPrefixes = [
    'lo',
    'utun',
    'bridge',
    'vmenet',
    'awdl',
    'llw',
    'gif',
    'stf',
    'ap',
    'ipsec',
    'ppp',
    'tun',
    'tap',
    'vboxnet',
    'vethernet',
    'hyperv',
    'virbr',
    'docker',
  ];

  /// 探测候选回连地址，按「物理网卡优先、en 序号小的优先」排序。
  ///
  /// 返回空列表表示找不到可用地址（所有网卡断开、或命令执行失败）。
  /// 命令失败一律返回空而不是抛异常——调用方要把这当成一类可报告的
  /// 启动失败，不是崩溃。
  static Future<List<String>> detectCandidates({
    Future<String> Function(String, List<String>)? runner,
  }) async {
    final run =
        runner ??
        (exe, args) async {
          final result = await Process.run(exe, args);
          return '${result.stdout}';
        };
    try {
      // macOS 优先 ifconfig；失败再试 Linux 风格的 `ip -o -4 addr`。
      final list = parseIfconfig(await run('ifconfig', const []));
      if (list.isNotEmpty) return list;
      return parseIpAddr(await run('ip', const ['-o', '-4', 'addr', 'show']));
    } catch (e) {
      debugPrint('[ArtexCallbackService] 探测网卡失败: $e');
      return const [];
    }
  }

  /// 单个候选：取排序后的第一个；没有返回 null。
  static Future<String?> detectSingle({
    Future<String> Function(String, List<String>)? runner,
  }) async {
    final all = await detectCandidates(runner: runner);
    return all.isEmpty ? null : all.first;
  }

  /// 从 `ifconfig` 输出解析物理网卡 IPv4。
  ///
  /// 过滤规则：非虚拟接口、状态 UP、有 IPv4。排序让 `en0` 排在 `en5` 前
  /// （主用网卡通常是序号最小的）。
  static List<String> parseIfconfig(String text) {
    final found = <String, String>{}; // name -> ipv4
    // 接口块以行首非空白字符开头（"en0: flags=8863<UP,...> mtu 1500"），
    // 缩进行（"\t inet ..."）归属当前块。用 lastBlock 累积而不是索引赋值
    // （Dart 的 List 没有 index setter）。
    final blocks = <String>[];
    for (final line in text.split('\n')) {
      if (line.isEmpty) continue;
      if (line.startsWith(' ') || line.startsWith('\t')) {
        if (blocks.isNotEmpty) blocks.add('${blocks.removeLast()}\n$line');
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
      if (_isVirtual(name)) continue;
      if (!header.contains('<UP') && !header.contains('UP,')) continue;

      final inetMatch = RegExp(
        r'inet (\d+\.\d+\.\d+\.\d+)',
      ).firstMatch(block);
      if (inetMatch == null) continue;
      found[name] = inetMatch.group(1)!;
    }
    final names = found.keys.toList()..sort();
    return names.map((n) => found[n]!).toList();
  }

  /// 从 Linux `ip -o -4 addr show` 输出解析物理网卡 IPv4。
  static List<String> parseIpAddr(String text) {
    final found = <String, String>{};
    for (final line in text.split('\n')) {
      final match = RegExp(
        r'^\d+:\s+([A-Za-z0-9_]+)\s+inet\s+(\d+\.\d+\.\d+\.\d+)/\d+',
      ).firstMatch(line);
      if (match == null) continue;
      final name = match.group(1)!;
      if (_isVirtual(name)) continue;
      found[name] = match.group(2)!;
    }
    final names = found.keys.toList()..sort();
    return names.map((n) => found[n]!).toList();
  }

  /// 该接口是否是虚拟/隧道/桥接类。
  static bool _isVirtual(String name) {
    final lower = name.toLowerCase();
    for (final prefix in _virtualPrefixes) {
      if (lower == prefix || lower.startsWith(prefix)) return true;
    }
    return false;
  }

  /// 测试用：判断接口名是否被当作虚拟接口。
  @visibleForTesting
  static bool debugIsVirtual(String name) => _isVirtual(name);
}
