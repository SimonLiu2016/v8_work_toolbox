# 安全工具箱（security-toolbox）

渗透测试工作台：把 nmap / nuclei / metasploit 等 CLI 工具收进一个会话里，
AI 在各阶段提供分析、推荐与驱动能力。

**仅用于授权的安全测试。** 模块内的每次高影响操作（exploit、爆破、注入利用）
都会弹窗要求人工确认。

## 运行前提

工具链走 macOS 上的 Homebrew，GUI 应用默认 PATH 不含 `/opt/homebrew/bin`，
所以工具箱自己做了 PATH 加固（`security_process_runner.dart`）——
直接用 `Process.run('nmap')` 会稳定地 command not-found，而错误信息读起来像
"工具没装"。

```bash
# 最小可用集
brew install nmap nuclei

# 完整工具链（14 个受管工具）
brew install nmap arp-scan masscan nuclei subfinder httpx katana ffuf \
             sqlmap gau metasploit bettercap netexec exploitdb
```

安装后在工具箱的「工具依赖」Tab 点「重新检测」即可看到三态状态
（已就绪 / 需更新 / 未安装）。

## 两个需要手工处理的特权场景

1. **nmap 的 OS 指纹识别（`-O`）与部分扫描** 需要 root。工具箱不申请 `sudo`，
   需要时请在系统偏好设置里为 nmap 配置免密，或关闭「OS 指纹识别」开关——
   端口与服务识别不需要特权。
2. **msfrpcd** 由工具箱自行拉起（`msfrpcd -P <密码> -a 127.0.0.1 -p 55553 -S -f`），
   无需手工启动。

## 数据存放

全部落在 `<AppPaths.root>/security/`（与 AI 配置、密码库同根）：

| 文件 | 内容 |
| --- | --- |
| `security.db` | 会话 / 资产 / 发现物 / 时间线 / 情报缓存 / 报告版本（drift SQLite） |
| `script_templates.json` | 用户保存的脚本模板（内置模板在代码里） |

会话数据与会话数据共享同一个 SQLite **连接**——各仓储都从
`SecuritySessionController` 取句柄，不要另开 `SecurityDatabase()`，
两个连接的写入缓存会互相覆盖。

## 架构

```
security_toolbox/
  models/       领域对象 + 落库字符串常量（Severity / SessionType / …）
  database/     drift 表定义与生成代码
  services/     进程执行、工具状态、扫描服务、仓储、Agent、报告、脚本、情报
  ui/           主页面 + 各 Tab 视图 + 共享组件
```

设计取舍见 `openspec/changes/add-security-toolbox/design.md` 与
`openspec/changes/close-security-toolbox-gaps/design.md`：

- **直接 `Process.start()` 流式解析**，不包守护进程——nmap/nuclei 是一次性命令
- **`security.db` 独立于 `note.db`**：渗透会话的 Finding 量级远高于笔记
- **拓扑图用 CustomPainter 自绘**：节点数 < 50，星形布局一帧画完
- **Agent 的审批用 Completer 挂起循环**：白名单外的只读工具不问
- **Agent 的 executeTool 落在 `SecurityAgentExecutor`**（service 侧），
  每次调用都把结果写回资产/发现物/时间线，而不是只在日志里留一行
- **"生成 Finding" 而非全自动**：一次情报同步可能命中几十个资产，
  全自动会灌入几十条"待验证"

## Security Agent 的工具如何真正执行

`SecurityAgentService` 只做编排（审批闸门、步骤流、上下文拼装），不认识
数据库；`SecurityAgentExecutor`（`services/security_agent_executor.dart`）把它的
`executeTool` 回调落到具体服务上：

| 工具 | 落点 | 写回 |
| --- | --- | --- |
| `run_nmap` | `NmapService.scan` | 资产 upsert（含端口）+ 时间线 |
| `run_nuclei` | `NucleiService.scan` | Finding add（缺失 CVSS 时补查 NVD） |
| `run_subfinder` | `SubfinderService.run` | 资产 upsert |
| `run_httpx` | `HttpxService.run` | 资产 metadata 合并 |
| `run_ffuf` | `FfufService.run` | URL 追加至资产 |
| `run_sqlmap` | `SqlmapService.scan` | Finding add |
| `run_msf_module` | 审批后 `MsfRpcService` | 会话列表刷新 |
| `query_threat_intel` | `ThreatIntelRepository` | 只读 |
| `get_session_findings` | `controller.findingList` | 只读 |

返回给模型的文本统一截断到 500 字符——回灌文本越长，3 轮迭代越容易把 context
撑爆。工具未安装 / 未建会话时返回可操作的说明，模型据此改走别的路径。

## Shodan 与全局利用参数

两者都存 `config/security-toolbox.json`（`SettingsStore` 工具配置）：

- **Shodan Key**——UI 上以脱敏形式展示（仅末 4 位），可从 account.shodan.io
  轮换。资产行的「外部情报」按钮触发查询，结果经 `mergeShodan()` 合并进
  资产 metadata，不覆盖本地扫描得到的端口。
- **LHOST/LPORT**——从未配置时探测本机主网卡 IP（跳过 VPN 隧道段）+ 端口
  4444；确认对话框中高亮展示，因为填错的 LHOST 只在会话建立失败后才可见。
  它与 MSFRPC 的连接地址是两回事：一个面向被攻击目标，一个面向本地 RPC 服务。
