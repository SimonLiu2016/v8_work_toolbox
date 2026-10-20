## 1. 前置验证（design D5 的未实测项）

- [x] 1.1 实测 `docker compose` 的端口范围 + 指定 IP 组合：写一个临时 compose 文件，ports 段用 `"192.168.1.3:20000-20099:20000-20099"`，`up -d` 后用 `docker port <container>` 确认映射条数、用 `lsof -iTCP:20005` 确认监听只绑在 `192.168.1.3`、用 `curl http://192.168.1.3:20005/` 确认可达。记录结论：支持 or 不支持
- [x] 1.2 若 1.1 不支持范围 + IP，实测退化方案：逐端口列出 100 条 `"192.168.1.3:200NN:200NN"`，确认同样可达并记录启动耗时。以 1.1/1.2 的结论定 override 的渲染形式

## 2. 配置模型扩展

- [x] 2.1 `ArtexEngineConfig` 增加三个字段：`callbackAddr`（`String?`，null = 自动探测）、`tunnelPortMin`（int，默认 20000）、`tunnelPortMax`（int，默认 20099）；补 `fromJson` 读取（含旧配置缺省回落）、`toJson`、`copyWith`
- [x] 2.2 补常量：`defaultTunnelPortMin = 20000`、`defaultTunnelPortMax = 20099`；写测试覆盖「旧配置文件无这三个 key 时读到默认值」「字符串形式的端口能解析」

## 3. 回连地址探测服务

- [x] 3.1 新建 `lib/tools/artex_engine/services/artex_callback_service.dart`：跑 `ifconfig`（失败回退 `ip -o -4 addr`，参照 `lan_recon_services.dart` 的解析模式），过滤 `lo0`/`lo` 与虚拟接口（`utun*`/`bridge*`/`vmenet*`/`awdl*`/`llw*`/`gif*`/`stf*`/`ap1`），只留 UP 且有 IPv4 的 `en*`
- [x] 3.2 提供 `Future<List<String>> detectCandidates()`（返回候选 IPv4 列表）与 `Future<String?>` 形式的单候选快捷路径；多候选时由调用方决定交互，服务本身不弹 UI
- [x] 3.3 写测试：喂 `ifconfig` 样本文本（含 `en0`/`en5`/`lo0`/`utun88`/`bridge100`/`awdl0`），断言只返回物理网卡地址；喂空文本与命令失败两种情况，断言返回空列表而非抛异常

## 4. Override 渲染

- [x] 4.1 `ArtexOverrideStore.render` 的 `ports` 段在同一个 `!override` 列表内追加隧道池发布条目（形式由 task 1 定），绑定到传入的回连 IP；`environment` 段追加 `ARTEX_CALLBACK_ADDR`（回连 IP，必要时带端口）与 `ARTEX_TUNNEL_PORT_RANGE`（`"min-max"`）
- [x] 4.2 `render` 签名扩展为接受回连地址与池范围（从 config 读，或显式传参以便测试）；保持 `gateOff` 与 8787/8788 逻辑不变
- [x] 4.3 更新文件头注释：把「两件事」改为「四件事」，并说明为什么池发布与池范围必须同源渲染（design D2）
- [x] 4.4 写测试：给定 config 与回连 IP，断言渲染结果含 `ARTEX_TUNNEL_PORT_RANGE: "20000-20099"`、含池发布条目且绑定正确 IP、`ports` 只有单个 `!override` 标签、8787/8788 条目仍在；断言 `ARTEX_CALLBACK_ADDR` 的端口部分（若带端口）与池一致

## 5. 启动流程接线

- [x] 5.1 `ArtexComposeService.start` 在端口预检前解析回连地址：用户填定则用之，否则调探测服务；单候选直接用，多候选时上报一类新失败（「需要用户选择回连地址」并附候选列表），无候选则上报失败
- [x] 5.2 `findConflictingPort` 的入参从 `[httpPort, proxyPort]` 扩为 `[httpPort, proxyPort, poolMin, poolMax]`；失败信息区分「引擎端口」与「隧道池端口」
- [x] 5.3 override 写入改用 task 5.1 解析出的回连地址，而不是写死 `127.0.0.1`
- [x] 5.4 启动失败分类增加一条：compose 输出含 `Published ports are discarded when using host network mode` 时，给出「不要用 host 网络模式」的定向提示（design D6）
- [x] 5.5 写测试：多候选时启动失败且状态里带候选列表；池边界被占时失败信息含具体端口号；用户填定回连地址时不再调用探测服务；compose 输出含 host-network 警告时归类为定向提示

## 6. UI

- [x] 6.1 `artex_engine_page.dart` 增加回连地址输入框：留空表示自动探测，显示当前探测值与候选；保存时写 config
- [x] 6.2 增加隧道池起止端口两个输入框，校验 `1 <= min <= max <= 65535` 且 `min != max` 无意义时提示；保存时写 config
- [x] 6.3 「能力边界明示」区块补充两条：内网隧道工具二进制需自行投递到 `data/tools/`；内网回连需要一个宿主机可路由的 IPv4，地址变化后需重启引擎
- [x] 6.4 探测到多候选时，在界面上呈现候选列表供选择（而不是只在启动失败时告知）；选中的值写回 config
- [x] 6.5 启动时发现回连地址与上次记录不同，界面提示新旧地址与「需重新启动引擎」

## 7. 回归与验证

- [x] 7.1 跑 `test/tools/artex_engine/` 全量测试，确认既有用例（override 生成、健康探测、端口预检、启停）不因签名变化而失败；签名变化的用例同步更新
- [x] 7.2 跑 `flutter analyze` 确认无新增告警
- [x] 7.3 真机验证（2026-10-12 已跑）：`docker port` 列出 102 条映射（8787/8788 绑 127.0.0.1 + 20000-20099 绑 192.168.1.3）；`lsof` 确认 20005/20099 只绑 192.168.1.3；`curl http://127.0.0.1:8787/api/health` 返回 `{"ok":true,"service":"artex"}`；容器内起监听后 `nc 192.168.1.3:20005` 通（DNAT 通路验证）。注：`curl 192.168.1.3:8787` 不通是**预期**——override 有意把工作台绑在 127.0.0.1，只有隧道池绑回连 IP
- [x] 7.4 真机验证（2026-10-12 已跑）：`printenv` 返回 `192.168.1.3` / `20000-20099` / `off`；引擎日志 `[tunnel] 多层代理隧道子系统已就绪（端口池 20000-20099）`、`[config] 回连地址(ARTEX_CALLBACK_ADDR): 192.168.1.3`；「未配置平台回连地址」出现 0 次
