/// 受管 CLI 工具清单。
///
/// 每个条目就是一次 `which` + 版本命令的探测目标，也是 `brew install` 的包名来源。
/// brew 包名与可执行文件名不同的（sqlmap 装在 `bin/sqlmap`，searchsploit 来自
/// `exploitdb`）必须分开写，否则安装按钮会用错包名。
library;

import '../models/security_enums.dart';

/// 工具安装方式/渠道。
enum InstallMethod {
  /// 通过 Homebrew 安装。
  brew,

  /// 通过 pipx 安装（如 netexec）。
  pipx,

  /// 需手动安装或通过官方安装器（如 metasploit）。
  manual;

  String get label => switch (this) {
    InstallMethod.brew => 'Homebrew',
    InstallMethod.pipx => 'pipx',
    InstallMethod.manual => '手动安装',
  };
}

/// 一个受管外部工具。
class SecurityTool {
  /// 稳定 id（同时是 UI key）。
  final String id;

  final String displayName;

  /// Homebrew 包名（若走 brew）。
  final String brewName;

  /// PATH 中的可执行文件名。
  final String executable;

  final ToolPurpose purpose;

  /// 最低可用版本，null 表示不校验版本。
  final String? minVersion;

  /// 探测版本的参数，默认 `--version`。
  final String versionArg;

  /// 安装渠道，默认为 Homebrew。
  final InstallMethod installMethod;

  /// 特殊安装或编译耗时提示。
  final String? installNote;

  /// 手动安装引导说明或官方文档外链。
  final String? manualInstallUrl;

  /// pipx 安装的目标包名或 git 仓库（若走 pipx 且与 executable 不同）。
  final String? pipxPackage;

  const SecurityTool({
    required this.id,
    required this.displayName,
    required this.brewName,
    required this.executable,
    required this.purpose,
    this.minVersion,
    this.versionArg = '--version',
    this.installMethod = InstallMethod.brew,
    this.installNote,
    this.manualInstallUrl,
    this.pipxPackage,
  });
}

/// 清单本体。
abstract final class SecurityToolRegistry {
  static const List<SecurityTool> tools = [
    SecurityTool(
      id: 'nmap',
      displayName: 'Nmap',
      brewName: 'nmap',
      executable: 'nmap',
      purpose: ToolPurpose.lanRecon,
      minVersion: '7.0',
    ),
    SecurityTool(
      id: 'arp-scan',
      displayName: 'arp-scan',
      brewName: 'arp-scan',
      executable: 'arp-scan',
      purpose: ToolPurpose.lanRecon,
      versionArg: '--help',
    ),
    SecurityTool(
      id: 'masscan',
      displayName: 'masscan',
      brewName: 'masscan',
      executable: 'masscan',
      purpose: ToolPurpose.lanRecon,
      versionArg: '--version',
    ),
    SecurityTool(
      id: 'nuclei',
      displayName: 'Nuclei',
      brewName: 'nuclei',
      executable: 'nuclei',
      purpose: ToolPurpose.vulnScan,
      minVersion: '3.0',
      versionArg: '-version',
    ),
    SecurityTool(
      id: 'subfinder',
      displayName: 'Subfinder',
      brewName: 'subfinder',
      executable: 'subfinder',
      purpose: ToolPurpose.webRecon,
      minVersion: '2.0',
      versionArg: '-version',
    ),
    SecurityTool(
      id: 'httpx',
      displayName: 'httpx',
      brewName: 'httpx',
      executable: 'httpx',
      purpose: ToolPurpose.webRecon,
      versionArg: '-version',
      installNote: '部分架构需本地 Go 编译，约需 2~4 分钟',
    ),
    SecurityTool(
      id: 'katana',
      displayName: 'Katana',
      brewName: 'katana',
      executable: 'katana',
      purpose: ToolPurpose.webRecon,
      versionArg: '-version',
    ),
    SecurityTool(
      id: 'ffuf',
      displayName: 'ffuf',
      brewName: 'ffuf',
      executable: 'ffuf',
      purpose: ToolPurpose.webRecon,
      versionArg: '-V',
      installNote: '部分架构需本地 Go 编译，约需 2~3 分钟',
    ),
    SecurityTool(
      id: 'sqlmap',
      displayName: 'sqlmap',
      brewName: 'sqlmap',
      executable: 'sqlmap',
      purpose: ToolPurpose.vulnScan,
      versionArg: '--version',
    ),
    SecurityTool(
      id: 'gau',
      displayName: 'gau',
      brewName: 'gau',
      executable: 'gau',
      purpose: ToolPurpose.webRecon,
      versionArg: '--version',
    ),
    SecurityTool(
      id: 'metasploit',
      displayName: 'Metasploit',
      brewName: 'metasploit',
      executable: 'msfconsole',
      purpose: ToolPurpose.exploit,
      versionArg: '--version',
      installMethod: InstallMethod.manual,
      installNote: 'Homebrew 官方已禁用，请使用 Rapid7 官方安装器安装',
      manualInstallUrl:
          'https://docs.metasploit.com/docs/using-metasploit/getting-started/nightly-installers.html',
    ),
    SecurityTool(
      id: 'bettercap',
      displayName: 'bettercap',
      brewName: 'bettercap',
      executable: 'bettercap',
      purpose: ToolPurpose.lanRecon,
      versionArg: '--version',
    ),
    // netexec 官方未进入 Homebrew 核心源，标准方式为 pipx 安装。
    SecurityTool(
      id: 'netexec',
      displayName: 'NetExec',
      brewName: 'netexec',
      executable: 'netexec',
      purpose: ToolPurpose.exploit,
      versionArg: '--version',
      installMethod: InstallMethod.pipx,
      pipxPackage: 'git+https://github.com/Pennyw0rth/NetExec',
      installNote: 'Homebrew 核心库无此包，通过 pipx 安装官方源码库',
    ),
    // 可执行文件 searchsploit 来自 exploitdb formula。
    SecurityTool(
      id: 'searchsploit',
      displayName: 'SearchSploit',
      brewName: 'exploitdb',
      executable: 'searchsploit',
      purpose: ToolPurpose.exploit,
      versionArg: '--version',
      installNote: '需克隆 exploitdb 仓库（约 1GB），耗时视网络而定',
    ),
    SecurityTool(
      id: 'hydra',
      displayName: 'THC-Hydra',
      brewName: 'hydra',
      executable: 'hydra',
      purpose: ToolPurpose.exploit,
      versionArg: '-h',
    ),
  ];

  static SecurityTool? byId(String id) {
    for (final t in tools) {
      if (t.id == id) return t;
    }
    return null;
  }

  static List<SecurityTool> byPurpose(ToolPurpose purpose) =>
      tools.where((t) => t.purpose == purpose).toList();
}
