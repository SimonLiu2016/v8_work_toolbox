## Why

两个在实机验证中暴露的问题，共同导致磐石运维工具的 ArgoCD 监控不可用。

**一是应用被沙盒化导致数据路径分裂。** `macos/Runner/Release.entitlements` 中的 `com.apple.security.files.user-selected.read-write` 使 macOS 将 `getApplicationSupportDirectory()` 重定向到带 bundle id 的 `~/Library/Application Support/com.v8en.V8WorkToolbox/`，而非原有的 `~/Library/Application Support/V8WorkToolbox/`。旧路径下已积累的 AI 配置、密码库密钥（`.dek` / `.secrets.bin`）、隐私空间媒体、资讯缓存、运维工具数据库全部失联，新路径下只有笔记附件（423M）与一个刚初始化的 `ops_tool.db`。笔记主库因走 drift 的 `getDatabasesPath()` 而未受影响，反而使分裂更隐蔽——用户看到笔记都在，误以为一切正常。

**二是 ArgoCD Tag 列表拉取失真。** 实测配置仓 `repository/config-fs-argocd-sit`（project id 60）的 `argocd/projects` 目录下有 117 个 `values-*.yaml`（分 2 页）、1 个 `templates` 目录、2 个非服务文件（`Chart.yaml` / `demo.yaml`）。但点击「刷新 Tag」只得到一行 `project_name = ".gitlab-ci"` 且 `current_tag` 为空——`.gitlab-ci.yml` 并不在该目录的 tree 返回中，说明 `listRepositoryFiles` 的 `path=` 参数在请求中丢失，退化为列出仓库根目录；而 `listYamlTags` 中 `catch (_) {}` 静默吞掉了全部失败，使用户侧完全看不到「117 个文件一个都没读到」。此外过滤条件收得过宽（任何 `.yaml`/`.yml`），把 `Chart.yaml`、`.gitlab-ci.yml` 这类非服务文件也当成微服务；`extractImageTag` 对 `tag: "v1.2.3"` 带引号的形态不剥引号；ArgoCD 监控 Tab 的环境编辑入口同时存在于环境标签铅笔图标与详情卡「编辑环境」按钮两处，功能重复。

## What Changes

- **移除应用沙盒**：删除 `macos/Runner/DebugProfile.entitlements` 与 `Release.entitlements` 中的 `com.apple.security.files.user-selected.read-write`、`com.apple.security.files.downloads.read-write`、`com.apple.security.files.desktop.read-write`、`com.apple.security.files.documents.read-write` 四项文件访问 entitlement，使 `getApplicationSupportDirectory()` 回到 `~/Library/Application Support/V8WorkToolbox/`。保留 `network.client` / `network.server` / `automation.apple-events` / `cs.allow-unsigned-executable-memory`——本工具需要访问内网 GitLab、Jenkins、SMTP，以及通过 `osascript` 发送原生通知。**BREAKING**：已安装的沙盒版本所写入的新路径数据（`ops_tool.db`）需迁回旧路径后才可见。
- **修正配置仓文件列举**：`listRepositoryFiles` 显式构造含 `path` / `ref` / `per_page` 的查询参数，确保 `path=` 不丢失；对非 2xx 响应与 JSON 解析失败给出可归因错误而非静默返回空列表。
- **修正服务文件过滤**：Tag 列举仅保留 `values-` 前缀的 `.yaml` / `.yml`，排除 `Chart.yaml`、`demo.yaml`、`.gitlab-ci.yml` 与目录条目（`type == 'tree'`）。
- **消除静默失败**：`listYamlTags` 对单个文件读取失败记录失败原因与文件名，汇总为「N 个成功 / M 个失败」反馈到 UI，不再丢弃。
- **修正 Tag 提取**：`extractImageTag` 去除 `tag` 值两侧的成对引号。
- **合并重复编辑入口**：删除环境标签（chip）中的铅笔图标，保留详情卡上的「编辑环境」文字按钮作为唯一编辑入口；chip 只承担选中、启停与删除。
- **数据归位**：将沙盒版本写入新路径的 `ops_tool.db` 合并回旧路径（保留旧库中更多的历史数据），并验证 AI 配置、密码库密钥、隐私空间媒体重新可见。

## Capabilities

### New Capabilities

<!-- 无新增能力。 -->

### Modified Capabilities

- `ops-tool`: 修订「DevOps ArgoCD 镜像标签监控与防漂移锁定」要求——「刷新 Tag」场景 MUST 列举配置仓内全部 `values-` 前缀的 YAML 文件并逐页遍历，MUST 排除非服务文件与目录条目，读取失败 MUST 可归因而非静默；环境管理场景中编辑入口收敛为单一入口。

## Impact

- **打包配置**：`macos/Runner/DebugProfile.entitlements`、`macos/Runner/Release.entitlements`——移除 4 项文件访问 entitlement。需 `flutter clean` + 重新构建 + 重新签名部署；旧版备份已存在于 `/Applications/V8WorkToolbox.app.bak-20260922`。
- **代码**：`lib/tools/ops_tool/services/gitlab_client.dart`（`listRepositoryFiles` 请求构造与错误处理）、`lib/tools/ops_tool/services/argocd_service.dart`（`listYamlTags` 过滤与失败反馈、`extractImageTag` 引号剥离）、`lib/tools/ops_tool/ui/ops_devops_view.dart`（chip 去铅笔图标、刷新结果含失败计数）、`test/ops_tool_test.dart`（补过滤与引号用例）。
- **数据**：`~/Library/Application Support/V8WorkToolbox/ops_tool/ops_tool.db`（归并回旧路径）与 `~/Library/Application Support/com.v8en.V8WorkToolbox/ops_tool/`（待确认后清理）。
- **不受影响**：笔记主库 `~/Documents/notebook.db` 走 drift `getDatabasesPath()`，与 App Support 路径无关；新路径的 `notebook_attachments`（423M，757 个文件）在去沙盒后会转为按旧路径寻址，需评估是否迁移或改由笔记库内的相对路径解析。
- **依赖**：无新增第三方依赖。
