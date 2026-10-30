## Context

参见 `proposal.md - Why`。

### 证据分级

本 design 严格区分「已实测确认」与「待验证假设」——上一轮排查之所以绕远，正是因为用 curl 的结果反推 app 行为，把不同证据等级的事实用同样语气陈述。

**已实测确认**（在 `flutter test` 环境跑真实调用链，配真实 URL 与 PAT）：

```
PROBE ref: repo=repository/config-fs-argocd-sit branch=master dir=argocd/projects
PROBE EXC: 配置仓 repository/config-fs-argocd-sit 的 argocd/projects（分支 master）下
           未找到任何 values-*.yaml 服务文件（共 4 个条目）。
```

**已实测确认**（curl 对照实验，同一 PAT、同一 project id = 60）：

```
GET /tree?path=argocd%2Fprojects&ref=master&per_page=100   → 100 条，含 Link: rel="next"
GET /tree?ref=master&per_page=100（不带 path）              →  4 条：argocd / backup /
                                                                  .gitignore / .gitlab-ci.yml
```

**推论（高置信但有一步跳跃）**：「4 条」= 仓库根目录前几项，故 `path` 未生效。

**待验证假设**：代码构造的 URL 与 curl 成功的 URL 文本一致（已人工比对），但结果不同。差异来源未锁定，候选有三：

1. `_getWithFallback` 因 v4 返回非 2xx 而重试 v3，v3 端点对 `path` 的处理不同
2. `ensureToken()` 后 `_token` 为空或与实际 PAT 不符，GitLab 以更低权限返回
3. `Uri(queryParameters: {...})` 在真实运行时的输出与人工预期不符（例如集合字面量中的条件条目在未来某次重构后失效）

### 目标目录的真实结构（已确认）

```
argocd/projects/
├── templates/            × 1    目录
├── Chart.yaml            × 1    非服务
├── demo.yaml             × 1    非服务
└── values-*.yaml         × 117  分 2 页（100 + 17）
```

## Goals / Non-Goals

**Goals:**
- 让「app 实际发出了什么请求、收到什么响应」在一次运行内可见，不再依赖外部工具反推。
- 修掉 `path` 未生效的根因（无论它落在上述三个候选中的哪一个）。
- 错误文案与真实原因对应，不再把请求构造问题表述成用户配置错误。
- 锁住「配置了 PAT 就不打 session API」的语义，排除认证路径分叉。

**Non-Goals:**
- 不重构 `GitLabClient` 的 v3/v4 回退机制本身，只在其上补可观测性与一处语义锁定。
- 不引入 YAML 解析库。
- 不改动上一轮已实现且被单测覆盖的 `values-` 过滤、翻页、成功/失败/跳过计数。
- 不做凭据加密。

## Decisions

### 1. 请求日志先行，根因修复以日志为依据

- **决策**：先加 debug 请求日志并部署一轮，拿到真实 URL 与响应头后再动根因修复。
- **原因**：三个候选假设的修法互不相同（改回退条件、改 token 传递、改 URL 构造），盲目全改会污染归因。日志的成本极低（`kDebugMode` 包裹，release 包零开销），且能把「不确定的那半」一次变成确定。
- **为什么不用 mock HTTP client 直接定位**：app 走的是 `IOClient` + 真实网络，而 curl 已证明网络与凭据无问题。要观测的是「app 这一侧到底发了什么」，只能让 app 自己说。

### 2. `listRepositoryFiles` 的观测点选择

- **决策**：在每次 `_getWithFallback` 之后打印：目标 URL、最终状态码、本页 `decoded.length`、`Link` 头原文、以及是否发生了 v4→v3 回退（由 `_getWithFallback` 返回一个标记或在日志中对比 URL 版本段）。
- **实现要点**：`_getWithFallback` 当前只返回 `http.Response`。为判断是否回退，日志中直接显示实际请求的 `target`（回退后 `target` 仍是被重试的那个 URL）。因此需要把「实际成功的 URL」纳入日志——最小改动是让 `_getWithFallback` 返回 `(http.Response, String actualUrl)` 记录，或在日志里同时打 v4 与 v3 两个 URL 并标注哪个成功。
- **取舍**：选后者（不改签名），在 `listRepositoryFiles` 内自行判断：若 v4 URL 失败则记一条 warn 日志说明回退原因。

### 3. `path` 参数下发加固

