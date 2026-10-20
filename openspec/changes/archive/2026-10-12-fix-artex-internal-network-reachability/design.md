## Context

动机见 proposal.md 的 Why。这里只记录塑造实现的既有状态与约束。

**Docker Desktop 网络拓扑（2026-10-12 实测）**：

| 事实 | 来源 |
|---|---|
| `--network host` 的容器共享的是 `docker-desktop` Linux VM 的 netns，不是 macOS 的 | 容器内 `cat /proc/sys/kernel/hostname` → `docker-desktop` |
| host-net 容器绑 `:8787` 后，macOS `127.0.0.1:8787` 不可达，`192.168.64.2:8787`（VM eth1）可达 | `curl` + `lsof` 实测 |
| macOS 的 `en0` 是 `192.168.1.3/24`，Docker VM 的 eth0/eth1 是 `192.168.65.3` / `192.168.64.2` | `ifconfig` + 容器内 `ip -o addr` |
| compose 遇 `network_mode: host` 时丢弃全部已发布端口并打警告 | `docker compose up` 实测 |
| host-net 下 compose 服务名 DNS 失效（`nslookup pg` → NXDOMAIN） | 实测 |
| bridge 容器分到 `172.17.0.x`，内网目标机（`192.168.1.x`）路由不到 | 容器内 `ip route` + `docker inspect` |

**ARTEX 隧道侧已确认的事实**（来自 artex 仓库源码阅读）：

| 事实 | 来源 |
|---|---|
| 隧道池默认 `20000-21000`，每条隧道消耗 2 个端口（chisel server 回连口 + socks/forward 入口） | `config/config.go:213`、`tunnel/plan.go:102,159` |
| chisel server 绑 `0.0.0.0:<listenPort>`（`ListenHost` 空则填 `0.0.0.0`） | `tunnel/plan.go:98-100` |
| 目标机回连地址 = `CallbackHost:listenPort`，`CallbackHost` 来自 `ARTEX_CALLBACK_ADDR` 的 host 部分 | `tunnel/plan.go:118`、`server/tunnel.go:239` |
| `ARTEX_CALLBACK_ADDR` 未设置时 `tunnel_deploy` 直接报错要求配置 | `server/tunnel.go:73-83` |
| `CanListen` 在容器内 `net.Listen("0.0.0.0:port)` 试绑——容器内 netns 独立，宿主机侧的 DNAT 发布不影响它 | `tunnel/deploy.go:137` |
| 端口分配失败时报「端口池 N-M 无可用端口」 | `tunnel/tunnel.go:51-62` |

**端口发布的代价（实测，`docker compose up -d`）**：

| 发布范围 | 端口数 | 耗时 |
|---|---|---|
| 20000-20100 | 101 | 3 秒 |
| 20000-21000 | 1001 | 41 秒 |

**发布绑定到指定 IP 的行为（实测）**：`"192.168.1.3:20005:20005"` 让监听只出现在 `192.168.1.3`，`127.0.0.1` 与 vmnet 接口上不可见（`lsof` 确认）；容器内绑 `0.0.0.0` 的服务仍能正常收到经 DNAT 转发的流量。

**本项目既有可复用件**：

- `ArtexOverrideStore` 已实现「标记注释识别 + 非托管文件备份 + 原子重写」，且 `ports: !override` 的追加合并问题已在注释里记录原因（design D1）。
- `ArtexComposeService.findConflictingPort` 已实现 `ServerSocket.bind` 预检模式，本次只是扩列表。
- `NetworkInterfaceDetector`（`lib/tools/security_toolbox/services/lan_recon_services.dart:40-64`）提供了 macOS `ifconfig` 解析的完整先例：过滤 `lo0`、判 `<UP`、提取 `inet` 与 netmask、失败回退 `ip -o -4 addr`。
- 应用未启用 App Sandbox，`Process.start('ifconfig')` 可用。
- `SettingsStore.readToolConfig/writeToolConfig` 是工具级配置的标准存放处。

**关键约束**：不引入任何新 pubspec 依赖。不跨工具 import（`artex_engine` 目前对 `security_toolbox` 零依赖，保持这个边界）。

## Goals / Non-Goals

**Goals:**
- 让内网目标机能回连到平台，且不牺牲本机对 8787 的访问。
- 让回连地址自动探测对，用户不需要懂网络。
- 让启动耗时不因端口发布明显变长。

**Non-Goals:**
- 不用 `--net=host`（spike 已证伪，见 Context）。
- 不做端口池的动态发布/回收（按需重载 compose）。
- 不自动投递 chisel / suo5 二进制。
- 不改 ARTEX 仓库的 `docker-compose.yml`。
- 不做「内网目标机回连成功」的端到端验证——那需要一台真实的第二台机器，超出本工具可自动化验证的范围。spec 的验收标准到「端口已发布 + 地址已注入」为止。

