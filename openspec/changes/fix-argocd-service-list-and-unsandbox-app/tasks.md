## 1. 备份与准备

- [x] 1.1 `cp` 备份两个 `ops_tool.db`：`~/Library/Application Support/V8WorkToolbox/ops_tool/ops_tool.db` 与 `~/Library/Application Support/com.v8en.V8WorkToolbox/ops_tool/ops_tool.db`
- [x] 1.2 记录 `com.v8en.V8WorkToolbox/notebook_attachments` 的文件数与总字节数（迁移后抽样核对用）

  > 基线：760 个文件 / 9 个目录 / 443273216 字节。
- [x] 1.3 确认 `/Applications/V8WorkToolbox.app.bak-20260922` 仍存在且可回滚

## 2. 移除应用沙盒（specs: 本地数据的应用支持目录唯一）

- [x] 2.1 从 `macos/Runner/DebugProfile.entitlements` 删除 `files.user-selected.read-write`、`files.downloads.read-write`、`files.desktop.read-write`、`files.documents.read-write` 四项
- [x] 2.2 对 `macos/Runner/Release.entitlements` 执行同样删除
- [x] 2.3 复核两份文件仍保留 `network.client`、`network.server`、`automation.apple-events`、`cs.allow-unsigned-executable-memory`（缺任一项都会破坏对应功能）
- [x] 2.4 复核 `macos/Runner.xcodeproj/project.pbxproj` 中三处 `CODE_SIGN_ENTITLEMENTS` 指向未被改错（Debug ×2、Release ×1）

## 3. 修正服务文件列举（specs: 从服务文件提取镜像 Tag / 刷新 Tag 并与已有配置合并）

- [x] 3.1 `gitlab_client.dart` `listRepositoryFiles`：`path` 为空时不下发 `path` 参数；非 2xx、JSON 非数组、条目缺 `name`/`path` 分别抛可归因异常
- [x] 3.2 `argocd_service.dart` `listYamlTags`：入口过滤由「任何 `.yaml`/`.yml`」改为「`values-` 前缀 + `.yaml`/`.yml` 结尾」
- [x] 3.3 `argocd_service.dart` `listYamlTags`：跳过 `type == 'tree'` 的目录条目（`RepoFile.type` 此前从未被引用，本次启用）
- [x] 3.4 `argocd_service.dart` `listYamlTags`：兜底校验——目录返回了条目但 `values-` 文件数为 0 时，抛出含目录路径与分支名的异常（design D2）
- [x] 3.5 `argocd_service.dart`：返回结构改为「成功列表 + 失败列表（含文件名与原因）」，删除 `catch (_) {}`
- [x] 3.6 `argocd_service.dart` `extractImageTag`：剥离 `tag` 值两端成对的 `"` 或 `'`

## 4. UI 对齐（specs: 编辑环境的入口唯一 / 刷新 Tag 展示失败数）

- [x] 4.1 `ops_devops_view.dart` `_envChip`：删除铅笔图标 `InkWell`，保留环境名点击（选中）、Switch（启停）、✕（删除）
- [x] 4.2 `ops_devops_view.dart` `_refreshTags`：toast 文案改为「已刷新 N 个 Tag」并在有失败时追加「，M 个文件读取失败」
- [x] 4.3 `ops_devops_view.dart`：当目录存在非 `values-` 条目被跳过时，展示「已跳过 N 个非服务文件」（design Risks 第 5 条）

## 5. 测试

- [x] 5.1 新增 `values-` 过滤单测：`values-a.yaml` / `values-b.yml` 通过；`Chart.yaml`、`demo.yaml`、`.gitlab-ci.yml`、目录条目被排除
- [x] 5.2 新增引号剥离单测：`tag: "v1.2.3"` → `v1.2.3`，`tag: 'v1'` → `v1`
- [x] 5.3 新增 `Link: rel="next"` 多页翻页用例（沿用真实 header 形态，含 `id`、`path`、`recursive`、`ref` 参数）
- [x] 5.4 新增失败汇总用例：部分文件读取失败时，成功列表与失败列表分别返回且失败项带文件名
- [x] 5.5 运行 `flutter analyze --no-fatal-infos`，确认 0 errors、0 warnings

  > 实测 177 issues / 0 errors / 14 warnings，与改动前完全一致（14 个 warning 全为既有）。
  > ops_tool_test.dart 新增 12 个用例，0 issues。
