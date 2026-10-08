## Purpose

让 sqlmap 的注入检测结论来自它自己的结构化结果文件而不是 stdout 文本：stdout 格式跨版本不稳定（design 当初因此选择读 JSON），且 DBMS 归属在多参数 URL 场景下会贴错条目。同时让 ffuf 的默认字典在两代 Homebrew 前缀下都能找到。

## MODIFIED Requirements

### Requirement: SQL 注入检测

系统 SHALL 集成 `sqlmap`，对爬虫或目录扫描发现的含参数 URL 执行自动化 SQL 注入检测，支持 GET/POST 参数，生成结构化发现报告。

#### Scenario: 批量注入检测

- **WHEN** 用户从 URL 列表中选择含参数的 URL 并启动 sqlmap
- **THEN** 系统 SHALL 以 `--batch --output-dir` 模式运行 sqlmap，将注入点发现解析为 Finding 条目

#### Scenario: 结论来自结构化结果文件

- **WHEN** 一次 sqlmap 扫描结束
- **THEN** 系统 SHALL 从 `--output-dir` 指定的目录读取该 URL 的结果文件，提取可注入参数、注入技术、后端 DBMS
- **AND** 解析不到结构化结果时 SHALL 回退为 stdout 关键行提取，并在日志中标注使用了回退路径

#### Scenario: 每条结论归属正确的 URL

- **WHEN** 一次扫描包含多个含参数 URL
- **THEN** 每个 Finding 的 DBMS SHALL 来自该 URL 自己的结果，不与其他 URL 混淆

### Requirement: Web 内容发现（目录爆破）

系统 SHALL 使用 `ffuf` 对存活 Web 资产执行目录与文件爆破，内置常用字典（SecLists 子集），支持扩展名猜测（.php/.asp/.bak/.conf 等），过滤无效响应。

#### Scenario: 字典路径按架构定位

- **WHEN** 用户未指定字典即启动 ffuf 扫描
- **THEN** 系统 SHALL 依次在 Homebrew 的两个前缀下查找默认字典：`/opt/homebrew/share`（Apple Silicon）与 `/usr/local/share`（Intel）
- **AND** 两处均不存在时 SHALL 明确提示"未找到默认字典，请手动指定"，而不是让 ffuf 带着空字典路径失败

#### Scenario: 用户指定字典

- **WHEN** 用户手动指定了字典文件路径
- **THEN** 系统 SHALL 该校验路径存在后使用，不再回退到默认字典
