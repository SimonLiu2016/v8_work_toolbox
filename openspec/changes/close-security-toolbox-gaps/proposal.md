## Why

`add-security-toolbox` 的 69 个任务已全部勾完，但代码里有三处"看起来实现了、实际空转"的能力：Security Agent 的 9 个工具只 log 不执行（Agent 全程跟回声说话）、Shodan 整块是孤岛（服务层写完但无 UI 也无调用方）、LHOST/LPORT 没落 settings（换个会话就丢）。另有 sqlmap 解析偏离 design、情报交叉比对不落库、ffuf 字典路径硬编码 Apple Silicon 三处半成品。

这三处空转不是"没做完的收尾"，而是 spec 里白纸黑字的需求——用户在 Agent 面板输入目标后拿不到任何真实结果，属于功能不可用。

## What Changes

- **修复** Security Agent 工具执行：`executeTool` 接入真实的 `NmapService` / `NucleiService` / `SubfinderService` / `MsfRpcService` / 情报库查询 / 会话 Finding 查询，执行结果写回会话并注入时间线
- **新增** Shodan API Key 配置 UI（存入 settings_store 工具配置），资产操作里提供"外部情报查询"入口，命中结果合并进资产 metadata
- **新增** 全局 LHOST/LPORT 配置（spec 7.7）：持久化到 settings_store，利用模块的推荐与执行默认读它，不再是 MSF 连接框的 host/port 顶替
- **修复** sqlmap 结果解析回归 design 决策：改回读 `--output-dir` 下的 JSON 结果文件，DBMS 归属按 URL 维度而非 `findings.last`
- **修改** 情报交叉比对：从"内存里算一次喂 banner 文案"改为可一键生成 Finding（`source=intel_match`、`status=open`），保留 banner 提示但不自动刷噪音
- **修复** ffuf 默认字典路径按架构选择（`/opt/homebrew/share` 与 `/usr/local/share`），两处都没有时明确报错而不是静默找不到字典

## Capabilities

### New Capabilities

（无。全部是对既有 capability 的缺口修补）

### Modified Capabilities

- `security/ai-agent`: 工具集从"声明了但只 log"改为真实执行，Agent 的每一次工具调用都落库到会话资产/发现物/时间线
- `security/web-recon`: Shodan 从"服务层孤岛"变为可配置、可触发、结果可合并的完整链路
- `security/exploit-manager`: 利用参数从"连接框临时值"改为全局持久化模板
- `security/vuln-scan`: sqlmap 结果来源从 stdout 正则改为 `--output-dir` JSON（回归 design 决策）
- `security/threat-intel`: 交叉比对从"只提示"改为"可一键落库"
