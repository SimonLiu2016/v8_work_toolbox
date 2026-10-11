import 'dart:io';

import 'package:flutter/foundation.dart';


/// 根 CA 的三种状态（spec「根 CA 安装引导」的三态呈现）。
enum ArtexCaState {
  /// 引擎从未成功运行，证书还没生成。
  notGenerated,

  /// 证书已生成，但未安装到系统信任库。
  generatedNotTrusted,

  /// 已安装到系统信任库。
  trusted;

  bool get needsGuidance => this == generatedNotTrusted;
}

/// 根 CA 的检测与安装命令生成（task 7）。
///
/// **本服务绝不自动执行安装**：`security add-trusted-cert` 需要 sudo，且装进
/// System.keychain 后对全系统生效——这是系统级副作用，必须由用户显式确认后
/// 自行执行（spec「根 CA 安装引导」的 MUST NOT）。
class ArtexCaService {
  ArtexCaService._();
  static final ArtexCaService instance = ArtexCaService._();

  static const String _certFileName = 'mitmproxy-ca-cert.pem';
  static const String _certSubPath = 'data/traffic/_ca';

  /// 证书文件的宿主机路径。
  ///
  /// compose 把 `./data` 绑到宿主机，所以证书就在工程目录下——不需要
  /// `docker cp`。注意 `_ca` 目录被 artex chmod 成 700/600，宿主机普通
  /// 用户读不了，安装命令必须 sudo。
  String certPath(String projectDir) =>
      '$projectDir/$_certSubPath/$_certFileName';

  /// 检测当前状态。
  ///
  /// [isTrusted] 可注入以便测试；生产用 `security find-certificate` 查系统库。
  Future<ArtexCaState> detect(
    String projectDir, {
    Future<bool> Function(String certPath)? isTrusted,
  }) async {
    if (!File(certPath(projectDir)).existsSync()) {
      return ArtexCaState.notGenerated;
    }
    final trusted =
        await (isTrusted ?? _isTrustedInSystemKeychain)(certPath(projectDir));
    return trusted ? ArtexCaState.trusted : ArtexCaState.generatedNotTrusted;
  }

  /// 安装命令。
  ///
  /// `-d` 加到管理域设置、`-r trustRoot` 标记为信任根证书。卸载需要用户
  /// 自行处理——见 [uninstallHint]。
  String installCommand(String projectDir) {
    final cert = certPath(projectDir);
    return 'sudo security add-trusted-cert -d -r trustRoot '
        '-k /Library/Keychains/System.keychain "$cert"';
  }

  /// 卸载提示。
  ///
  /// 装进 System.keychain 后无法靠删除文件撤回，必须在钥匙串访问里手工删。
  /// 这条 MUST 随安装命令一起展示（spec「UI 明示系统级影响与需自行卸载」）。
  String get uninstallHint =>
      '该证书装入系统信任库后对全系统生效。如需卸载，请打开「钥匙串访问」'
      '→ 系统 → 证书，找到 mitmproxy 相关条目删除。';

  /// 用 macOS `security` 查系统钥匙串里是否已有该证书。
  Future<bool> _isTrustedInSystemKeychain(String certPath) async {
    try {
      final result = await Process.run('security', <String>[
        'find-certificate',
        '-c',
        'mitmproxy',
        '/Library/Keychains/System.keychain',
      ]);
      if (result.exitCode != 0) return false;
      final out = '${result.stdout}${result.stderr}';
      // find-certificate 命中时会打印证书详情；未命中返回非 0 或空输出。
      return out.toLowerCase().contains('mitmproxy');
    } catch (e) {
      debugPrint('[ArtexCaService] 查询系统钥匙串失败: $e');
      return false;
    }
  }
}
