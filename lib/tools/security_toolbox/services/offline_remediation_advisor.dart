/// 本地离线安全加固与应急缓解建议引擎。
///
/// 当云端 AI 遭遇网络超时、内容审查挂起或处于熔断冷却期时，
/// 自动调用本地规则库生成规范化、可落地的防御处置指引。
library;

import '../models/security_enums.dart';
import '../models/security_models.dart';

abstract final class OfflineRemediationAdvisor {
  /// 为单条漏洞发现物生成防御处置建议。
  static String build({
    required PentestFinding finding,
    required String targetHost,
  }) {
    final title = finding.title.toLowerCase();
    final cve = finding.cveId;
    final sev = finding.severityLevel;

    final buffer = StringBuffer()
      ..writeln('### 【本地防御加固基线建议】')
      ..writeln('- **目标资产**：`$targetHost`')
      ..writeln('- **风险名称**：${finding.title}')
      ..writeln('- **危害级别**：${sev.label} (CVSS: ${finding.cvssScore?.toStringAsFixed(1) ?? '未知'})')
      ..writeln('- **CVE 编号**：${cve ?? '暂无'}')
      ..writeln();

    if (title.contains('ssh') || title.contains('openssh')) {
      buffer
        ..writeln('#### 1. 风险成因与潜在危害')
        ..writeln('公网直接暴露 SSH 远程管理端口（通常为 22 端口），极易面临自动化字典暴力破解、用户名枚举以及已知版本的未授权探测。')
        ..writeln()
        ..writeln('#### 2. 应急临时缓解措施')
        ..writeln('- 配置安全组 / 云防火墙网络 ACL，仅允许受信任的内网 IP、管理跳板机或企业 VPN 访问 22 端口。')
        ..writeln('- 如无法限制 IP，可临时修改默认端口为高位随机端口（例如 22222），规避全网低频扫描。')
        ..writeln()
        ..writeln('#### 3. 永久加固与最佳实践')
        ..writeln('- 修改 `/etc/ssh/sshd_config`：')
        ..writeln('  ```bash')
        ..writeln('  PermitRootLogin prohibit-password  # 禁止 root 密码直连')
        ..writeln('  PasswordAuthentication no          # 关闭密码认证，强制公钥')
        ..writeln('  PubkeyAuthentication yes           # 仅启用密钥认证')
        ..writeln('  MaxAuthTries 3                     # 单次连接最多尝试认证 3 次')
        ..writeln('  ```')
        ..writeln('- 部署 `fail2ban` 或云主机 HIDS，针对 5 分钟内连续认证失败 5 次的 IP 封禁 24 小时。')
        ..writeln()
        ..writeln('#### 4. 验证与复测要点')
        ..writeln('- 从非白名单外网 IP 尝试 `ssh -v $targetHost`，确认 TCP 握手直接被丢弃（Drop）或拒绝（Reject）。');
      return buffer.toString();
    }

    if (finding.source == FindingSource.sqlmap ||
        title.contains('sql') ||
        title.contains('injection')) {
      buffer
        ..writeln('#### 1. 风险成因与潜在危害')
        ..writeln('Web 应用程序对外部输入参数缺乏充分过滤或参数化校验，攻击者可能借此窃取数据库敏感数据、篡改数据甚至读取底层操作系统文件。')
        ..writeln()
        ..writeln('#### 2. 应急临时缓解措施')
        ..writeln('- 在 WAF 或应用网关处针对该接口添加临时规则，拦截包含单引号、注释符、UNION 等特征的 SQL 注入攻击流量。')
        ..writeln('- 若该接口非核心业务，可在反向代理层临时将该 URL 重定向至 404 或维护页。')
        ..writeln()
        ..writeln('#### 3. 代码修复与加固方案')
        ..writeln('- **彻底使用预编译参数化查询 (Prepared Statements)**，禁止任何形式的动态 SQL 字符串拼接。')
        ..writeln('- 实施数据访问层最小权限原则：Web 服务连接数据库的账号严禁拥有 DBA/sa/root 权限，严格限制其跨库查询与文件读写特权。')
        ..writeln('- 开启输入白名单校验，限制参数的类型（如严格校验整数类型）与字符长度。')
        ..writeln()
        ..writeln('#### 4. 验证与复测要点')
        ..writeln('- 使用正常业务参数重新请求，验证功能完好；使用特殊字符（如引号与算术表达式）请求，确认接口返回结构化业务错误且无底层 SQL 异常栈暴露。');
      return buffer.toString();
    }

    if (cve != null && cve.isNotEmpty) {
      buffer
        ..writeln('#### 1. 风险成因与潜在危害')
        ..writeln('系统检测到已知公开漏洞编号 **$cve**。此类漏洞往往具备成熟的公开原理验证分析，可能涉及未授权访问、组件反序列化或任意文件操作。')
        ..writeln()
        ..writeln('#### 2. 应急临时缓解措施')
        ..writeln('- 排查是否有厂商官方发布的临时缓解方案（如关闭特定子功能、配置安全过滤中间件等）。')
        ..writeln('- 在反向代理/WAF 层根据漏洞披露的 URI 模式阻断外部访问路径。')
        ..writeln()
        ..writeln('#### 3. 官方补丁与修复方案')
        ..writeln('- 查看官方安全公告及 NVD 数据库（`https://nvd.nist.gov/vuln/detail/$cve`），升级受影响的基础组件至最新安全稳定版本。')
        ..writeln('- 检查软件依赖项（如 Maven/npm/pip 等），更新存在已知漏洞的三方依赖库。')
        ..writeln()
        ..writeln('#### 4. 验证与复测要点')
        ..writeln('- 确认组件版本号已更新，并使用 Nuclei 重新扫描该资产，确保模板规则不再命中。');
      return buffer.toString();
    }

    // 通用降级加固方案
    buffer
      ..writeln('#### 1. 风险成因与潜在危害')
      ..writeln('检测到目标资产存在安全脆弱性或服务配置不当，可能为外部侦察提供指纹特征，甚至成为横向移动的突破口。')
      ..writeln()
      ..writeln('#### 2. 应急处置与加固建议')
      ..writeln('- **收敛暴露面**：审查目标端口与接口是否确有公网开放必要，关闭或隔离非必要的管理端口。')
      ..writeln('- **加固认证与配置**：强化所有管理端点的身份认证机制，开启多因素认证 (MFA) 并停用系统默认口令。')
      ..writeln('- **隐藏系统指纹**：修改 Web 服务器（Nginx/Apache）响应头，关闭 Server 详细版本号显示，避免泄露内部技术栈细节。')
      ..writeln()
      ..writeln('#### 3. 复测验证')
      ..writeln('- 对目标资产重新执行全端口与服务探测，确认敏感端点已妥善收敛。');

    return buffer.toString();
  }