## Decisions

### D1: 发布端口池，不改网络模式

**选择**：保持 bridge 网络，在 override 的 `ports` 段追加隧道池的发布条目。

**为什么不用 `--net=host`**：spike 已实测它是 Desktop 虚拟化下的陷阱——共享的是 VM netns，导致 8787 对 macOS 不可见、健康探测必然超时、端口预检误判空闲、compose 服务名 DNS 失效、pg 的 5432 与本机冲突。它换来的是「VM 的 IP 可达」，而那个 IP 是 Docker Desktop 分配的，不稳定也不可读。

**为什么发布端口池就能解决**：ARTEX 的目标机回连走 `CallbackHost:listenPort`，`CallbackHost` 由我们注入。把 `listenPort` 所在的池通过 DNAT 发布到 macOS 的 en0 IP，目标机连 `192.168.1.3:<port>` 就能到容器内的 chisel server。实测这条链路通了。

**备选**：
- `--net=host` — 已否（上面）。
- 只发布部分端口（比如前 20 个）— 会与池语义不一致，用户建第 21 条隧道时静默失败。否。
- 用 `socat`/用户态代理在宿主机转发 — 引入新进程与新的生命周期管理，比 compose 原生机制复杂。否。

### D2: 默认池缩窄到 20000-20099，与发布范围严格一致

**选择**：工具侧默认池 = 20000-20099，同时通过 `ARTEX_TUNNEL_PORT_RANGE` 覆盖上游默认值，并发布同一范围。

**为什么必须两者一致**：池决定 ARTEX 分配哪些端口，发布决定哪些端口有 NAT。若池宽于发布，ARTEX 会分配到没有 NAT 的端口，目标机回连静默失败。若发布宽于池，白占监听。所以 override 必须同时注入 `ARTEX_TUNNEL_PORT_RANGE` 与对应的 `ports` 条目，两者从同一份配置渲染。

**为什么是 100**：单人场景。实测 101 个端口发布耗时 3 秒，1001 个 41 秒。100 个端口 = 50 条隧道（每条 2 端口），单人远够。池的起止端口可配置，用户嫌窄可以自己放宽——但要自己承担启动耗时。

**备选**：
- 保持上游 20000-21000 全量发布 — 启动 41 秒，单人用不上 500 条隧道。否。
- 缩到 20 个端口（10 条隧道）— 单人也许够，但一次多任务扫描可能同时开多条。100 是保守值。否。

### D3: 回连地址 = 探测物理网卡 IPv4，可手动覆盖

**选择**：启动时跑 `ifconfig`，过滤 `lo0` 与虚拟接口（`utun*`/`bridge*`/`vmenet*`/`awdl*`/`llw*`/`gif*`/`stf*`/`ap1`），取 UP 且有 IPv4 的物理网卡（`en*`）。多候选时让用户选并记住；用户可在 UI 填死一个地址，填死后不再自动覆盖。

**为什么要过滤虚拟接口**：本机实测有 `utun0-4`、`utun88`、`bridge0`、`bridge100`、`awdl0`、`llw0`、`vmenet0`、`ap1`、`en5`、`en0`。其中 `utun88` 是 `198.18.0.1`（TUN 模式虚拟网关），`bridge100` 是 `192.168.64.1`（Docker 的 vmnet 网桥）——拿它们当回连地址，内网目标机连不进来。`en0`（`192.168.1.3`）才是真的 LAN 地址。

**为什么手动覆盖优先于探测**：DHCP 换 IP、多网卡切换、VPN 场景下探测可能选错。用户最清楚该填什么。

**备选**：
- 用 `NetworkInterface.list`（dart:io）— 也能列接口，但拿不到「物理 vs 虚拟」的区分信息（macOS 上 `NetworkInterface.name` 只是 `en0`/`lo0` 这样的 BSD 名，没有 `utun88` 这种）。要区分虚拟接口仍得解析 `ifconfig` 的完整输出。且项目已有 `ifconfig` 解析先例。否。
- 写死 `192.168.1.3` — DHCP 会变，换网络环境失效。否。
- 每次启动都重新探测覆盖用户的手动值 — 用户填定就被抹掉，违背「可覆盖」。否。

### D4: 端口预检扩展到池边界与回连端口

**选择**：`findConflictingPort` 的入参从 `[httpPort, proxyPort]` 扩为 `[httpPort, proxyPort, poolMin, poolMax]`，再加上「回连地址端口」当它与上述不同时。

**为什么检池的两端就够**：预检的目的是在 `up -d` 之前给用户可读的失败原因，而不是穷举 100 个端口。池是连续范围，两端被占说明范围选得不对；中间被占则由 ARTEX 的 `CanListen` 在分配时自然跳过（它逐个试绑）。检两端能抓住「用户把池选成了与服务重叠的范围」这个真实错误。

