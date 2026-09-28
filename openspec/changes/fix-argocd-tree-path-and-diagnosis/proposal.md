## Why

「刷新 Tag」在当前部署版本上直接报错，ArgoCD 监控完全不可用。已用真实凭据在测试环境复现：`ArgoCdService.listYamlTags` 抛异常，信息是「配置仓 repository/config-fs-argocd-sit 的 argocd/projects（分支 master）下未找到任何 values-*.yaml 服务文件（共 4 个条目）」。

同一次实测确认了三件事：路径解析正确（`repo=repository/config-fs-argocd-sit`、`branch=master`、`fileDir=argocd/projects`）；目录列举只返回 4 条；兜底校验按设计拦住了这次异常。而用 curl 做对照实验，「不带 `path` 参数」恰好返回 4 条（`argocd` / `backup` / `.gitignore` / `.gitlab-ci.yml`，即仓库根目录前几项），「带 `path=argocd%2Fprojects`」返回 100 条并带 `Link: rel="next"`。

因此可以确定：**tree 列举请求里的 `path` 参数没有生效**，GitLab 退化为列举仓库根目录，导致目标目录下的 117 个 `values-*.yaml` 一个都没被看见。

但同一段代码构造出的 URL 与 curl 成功的 URL 完全一致，却得到不同结果。这意味着差异不在 URL 本身，而在请求头或认证路径（`_getWithFallback` 的 v3 回退、或 `ensureToken()` 后的实际 token）。**这一环尚未被证据锁定**，是当前排查的断点。

此外，现有兜底校验把「目录下真的没有服务文件」和「`path` 疑似未生效」混为同一条错误文案，指向「请检查配置仓项目路径」，而真实原因是请求构造——这条错误信息主动误导了排查方向。

## What Changes

- **目录列举请求可诊断**：`listRepositoryFiles` 在 debug 模式下输出实际请求 URL、HTTP 状态码、本页条目数与 `Link` 响应头，使「URL 构造是否正确」「是否走了 v3 回退」「分页是否推进」三个疑问能被一次运行回答，而不是靠 curl 结果反推。
- **兜底校验的错误文案区分两种情形**：当列举结果为空且未带 `path` 参数（或 `path` 为空串）时，明确指出「列举请求未限定子目录，GitLab 已退化为列举仓库根目录」；仅当确实带了非空 `path` 仍无服务文件时，才提示检查路径中的分支与子目录。
- **`path` 参数的下发路径加固**：显式校验 URL 中确实包含 `path=` 段（`kDebugMode` 下断言），避免集合字面量中的条件条目在未来重构中静默失效。
- **认证路径排除分叉**：`login()` 在 `config.token` 非空时直接返回，不再进入 session 循环；对此补一条单测，锁住「配置了 PAT 就不该打 session API」这一语义。
- **不改变**：`values-` 前缀过滤、翻页逻辑、`ArgoCdTagScanResult` 的成功/失败/跳过计数、UI 反馈文案（「已刷新 N 个 Tag，跳过 M 个非服务文件」）——这些在上一轮已实现且被单测覆盖。

## Capabilities

### New Capabilities

<!-- 无新增能力。 -->

### Modified Capabilities

- `ops-tool`: 修订「DevOps ArgoCD 镜像标签监控与防漂移锁定」中「刷新 Tag 并与已有配置合并」场景——列举请求 MUST 可诊断（debug 模式下可观测 URL、状态码、条目数与分页头）；当列举结果未限定子目录时，系统 SHALL 给出指向请求构造而非用户配置的错误提示。

## Impact

- **代码**：`lib/tools/ops_tool/services/gitlab_client.dart`（`listRepositoryFiles` 请求日志与 `path` 下发校验、`login()` token 分支）、`lib/tools/ops_tool/services/argocd_service.dart`（兜底校验文案分情形）、`test/ops_tool_test.dart`（`login()` PAT 语义单测）。
- **诊断资产**：现有探针 `test/zz_probe_argocd_test.dart` 在定位完成后删除或转为使用 mock HTTP client 的正式用例（不进 release 包）。
- **不影响**：数据库结构、凭据存储形态、窗口拓扑、其余 DevOps 能力。
- **依赖**：无新增。
