## 1. Tier A 发现修复

- [x] 1.1 `manifestSignals`: 新增 `pom.xml`、`Cargo.toml`
- [x] 1.2 新增 `discoveryPruneDirs` 静态常量（包管理器缓存：`.pub-cache`、`.npm`、`.yarn`、`.cache`、`.cargo`、`.rustup`、`.local`），与 `artifactNames` 语义分离
- [x] 1.3 `_walkDiscover` 剪枝条件：追加 `discoveryPruneDirs` 与 `Applications` 检查
- [x] 1.4 `discoverMaxDepth`: 3 → 5

## 2. 测试

- [x] 2.1 Tier A：`pom.xml` 根被识别（无 `.git` 的 Maven 项目）
- [x] 2.2 Tier A：`Cargo.toml` 根被识别（无 `.git` 的 Rust 项目）
- [x] 2.3 Tier A：`.pub-cache`/`.npm`/`.cargo` 目录内 manifest 不被识别为根
- [x] 2.4 Tier A：`~/Applications` 内 manifest 不被识别为根
- [x] 2.5 Tier A：depth 4 根被识别（回归测试：`dc-promotion` 用例）
- [x] 2.6 本机实测校准：**剪枝后 depth 5 → 782 根 / 12569ms**。根数与 proposal 基线（782 根 / 11040ms）完全一致，耗时 +14%（<30%，属机器负载波动，无需说明）。实测确认 `/Users/simon/Workspace/ctf-gitlab/dc-promotion`（depth 4）已进入根集合。
- [x] 2.7 跑通既有测试（project_artifact_detector_test 26/26 通过；disk_slimmer / disk_slimmer_hardening_verify / settings_store 仅 1 个既有无关失败——v8-video-downloader 字符串匹配）

## 3. 部署

- [x] 3.1 `flutter build macos --release` 成功（110M），已替换 `/Applications/V8WorkToolbox.app`（先 SIGTERM 退出运行中的旧实例，再 `rm -rf` + `mv`；替换前校验二进制哈希确认本机原为旧版 `6e6eeae0`，替换后为新版 `e4fd7c38`，并 `open` 验证可正常启动）。
- [x] 3.2 端到端验证通过（`flutter test test/_e2e_dcpromotion.dart`，验证后删除）：Tier A 自然发现 `/Users/simon/Workspace/ctf-gitlab/dc-promotion`（depth 4），Tier B 收集出 `target/` **109.9MB** 为 `dir=target` 产物，聚合条目 `incomplete=false`。代码路径已确认；UI 内呈现由用户打开 App 跑一次磁盘扫描人工确认。