**回连地址端口是什么**：`ARTEX_CALLBACK_ADDR` 的语义是 `host:port`（`server/tunnel.go:77` 支持 bare host，但 `net.SplitHostPort` 失败时按 bare host 处理）。如果用户填了带端口的形式，那个端口应当与池内端口一致才有意义；填不一致时预警但不阻断（ARTEX 只在 host 部分用它）。

### D5: override 的渲染顺序与 `!override` 语义

**选择**：`ports` 段保持单个 `!override` 列表，把 8787/8788 与池的 100 个条目放进同一个列表。`environment` 段追加 `ARTEX_CALLBACK_ADDR` 与 `ARTEX_TUNNEL_PORT_RANGE`。

**为什么放同一个 `ports` 列表**：compose 的 `!override` 标签作用于整个 `ports` key，拆分多个 key 会退化成追加合并，上游的 `"8787:8787"` 会回来——这正是既有代码注释里记录的坑。实测 `docker compose config` 确认：单列表 + `!override` 后，最终配置里只剩 override 定义的那些条目。

**为什么池的发布条目要逐个列出**：compose 支持 `"20000-20099:20000-20099"` 范围语法，实测可用（`docker port` 显示 2002 条映射）。但绑定到指定 IP 时范围语法是否保留 IP 绑定需要确认——实测 `"192.168.1.3:20010:20010"` 单端口是绑 IP 的，范围 + IP 的组合在 Context 的实测里用的是单端口。为稳妥，**池发布用范围语法并绑定 IP：`"<ip>:20000-20099:20000-20099"`**，这一条要在 task 里实测确认。

### D6: 不做 host-net，但保留一条诊断

**选择**：不改网络模式；但在启动失败分类里增加一条识别——如果 compose 输出里出现 `Published ports are discarded when using host network mode`（说明 override 或上游文件被加了 `network_mode: host`），给出定向提示。

**为什么**：这是用户第一直觉会做的事。与其只在文档里说「别这么干」，不如在他真这么干（或从网上抄了段配置）时给出可读的诊断。

## Risks / Trade-offs

**[端口范围 + 指定 IP 的组合未实测] → 先做验证再写实现。** Context 里实测的是单端口绑 IP（`192.168.1.3:20010:20010` → `lsof` 确认只绑该 IP）与范围不绑 IP（`20000-21000` → 2002 条映射全通）。范围 + IP 的组合（`192.168.1.3:20000-20099:20000-20099`）需在 task 1 实测；若不支持，退化为「范围绑 0.0.0.0」并接受暴露面扩大，或改成逐端口列出 100 条。

**[DHCP 换 IP 后回连地址过期] → 启动时重新探测并更新 override，UI 提示地址已变化需重启。** 用户手动填定的值不覆盖。spec 的「回连地址变化」场景覆盖这个提示。

**[macOS 上多开 100 个监听] → 绑定到探测到的回连 IP，不绑 `0.0.0.0`**，避免暴露给 vmnet/bridge 接口。已实测单端口绑 IP 有效。

**[用户把池范围改得与服务重叠] → 端口预检覆盖池两端**，启动前报出具体端口号。

**[与上游默认池不一致，绕过本工具直接 `docker compose up` 时隧道不可用] → 这是既有约束的延续**（容器生命周期本就由本工具管理）。override 文件带标记注释，用户能看到 `ARTEX_TUNNEL_PORT_RANGE` 是工具注入的。

**[100 个端口发布让 `up -d` 慢 3 秒] → 可接受**；但若用户把池放宽到 1000，启动 41 秒，需在 UI 上提示「范围越大启动越慢」。

**[探测选错网卡（多网卡/VPN 环境）] → 多候选时让用户选并记住，且 UI 可随时覆盖。** 不做「猜得最准」的启发式。

## Migration Plan

**升级**：已有用户在下次启动时会拿到新的 override 文件（工具重写，旧的被备份到 `AppPaths.artexDir`）。第一次启动时回连地址尚未探测过，走自动探测路径；探测到多候选则弹选择。

**回滚**：`ArtexOverrideStore.remove()` 删除工具生成的 override，容器回到上游 `docker-compose.yml` 的默认行为（8787/8788 发布、无回连地址、上游默认池）。已有的 `gateOff` / 端口配置随之失效，但引擎数据（pgdata 卷 + `./data`）不受影响。

**数据**：无 schema 变更。配置只是多了三个字段（回连地址可空、池起、池止），`fromJson` 缺省时回落到默认值，旧配置文件无需迁移。

## Open Questions

（无。范围 + IP 的发布语法已列入 task 1 作为首个验证项，不构成开放问题。）