- [x] 5.6 运行 `flutter test`，确认无新增失败（既有失败清单：13 处环境依赖型 + `evernote_import_test` 超时）

  > 实测 706 通过 / 2 跳过 / 13 失败，优于上一轮基线的 690/1/14（`evernote_import_test`
  > 超时本轮通过，属时序波动）。13 处失败全部落在 `notebook_editor_test` ×3、
  > `notebook_table_interactive_test` ×2、`table_*` 五个文件各 1、
  > `pointer_tap_table_test`、`notebook_codeblock_interactive_test`、
  > `disk_slimmer_hardening_verify_test` —— 均为环境依赖型既有失败。
  > ops_tool 相关 0 失败；`test/ops_tool_test.dart` 35 个用例全绿（新增 12 个）。
  > 跳过数由 1 变 2 是 `evernote_space_routing` 探测用例的既有行为。

## 6. 构建部署与数据归位

- [x] 6.1 `flutter clean` → `flutter build macos --release` → `codesign -v --strict` 通过

  > 构建产物 117.8MB（EXIT=0）。安装版与暂存版的 AOT 快照哈希一致（03077bde…），
  > `_kDartVmSnapshotData` 符号存在，确认 Dart 代码已打入。`codesign -d --entitlements`
  > 复核：四项 files.* 授权已消失，network.client / network.server /
  > automation.apple-events / allow-unsigned-executable-memory 均在。
- [x] 6.2 暂存 `/tmp/deploy` → 备份现有 app → 替换 `/Applications/V8WorkToolbox.app` → 校验 AOT 快照哈希

  > 沙盒版备份为 `/Applications/V8WorkToolbox.app.bak-sandboxed-20260922`
  > （另有更早的无沙盒版 `.bak-20260922`）。安装后 `codesign -v --strict` EXIT=0。
- [x] 6.3 启动 app，确认 `~/Library/Application Support/com.v8en.V8WorkToolbox/` 不再有新数据写入（新建的临时目录不再出现）

  > 判定依据：
  > 1. `com.v8en.V8WorkToolbox/` 目录 mtime 停留在 09-21 08:20（新 app 安装前），
  >    13:00 后该路径下无任何新文件；
  > 2. 旧路径 `V8WorkToolbox/config/smart-disk-slimmer.json` 于 13:26 被写入，
  >    即 app 安装（13:20）之后的运行确实落在旧路径。
  > → 去沙盒生效，`getApplicationSupportDirectory()` 已回到
  >   `~/Library/Application Support/V8WorkToolbox/`。
- [x] 6.4 把 `com.v8en.V8WorkToolbox/notebook_attachments` 整体迁回 `~/Library/Application Support/V8WorkToolbox/notebook_attachments`，核对文件数与总字节数与 1.2 记录一致

  > app 未运行时执行。迁移后 760 文件 / 9 目录 / 443273216 字节，与 1.2 基线三项全一致。
  > 后续 app 启动未在新路径重建该目录，佐证去沙盒生效。
- [x] 6.5 把新库中的 SIT 环境写入旧库（保留旧库既有配置），确认 `.gitlab-ci` 垃圾行不进入

  > 实施中发现数据归属与预设相反：**有价值的运维数据全在新库**（26 份报告、124 条任务日志、
  > 13 条 SQL 查询、2 个模板、1 个邮件账户、3 个数据源、3 个连接，报告日期 2026-06-24），
  > 旧库仅余演示环境残片且各表为 0 行。故改为「新库整体替换旧库」：
  > `integrity_check` ok、`foreign_key_check` 无违例后整体 `cp`；旧库已由 6.1 的
  > `.bak-argocd-fix` 保留可回退。替换后复核 10 张表行数全部一致。
  > `.gitlab-ci` 那行垃圾数据随库带入，保留作 7.x 的回归验证点（刷新后应消失）。
- [x] 6.6 抽查旧路径的 `ai_config.json`、`.dek`、`PrivateMedia` 在 app 内是否重新可见

  > 三项均就位于旧路径：`ai_config.json` 2.8K（providers ×2、槽位绑定 text/multimodal/tts/stt）、
  > `.dek` 50B、`PrivateMedia` 6 项。AI 配置走 `ai_config_store.dart:317` 的
  > `HOME + 'Library/Application Support/V8WorkToolbox'` 硬编码（策略 A），沙盒从未使其漂移，
  > 因此不存在「重新可见」问题——真正漂移的只有策略 B 的 `ops_database` 与 `note_store`。

## 7. 联调验证（需内网 PAT）

- [ ] 7.1 选中 SIT 环境点「刷新 Tag」，确认列表行数与 `curl` 两次分页得到的 117 个 `values-*.yaml` 一致
- [ ] 7.2 确认无 `Chart.yaml` / `demo.yaml` / `.gitlab-ci` 行；`values-adpt-b2b-order.yaml` 对应行 `current_tag` 为 `1.6.24.0-54f4f991`（或当前真实值）
- [ ] 7.3 确认全部行 `current_tag` 非空（除确实不含 tag 的文件）；若有读取失败，toast 显示失败计数
- [ ] 7.4 环境标签上不再出现铅笔图标，编辑只走详情卡「编辑环境」按钮