  /// 为当前会话的全部发现物生成全量加固汇总报告（离线模式）。
  static String buildBatchSummary({
    required String sessionName,
    required List<PentestFinding> findings,
    required List<PentestAsset> assets,
  }) {
    final buffer = StringBuffer()
      ..writeln('# 《系统安全基线排查与漏洞加固全量处置清单》')
      ..writeln('**会话名称**：`$sessionName`')
      ..writeln('**关联资产**：`${assets.length}` 个')
      ..writeln('**检测到脆弱项**：`${findings.length}` 项')
      ..writeln();

    final criticals = findings.where((f) => f.severityLevel == Severity.critical).toList();
    final highs = findings.where((f) => f.severityLevel == Severity.high).toList();
    final mediums = findings.where((f) => f.severityLevel == Severity.medium).toList();
    final others = findings.where((f) => f.severityLevel == Severity.low || f.severityLevel == Severity.info).toList();

    buffer
      ..writeln('## 一、 风险态势摘要')
      ..writeln('- 🔴 **严重风险 (Critical)**：`${criticals.length}` 项（建议 24 小时内完成紧急收敛与加固）')
      ..writeln('- 🟠 **高危风险 (High)**：`${highs.length}` 项（建议 3 个工作日内完成补丁升级）')
      ..writeln('- 🟡 **中危风险 (Medium)**：`${mediums.length}` 项（建议纳入下个版本迭代修复）')
      ..writeln('- 🔵 **低危/信息 (Low/Info)**：`${others.length}` 项（建议纳入常规安全基线巡检）')
      ..writeln();

    // 聚合共性漏洞
    final grouped = <String, List<PentestFinding>>{};
    for (final f in findings) {
      grouped.putIfAbsent(f.title, () => []).add(f);
    }

    buffer.writeln('## 二、 关键共性脆弱点与收敛建议');

    var index = 1;
    for (final entry in grouped.entries) {
      final name = entry.key;
      final items = entry.value;
      final topSev = items.map((i) => i.severityLevel).reduce(
        (a, b) => Severity.ordered.indexOf(a) < Severity.ordered.indexOf(b) ? a : b,
      );

      buffer
        ..writeln('### $index. $name【${topSev.label}，影响 ${items.length} 个目标】')
        ..writeln('- **涉及资产**：${items.map((i) => i.assetId != null ? '资产#${i.assetId}' : '目标').toSet().join('、')}')
        ..writeln('- **处置建议**：');

      final lower = name.toLowerCase();
      if (lower.contains('ssh')) {
        buffer.writeln('  配置云防火墙收敛 22 端口仅对特定白名单开放；关闭密码登录，强制使用 SSH 密钥认证。');
      } else if (lower.contains('sql') || items.any((i) => i.source == FindingSource.sqlmap)) {
        buffer.writeln('  在应用网关启用 SQL 注入 WAF 拦截规则，代码层重构为参数化预编译查询，降低 DB 账号权限。');
      } else if (items.any((i) => i.cveId != null)) {
        final cve = items.firstWhere((i) => i.cveId != null).cveId;
        buffer.writeln('  针对已知漏洞 $cve，建议跟进组件官方补丁，升级至安全稳定版本或在反向代理层阻断攻击特征路径。');
      } else {
        buffer.writeln('  核查暴露端口必要性，收敛内网服务，强化身份鉴别与访问控制策略。');
      }
      buffer.writeln();
      index++;
    }

    buffer
      ..writeln('## 三、 持续安全防御建议')
      ..writeln('1. **网络边界收敛**：实行公网“零暴露”原则，所有内部管理类后台与运维管理端口禁止裸连外网。')
      ..writeln('2. **漏洞生命周期跟踪**：在管理面板中将已验证完成整改的项标记为“已整改”，定期复测确保防御措施持续有效。')
      ..writeln('3. **日志与监控联动**：对关键主机的异常登录、高频 Web 探测日志开启告警告警联动，提升威胁发现时效。');

    return buffer.toString();
  }
}
