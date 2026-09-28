## 1. 让列举请求可诊断（不依赖外部工具反推）

- [x] 1.1 `gitlab_client.dart` `listRepositoryFiles`：每次请求后以 `kDebugMode` 输出实际 URL、HTTP 状态码、本页条目数、`Link` 响应头原文
- [x] 1.2 同处输出是否发生 v4→v3 回退（打两条 URL 并标注哪个成功），不改变 `_getWithFallback` 签名
- [x] 1.3 `_headers()` 内容纳入日志（Key 名打全、Value 只打前 6 位 + 长度），用于比对 curl 与 app 的认证差异
- [x] 1.4 URL 构造后加 debug 自检：`path.isEmpty || url.contains('path=')`，不满足只 `debugPrint` 不抛

## 2. 兜底校验文案分情形（specs: 列举请求可诊断）

- [x] 2.1 `argocd_service.dart` `listYamlTags`：`ref.fileDir.isEmpty` 时文案为「未指定子目录，已列举仓库根目录且未找到服务文件」

  > 文案明确写出「这通常是请求构造问题而非配置问题」，避免再次把代码缺陷
  > 表述成用户配置错误（本次故障正是被旧文案误导）。
- [x] 2.2 `ref.fileDir.isNotEmpty` 时文案为「已限定子目录 <dir>（分支 <branch>）但未找到 values-*.yaml，请检查该目录下是否存在服务文件」

## 3. 锁定 PAT 语义

- [x] 3.1 `gitlab_client.dart` `login()`：`config.token` 非空时立即返回，不进入 session 端点循环
- [x] 3.2 新增单测：配置 token 的 client 调 `ensureToken()` 后 token 生效，且不触达任何 session 请求

  > 三条用例：token 直接生效；token 前后空白被 trim（否则 `PRIVATE-TOKEN` 头带
  > 空格会 401）；未配 PAT 且凭据为空时抛错并提示配置 PAT。为此在
  > `GitLabClient` 加了 `@visibleForTesting get debugToken`。

## 4. 定位根因并修复

- [x] 4.1 `flutter analyze --no-fatal-infos` 0 errors / 0 warnings；`flutter test` 无新增失败（既有 13 处环境依赖型）

  > analyze：176 issues / 0 errors / 14 warnings（14 个全为既有）。
  > 全量：717 通过 / 2 跳过 / 13 失败，失败清单与基线逐文件一致
  > （`notebook_editor_test` ×3、`notebook_table_interactive_test` ×2、五个 `table_*`
  > 各 1、`pointer_tap_table_test`、`notebook_codeblock_interactive_test`、
  > `disk_slimmer_hardening_verify_test`）。`test/ops_tool_test.dart` 38 个用例全绿
  > （新增 3 个认证语义用例）。
- [x] 4.2 部署：clean → build → codesign → 暂存 → 备份 → 替换 → 校验 AOT 快照哈希

  > 构建 117.8MB（EXIT=0），签名 EXIT=0，AOT 快照哈希 59fff09e… 暂存版与安装版
  > 一致。备份 `.bak-diag-20260922`。日志已重定向到 `/tmp/refresh_err.log`，
  > 待用户触发「刷新 Tag」后读取。
- [ ] 4.3 触发一次「刷新 Tag」，读取请求日志，判定 `path` 未生效真实原因（假设 1 回退 / 假设 2 认证 / 假设 3 URL 构造）

  > **阻塞原因已定位**：日志原先写 `debugPrint` + `kDebugMode`，而 release 构建下
  > `kDebugMode` 为 false，这些日志被编译期移除——`/tmp/refresh_err.log` 中
  > `[GitLab]` 行数为 0（同文件里 `DB Path: .../V8WorkToolbox/notebook.db` 出现 6 次，
  > 证明 app 确为新 build、路径统一已生效）。即：**在最需要日志的 release 场合，
  > 日志方案本身失效**。debugPrint 还有第二个问题——输出落 stderr，而 app 从
  > Dock/Finder 启动时 stderr 去向对用户不可见。
  >
  > 已改为文件落盘：见 4.7。
- [x] 4.4 依据日志修复根因，复跑 `test/ops_tool_test.dart` 与探针

  > **根因（日志实锤）**：URL 为 `tree??path=...`——`Uri(queryParameters:).toString()`
  > 已自带前导 `?`，代码又手工拼了一个。GitLab 把第二个 `?` 当作参数名的一部分
  > （Link 头回写为 `?%3Fpath=`），`path` 参数实际不存在，tree 列举退化为仓库根目录，
  > 只返回 4 条（`argocd` / `backup` / `.gitignore` / `.gitlab-ci.yml`）。
  >
  > **修复**：删掉手工的 `?`；自检从 `url.contains('path=')` 加强为
  > `!url.contains('?path=') || url.contains('??')`；补回归单测锁住「Uri 自带前导 ?」。
  > `test/ops_tool_test.dart` 39 用例全绿；全量 716 通过 / 14 失败，多出的 1 处为
  > `evernote_space_routing` 的 30s 超时（单独复跑即通过，属时序波动）。
- [x] 4.5 再次部署，实机确认「已刷新 117 个 Tag，跳过 3 个非服务文件」且列表无 `Chart.yaml` / `demo.yaml` / `.gitlab-ci`

  > 构建 117.8MB（EXIT=0）、签名 EXIT=0、AOT 快照哈希 3e2db229… 暂存版与安装版一致。
  > 备份 `.bak-fix-20260922`；旧请求日志存档为 `ops_gitlab.log.pre-fix` 以便对照。
  > app 已启动。待用户点击「刷新 Tag」做最终复验。
- [x] 4.6 删除 `test/zz_probe_argocd_test.dart`（含真实 PAT，不得留存）；如需回归能力改为 mock HTTP client 的正式用例

  > 已删除。另有一个临时验证 `test/zz_gitlab_log_test.dart`（验证日志确实落盘），
  > 通过后一并删除。

## 5. 日志方案修正（4.3 阻塞后追加）

- [x] 5.1 新增 `lib/tools/ops_tool/services/ops_gitlab_log.dart`：异步文件追加到 `AppPaths.logsDir/ops_gitlab.log`，4MB 截断（保留 `.1` 副本），写入失败静默降级不影响主流程
- [x] 5.2 `gitlab_client.dart` 全部日志点从 `kDebugMode` + `debugPrint` 改为 `OpsGitLabLog.write`：URL、状态码、headers（token 只打前 6 位+长度）、Link 头原文、翻页推进、v4→v3 回退、path 自检失败
- [x] 5.3 单元验证日志确实落盘（读回文件内容断言含 URL 与脱敏 headers）
- [x] 5.4 部署并再次触发「刷新 Tag」，读取 `~/Library/Application Support/V8WorkToolbox/logs/ops_gitlab.log`

  > 构建 117.8MB（EXIT=0）、签名 EXIT=0、AOT 快照哈希 9efa64bc… 暂存版与安装版
  > 一致。备份 `.bak-log2-20260922`。app 已启动。待用户点击「刷新 Tag」。
