## ADDED Requirements

### Requirement: 资产导出的内容范围

资产桥 SHALL 支持把 AI 短视频工坊中一个剧集的既有内容导出为 Toonflow 工作区，导出范围 SHALL 限于：本集粗剧情大纲、世界观设定、全局风格词、角色卡（中文外貌描述 + 英文正负向 Prompt + 基准参考图文件）、场景卡（中文描述 + 英文 Prompt + 主视图参考图文件）、以及按分镜序号组织的分镜表文本。

资产桥 SHALL NOT 导出：任何供应商 API Key、本软件的配置、其他剧集的数据、或 Toonflow `settings.json` 的任何内容。

#### Scenario: 导出一集到工作区

- **WHEN** 用户在工坊中选择一个剧集与集并触发「导出到 Toonflow」
- **THEN** 系统在 `toonflow_data/workspaces/<series-id>/` 下写入画布 JSON、若干内容节点的 Markdown 文件与 `assets/<nodeId>/` 下的参考图文件，并向用户报告实际写入的路径清单

#### Scenario: 重复导出不产生重复目录

- **WHEN** 用户对同一剧集再次触发导出
- **THEN** 系统覆盖同一工作区目录中的同名内容节点与参考图，不为同一剧集创建第二个工作区目录

### Requirement: 导出落盘结构

导出产物 SHALL 满足 Toonflow 画布的读取契约：工作区根目录下的画布 JSON SHALL 包含 `toonflowCanvas: true` 标记、`nodes` 数组与 `viewport`；文本类内容 SHALL 落在 `assets/<nodeId>/content.md`，与该画布 JSON 中对应文本节点的 `textPath` 一致；参考图 SHALL 落在 `assets/<nodeId>/` 下，画布 JSON 中对应图片节点通过工作区相对路径引用。

系统 SHALL 为每次导出生成确定性的节点 id（由剧集/集/角色/场景标识派生），使重复导出的画布 JSON 稳定可比。

#### Scenario: 画布 JSON 可被 Toonflow 识别

- **WHEN** 用户在 Toonflow 工作台打开导出的工作区目录并加载该画布
- **THEN** Toonflow 识别该文件为有效画布并展示其中的文本节点与图片节点

#### Scenario: 文本节点路径与文件一致

- **WHEN** 系统导出一个包含剧本大纲的画布
- **THEN** 画布 JSON 中该文本节点的 `textPath` 指向 `assets/<nodeId>/content.md`，且该文件存在于工作区内

### Requirement: 导回的扫描与归集

资产桥 SHALL 支持把 Toonflow 工作区中新产生的视频产物归集回工坊。扫描范围 SHALL 限于 `toonflow_data/workspaces/<series-id>/assets/` 下的视频文件，系统 SHALL 按文件修改时间排序，并把用户本次选中的文件复制到该集对应的 `segments/` 或 `clips/` 目录。

复制而非移动：Toonflow 工作区的原文件 SHALL 保持不动，因为用户可能仍在 Toonflow 内继续使用它。

#### Scenario: 归集新生成的片段

- **WHEN** 用户在 Toonflow 中完成了视频生成，回到工坊触发「从 Toonflow 归集」
- **THEN** 系统列出工作区内本次导出后新增或修改的视频文件，用户勾选后系统将其复制到当前集的 `segments/`，并按分镜顺序写回剧集数据

#### Scenario: 未选择集时不猜测目标

- **WHEN** 用户在工坊中未选中任何集时触发归集
- **THEN** 系统报告需要先选择目标集，不自行选择某一集或创建新集

### Requirement: 密钥边界

资产桥及其所在工具 SHALL NOT 读取、写入、复制、打印或导出 Toonflow 数据目录中的 `settings.json`。诊断日志与错误信息 SHALL NOT 包含该文件的内容。

系统 SHALL 在资产桥的导入/导出结果中不包含任何来自 `settings.json` 的字段。

#### Scenario: 导出不触碰密钥文件

- **WHEN** 用户执行一次导出或归集
- **THEN** 系统对 `settings.json` 的访问次数为零，该文件的修改时间不变

#### Scenario: 错误信息不泄漏密钥

- **WHEN** 一次文件操作失败并产生错误详情
- **THEN** 系统展示的错误文本 SHALL NOT 包含 `settings.json` 的内容或其路径下的任何供应商凭据

### Requirement: 写画布内容的权限边界

资产桥 SHALL 只写「内容节点与其素材文件」这一层，SHALL NOT 写画布的连线（edges）、节点生成状态、或节点的模型配置。连线与媒体生成 SHALL 由用户在 Toonflow 工作台内通过其 Agent 能力完成。

系统 SHALL 在导出结果中说明：画布已含内容节点与参考素材，但需要用户在 Toonflow 内完成连线与生成。

#### Scenario: 导出不含连线

- **WHEN** 用户查看一次导出的结果报告
- **THEN** 系统报告写入的节点与素材清单，并明确说明未创建任何连线、未触发生成

#### Scenario: 用户自行完成后续

- **WHEN** 用户在 Toonflow 中打开导出的画布并要求其 Agent 把角色图接到视频生成节点
- **THEN** 该操作由 Toonflow 完成，本软件不参与也不记录其生成参数
