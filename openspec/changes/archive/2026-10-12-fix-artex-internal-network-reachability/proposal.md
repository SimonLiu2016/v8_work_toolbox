## Why

ARTEX 渗透引擎的内网渗透功能（隧道 / 反弹 shell）实际不可用。用户提出的修法是给容器加 `--net=host`，但 2026-10-12 的 spike 实测证明：Docker Desktop 的 `host` 网络是 **Linux VM 的 netns，不是 macOS 的 netns**，加上它之后 ARTEX 的 8787 端口会藏进 VM，导致本机健康探测必然超时、浏览器打不开工作台、端口预检误判空闲——把唯一可用的功能换成了不可用的功能。

真正的根因不是「用了默认网络」，而是**容器内 chisel server 绑在 `0.0.0.0:<pool>`，却没有 NAT 规则让内网目标机回连进来**。ARTEX 默认的 bridge 网络给容器分的是 `172.17.0.x`，内网目标机（`192.168.1.x`）根本路由不到；而 `ARTEX_CALLBACK_ADDR` 指向的又是 macOS 的 en0 地址，中间缺一段端口发布。

## What Changes

- **发布隧道端口池到宿主机**：override 增加 `ports` 条目，把 ARTEX 的隧道端口池（默认 20000-21000，可配置）发布出去，使内网目标机能回连到 macOS 的 en0 地址。**不用 `--net=host`**，bridge 网络保持不变。
- **缩窄默认端口池**：单人使用场景下 1001 个端口没有意义，且实测全量发布会让 `docker compose up -d` 从 3 秒变成 41 秒。默认池改为 20000-20099（100 个端口，约 50 条隧道），发布耗时约 3 秒，单人并发足够。
- **自动探测回连地址**：启动时探测宿主机活跃网卡的 IPv4 地址，写入 `ARTEX_CALLBACK_ADDR`；探测失败或用户需要覆盖时提供 UI 输入框。默认优先选择物理网卡（`en` 开头）而非虚拟网卡（`bridge`/`utun`/`vmenet`/`awdl`）。
- **回连地址纳入端口预检**：现有的 `findConflictingPort` 只覆盖 8787/8788，现在也要覆盖回连端口本身，以及缩窄后的隧道池两端。
- **端口池配置暴露到 UI**：隧道池的起止端口可配置（与 `ARTEX_TUNNEL_PORT_RANGE` 语义一致），持久化到工具配置。

**不做的事（Non-goals）**：
- 不给容器加 `--net=host`（spike 已证伪，见 design.md）。
- 不改造 ARTEX 仓库的 `docker-compose.yml`，仍然只通过 override 注入。
- 不自动投递 chisel / suo5 二进制到 `data/tools/`——那是独立的「内网隧道工具未预置」问题，spec 已另有一条「能力边界明示」覆盖，本次不改。
- 不做端口池的动态发布/回收（按需 `docker compose` 重载）。发布是启动时一次性完成的静态配置。

## Capabilities

### New Capabilities

（无。本次是对既有能力的缺口补齐，不引入新能力域。）

### Modified Capabilities

- `artex-engine`: 修改「端口分配与冲突预检」与「运行时配置以 override 注入而不修改上游工程文件」两条需求——端口预检的覆盖范围从 8787/8788 扩展到回连地址端口与隧道池；override 的职责从「关门控 + 覆盖端口」扩展为「关门控 + 覆盖端口 + 发布隧道池 + 注入回连地址」。同时修改「应用退出时的容器处置」不变，但「能力边界明示」中关于内网隧道的表述需要与实际可达性对齐。

## Impact

**新增代码**（约 250 Dart 行，零新依赖）：

```
lib/tools/artex_engine/
  models/artex_engine_config.dart        + 回连地址、隧道池起止端口字段
  services/artex_override_store.dart     + ports 段生成隧道池发布、environment 注入回调地址
  services/artex_callback_service.dart   新增：宿主机 IPv4 探测（复用 ifconfig 解析模式）
  services/artex_compose_service.dart    端口预检覆盖范围扩展
  ui/artex_engine_page.dart              + 回连地址输入框、隧道池输入框
```

**依赖的既有件**：
- `lib/tools/security_toolbox/services/lan_recon_services.dart` 的 `NetworkInterfaceDetector` 提供了 macOS `ifconfig` 解析的先例（过滤 loopback、判 UP、提取 IPv4）。本次**不跨工具 import**（artex_engine 目前对其他工具零依赖），而是在 artex 侧实现一个更小的探测函数，只取「第一个物理网卡的 IPv4」。
- `ArtexOverrideStore` 的 `!override` 标签机制继续复用（compose 对 `ports` 的默认合并行为是追加）。

**外部依赖**：Docker Desktop（已安装，29.8.2）；artex 仓库本地副本（`~/Workspace/github/artex-ymh`）。

**风险**：
- 回连地址依赖 DHCP：en0 的 IP 变化后需要重启引擎才能让目标机拿到新地址。UI 可覆盖，且启动时重新探测写 override。
- 端口池缩窄后与 ARTEX 上游默认值（20000-21000）不一致：如果用户绕过本工具直接 `docker compose up`，上游 compose 没有发布这些端口，隧道仍然不可用——但这本来就需要本工具，spec 中已明确「容器生命周期由本工具管理」。
- 发布 100 个端口会在 macOS 上开 100 个监听。已实测可指定绑定到 en0 IP（`192.168.1.3:20000-20099`），不暴露到 vmnet/bridge 接口。

**数据位置**：无新增持久化数据。回连地址与隧道池配置进 `SettingsStore` 的 `config/artex-engine.json`（既有位置）。
