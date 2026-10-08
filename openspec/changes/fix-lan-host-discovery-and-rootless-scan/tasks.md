## 1. UDP 激发与系统 ARP 缓存提取核心服务

- [x] 1.1 在 `lan_recon_services.dart` 中实现基于 Dart `RawDatagramSocket` 的并发 UDP 探针激发函数，向指定 CIDR 扇出无害探针迫使内核发送硬件 ARP
- [x] 1.2 在 `lan_recon_services.dart` 中实现系统 `arp -a` / `arp -an` 输出解析函数，支持精准提取 IP、MAC 地址并过滤 `incomplete` 与广播条目
- [x] 1.3 扩展 MAC 地址 OUI 厂商推断逻辑（支持 Apple、华为、小米、TP-Link、Intel 等常见厂商前缀识别）
- [x] 1.4 重构 `ArpScanService.scan`，形成「UDP 激发 + 系统 ARP 缓存提取」优先、nmap 多端口 Ping 补充的免特权高可靠发现流水线

## 2. 界面与流水线整合

- [x] 2.1 优化 `lan_recon_view.dart` 中的扫描日志与阶段状态，透明展示每台设备的 IP 与识别到的 MAC/厂商信息
- [x] 2.2 确保 `SecurityPipelineService.runLanPipeline` 阶段 1 复用新的 `ArpScanService.scan` 实现

## 3. 单元测试与端到端验证

- [x] 3.1 编写针对 `arp -a` 输出解析与 CIDR 匹配过滤的单元测试
- [x] 3.2 运行自动化测试，验证当前真实 WiFi 环境下 192.168.1.0/24 能稳定发现全部在线设备
