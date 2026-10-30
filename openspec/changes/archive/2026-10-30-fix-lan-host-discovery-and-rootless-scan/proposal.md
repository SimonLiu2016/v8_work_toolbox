## Why

在没有 root 权限的桌面运行环境中，“安全工具箱”的局域网侦察功能因底层依赖 `arp-scan`（访问 `/dev/bpf` 权限被拒）及 `nmap -sn -PR`（非 root 静默退化为仅针对 80/443 的 TCP Connect 探测），导致未开放 Web 服务的局域网终端（如手机、平板、静默防火墙主机）被系统误判为离线，主机发现阶段仅能扫描到本机，造成局域网全端口及深度扫描严重漏扫。

## What Changes

- **新增免 Root 的全网段存活发现流水线**：使用应用层无害并发 UDP 数据包（广播与目标端口扇出）激发系统内核链路层发送真正的硬件 ARP 请求，迫使子网内全部在线设备硬件应答并刷新操作系统 ARP 缓存。
- **解析系统原生 ARP 表（`arp -a` / `arp -an`）**：在无特权环境下直接读取系统内核 ARP 缓存，精准提取当前网段内所有在线设备的真实 IP、MAC 地址，并自动进行 OUI 厂商名称匹配。
- **重构 `ArpScanService` 探测降级逻辑**：
  1. 优先执行免 Root 的内核 ARP 激发与系统缓存提取，保障 100% 存活设备发现；
  2. 若用户环境具备特权或装有特权 helper，才按需尝试 `arp-scan`；
  3. 保留多端口/多协议探测组合（TCP 多端口 + UDP 端口）作为补充发现；
  4. 修复原 `arp-scan` 参数拼写错误（`--local` 改为 `--localnet` 并指定网卡）。
- **完善扫描日志与错误透明度**：在日志面板清晰展示存活主机发现机制、已识别到的 IP 与 MAC 厂商，严禁静默吞掉底层命令的错误输出。

## Capabilities

### New Capabilities
- `security/lan-recon-discovery`: 局域网存活主机发现与免特权 ARP 识别能力，确保桌面应用在非 root 权限下快速、完整识别局域网内所有在线终端、网关与 MAC/厂商信息。

### Modified Capabilities
<!-- 无已有 spec 修改 -->

## Impact

- **Affected code**:
  - `lib/tools/security_toolbox/services/lan_recon_services.dart`: 重构 `ArpScanService`，增加 UDP 激发与系统 `arp -a` 解析，更新 `NetworkInterfaceDetector`；
  - `lib/tools/security_toolbox/ui/lan_recon_view.dart`: 扫描日志与设备呈现优化；
  - `lib/tools/security_toolbox/services/security_pipeline_service.dart`: 局域网流水线阶段 1 复用新的存活发现逻辑；
  - `test/security_toolbox_test.dart` / 新增单元测试：覆盖系统 ARP 输出解析与存活探测用例。
- **Dependencies**: 无新增外部第三方依赖，复用现有 Dart 网络套接字与进程工具。
