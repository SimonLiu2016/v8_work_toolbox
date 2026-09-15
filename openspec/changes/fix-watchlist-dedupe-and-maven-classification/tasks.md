## 1. 核心实现

- [x] 1.1 `slimmer_models.dart`：`ProjectTechStack` 枚举新增 `maven('Maven / Java', 'pom.xml', 'target', 'build')`，置于 `gradleAndroid` 与 `other` 之间
- [x] 1.2 `project_artifact_detector.dart` `_detectTechStack`：新增 `pom.xml` → `maven` 分支，置于 flutterDart 之后、node 之前
- [x] 1.3 `project_artifact_detector.dart` `discoverProjectRoots`：watchlist 与自然根改交集语义——watchlist 条目仅在其下无任何自然根时才加入，有子则弃父
- [x] 1.4 `settings_store.dart` `_inheritCleanBuildsConfigIfNeeded`：移除"承接键为空"守卫，`extraRoots` 与 `artifactOptions` 改无条件并集（按值去重）；`slimmerInheritedFromCleanBuilds` flag 收窄为一次性提示标志，不再作门闸

## 2. 测试

- [x] 2.1 Tier A：watchlist 宽容器条目（其下含自然根）被弃父，自然根全部保留
- [x] 2.2 Tier A：watchlist 条目其下无任何自然根时，自身作为根加入（逃生口语义）
- [x] 2.3 Tier A：watchlist 条目本身就是自然根时，等价不重复
- [x] 2.4 Tier B 技术栈：含 `pom.xml` 的根归类为 `maven`
- [x] 2.5 Tier B 技术栈：含 `build.gradle` 与 `pom.xml` 的根归 `gradleAndroid`（优先级）
- [x] 2.6 Tier B 技术栈：无 manifest 信号的根归 `other` 兜底组（既有行为回归）
- [x] 2.7 配置继承：承接键为空时并入被移除工具的根（既有行为回归）
- [x] 2.8 配置继承：承接键非空时仍并入被移除工具的根，用户既有条目保留
- [x] 2.9 配置继承：flag 已置位时仍补齐（自愈），幂等——重复读取不产生重复条目
- [x] 2.10 配置继承：`artifactOptions` 并集语义（用户既有开关保留，被移除工具的开关并入）
- [x] 2.11 配置继承：被移除工具的原配置文件保持原样不被删除
- [x] 2.12 跑通既有测试（project_artifact_detector_test / settings_store / disk_slimmer / disk_slimmer_hardening_verify），确认无回归
- [x] 2.13 本机实测（真实配置）。修复前基线 553 根（watchlist 吞根后）；修复后：**自然发现 782 根，加 watchlist 后 783 根**。`extraRoots` 从 1 条（`~/Workspace`）补回至 **13 条**（12 个旧根 + 原条目）。13 条中 12 条被交集丢弃（均含自然子根），仅 `~/Workspace/pythonProject` 保留为根。`~/Workspace` 不再为条目。`dc-promotion`（depth 4）命中确认。
- [x] 2.14 本机实测（design D4 待验证项）。唯一符合"无自然子根"的条目 `~/Workspace/pythonProject` 作为单根保留，Tier B **45ms、0 个候选条目**（该树仅 14M、无产物目录名命中）。**结论：D4 的"宽容器根必然超时"推断不成立**——是否触发 `incomplete` 取决于树体积与命中数，小容器根极快完成且产出空。D4 应理解为防御性说明而非可依赖的兜底。

## 3. 部署与验证

- [x] 3.1 `flutter build macos --release`（110M）。**必须 `flutter clean` 后构建**：增量构建会留下失效的框架 seal（`codesign -v --strict` 报 "nested code is modified or invalid"），导致 macOS 拒绝该二进制访问 Keychain（部署 0563bfe5 前置事故，见 3.6）。
- [x] 3.2 替换 `/Applications/V8WorkToolbox.app`（先 SIGTERM 退出运行中的实例，再 `rm -rf` + `mv`，替换后校验 **Dart AOT 快照** `Contents/Frameworks/App.framework/Versions/A/App` 哈希与构建产物一致，`Maven / Java` 标签存在，终端启动验证无异常）

  **踩坑记录**：不能用 `Contents/MacOS/V8WorkToolbox` 的可执行文件哈希判断新旧——它是瘦启动器，跨构建不变（`e4fd7c38…` 恒定）。真正的应用代码在 AOT 快照里。此前曾以可执行文件哈希判定"已部署新版"，结论错误。另外 `/tmp` 是 `/private/tmp` 的符号链接，首次 `cp` 到 `/tmp/deploy` 时因大写路径残留导致暂存失败、`/Applications` 未真正替换。
- [ ] 3.3 真机验证：Maven / Java 组在技术栈筛选 chip 与分组列表中可见且非空（代码路径已单测覆盖，UI 呈现需用户打开 App 跑一次扫描确认）
- [ ] 3.4 真机验证：`~/Workspace` 不再作为单一条目出现，其下子项目各自成条目
- [x] 3.5 真机验证：`extraRoots` 中 12 个旧根已补回配置。读 `~/Library/Application Support/V8WorkToolbox/config/smart-disk-slimmer.json` 确认共 13 条（原 `~/Workspace` + 12 个旧根：`ctf-gitlab`、`github`、`gitee`、`vsProject`、`Livespace`、`flink_space`、`devops`、`zeebe`、`pythonProject`、`cae`、`PycharmProjects`、`ClaudeWorkspace`）。自愈生效，用户无需手工修复。
- [x] 3.6 **部署事故记录（黑屏）**：增量构建产物签名 seal 失效 → macOS 拒绝 Keychain 访问 → `getOrCreateDek` 走文件兜底生成新 K2 → 旧 `.secrets.bin`（K1 加密）解密认证失败 → `main.dart` 中 `PrivacySecurityService.init()` 无守卫 → 启动即抛未捕获异常 → 黑屏。处置：`flutter clean` 重建（签名恢复 valid）；`.secrets.bin` 手工隔离为 `.secrets.bin.corrupt-K1-20260915-104205` 留证（内含 PIN 哈希/盐/自动锁定设置，无密码数据，`.vault.bin` 不存在）；`main.dart` 为该 init 加 try/catch 守卫（服务保持锁定语义，不违反 fail-fast 契约）。恢复路径：用户重设 PIN，或将来找回 K1 后走「设置 → DEK 备份恢复」。

## 4. 归档

- [ ] 4.1 按依赖序归档三个变更：`openspec archive merge-clean-builds-into-slimmer -y` → `openspec archive fix-tier-a-discovery -y` → `openspec archive fix-watchlist-dedupe-and-maven-classification -y`
- [ ] 4.2 归档后 `openspec validate` 与 `git diff openspec/specs/` 复核合并结果与预期一致（三条需求内容无丢失、无被覆盖）