- **决策**：URL 构造后，在 `kDebugMode` 下断言 `path.isEmpty || url.contains('path=')`；不满足则 `debugPrint` 明确错误并仍继续（不抛，避免把调试辅助变成运行时崩溃）。
- **原因**：当前 `if (path.isNotEmpty) 'path': path` 是集合字面量中的条件条目，任何一次格式化或重构都可能悄悄改变其求值时机。断言让这类退化在开发期立刻可见。
- **替代方案**：改为字符串拼接 `'path=${Uri.encodeComponent(path)}'`。暂不采用——curl 已证明 `%2F` 编码可被 GitLab 正确接受，改动它会引入新的不确定变量。

### 4. 兜底校验文案分情形

- **决策**：`listYamlTags` 中的兜底校验拆成两支：
  - `ref.fileDir.isEmpty` → 文案为「未指定子目录，已列举仓库根目录且未找到服务文件」
  - `ref.fileDir.isNotEmpty` → 文案为「已限定子目录 <dir>（分支 <branch>）但未找到 values-*.yaml，请检查该目录下是否存在服务文件」
- **原因**：现有文案把两者都导引到「请检查配置仓项目路径」，而本次故障的真实原因是请求构造。分情形后，错误信息本身就能指示该查代码还是查配置。

### 5. `login()` 的 PAT 语义锁定

- **决策**：`login()` 在 `config.token` 非空时立即返回，不进入 session 端点循环；补单测断言：配置了 token 的 client 调用 `ensureToken()` 后，`_token` 等于该 token，且不产生任何 HTTP 请求（以「未注入可用的 HTTP 端点即不会抛连接错」为间接判据，或注入一个必定失败的 client 验证不被触达）。
- **原因**：这是假设 2 的正面排除。即使它最终不是本次根因，这个语义本身值得锁住——「配了 PAT 还去打 session」是隐性的性能与日志噪音来源。

## Risks / Trade-offs

- **[Risk] 日志只能定位、不能保证修复，可能需要第二轮**
  → Mitigation: proposal 的 What Changes 已把「日志」与「根因修复」列为同一 change 的两部分；若日志揭示的根因不在原计划内，按 apply 阶段的暂停机制报告并补充任务，不臆造修复。

- **[Risk] `debugPrint` 在 release 版被 TreeShake 掉，导致「release 里看不到」**
  → Mitigation: 日志统一用 `kDebugMode` 包裹（编译期常量，release 零成本）；探查根因依赖 debug 运行或本次的 `flutter test` 探针，不需要 release 日志。

- **[Risk] 加 URL 断言在 debug 下误报，打扰开发**
  → Mitigation: 断言失败只 `debugPrint` 不抛，且文案直接说明是「开发期自检」。

- **[Risk] 探针文件 `test/zz_probe_argocd_test.dart` 含真实 PAT，留在仓库中有泄露风险**
  → Mitigation: 本 change 明确定位完成后删除该探针；若需保留回归能力，改为注入 mock HTTP client 的正式用例，绝不在代码中留存真实凭据。

## Migration Plan

1. 加请求日志与 `path` 下发自检（debug only）。
2. 拆分兜底校验文案。
3. `login()` PAT 语义 + 单测。
4. `flutter analyze` 保持 0 errors / 0 warnings；`flutter test` 对比既有失败清单（13 处环境依赖型）。
5. 部署（clean → build → codesign → 暂存 → 备份 → 替换 → 校验 AOT 哈希）。
6. **关键一步**：以 debug 方式运行或经 UI 触发一次「刷新 Tag」，读取 stderr 中的请求日志，锁定 `path` 未生效的真实原因。
7. 依据日志修复根因，再次部署并复验「列表 117 行 / 跳过 3 个非服务文件」。
8. 删除含真实 PAT 的探针文件。
9. **回滚**：`/Applications/V8WorkToolbox.app.bak-badpath-20260922` 等四级备份在位；代码侧 `git revert` 可退。

## Open Questions

- **`path` 未生效的真实原因落在三个候选中的哪一个**——需第 6 步的日志才能确定。这是本 change 的核心待答问题，但不影响前 4 步的实施（日志与文案拆分与根因无关，无论如何都要做）。
- 若日志显示 URL 完全正确、状态码 200、条数仍为 4，则假设 2（认证/权限导致 GitLab 返回降级结果）升级为首要嫌疑，届时需要对比「同一 PAT 在 curl 与 app 中的请求头差异」——`_headers()` 的内容也应纳入日志。
