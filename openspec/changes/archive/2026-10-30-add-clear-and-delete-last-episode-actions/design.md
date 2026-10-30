## Context

剧集库的分集数据物理存放于 `series_library/<seriesId>/episodes/<episodeId>/` 路径下，包含了 `storyboard.json`（剧本场次与分镜数据）、`audio/`（对白录音）、`frames/`（首尾帧画面）、`clips/`（生成视频）与 `exports/`（导出成片）。同时，连续剧的各集前情记忆保存在所属剧集的 `series_profile.json` 中的 `memories` 字段中。

此前：
1. `ProjectListPage` 展开的分集列表头部仅有“新建第 X 集”按钮，缺失分集清理入口；
2. 底层 `StudioProjectManager.deleteEpisode` 仅执行物理目录递归删除，未级联清理 `series.memories`，可能遗留幽灵前情记忆；
3. IP 主库（`ip_library/<ipId>/`）与剧集分集数据已实现物理分目录存储，具备了纯净隔离的前提。

## Goals / Non-Goals

**Goals:**
- 在 `ProjectListPage`（剧集库卡片展开分集）与 `SeriesPage._EpisodesTab`（IP 主库分集列表）头部工具栏中，同构提供“删除最后一集”与“一键清空”操作按钮。
- 分集列表为空（0 集）时，两个清理按钮自动置灰禁用。
- “删除最后一集”自动定位最大序号分集，经二次确认后物理删除该集目录并清理其前情记忆。
- “一键清空”经高危二次确认后物理清空所有分集目录并清空剧情记忆库。
- 若被清理分集处于活跃会话中，安全复位 `session.selectEpisode(null)`。
- 保证 IP 主库（`ip_library/<ipId>/`）中的角色卡、三视图、公共场景卡及世界观 100% 免疫、完好无损。

**Non-Goals:**
- 不支持中间插空删除任意分集（避免序号空洞及自定义标题脱节）。
- 不触动全局资产与 IP 企划的保存与编辑逻辑。

## Decisions

### 1. 采用栈式“删除最后一集”与“一键清空”组合模式
- **选择理由**：剧集创作是按集数顺序推进的连续性流程，最典型的删除诉求只有两种：
  1. 最近一集生成不理想或拆解多余，需要撤销回退（LIFO 栈顶回退）；
  2. 全季方案推翻，需要全量重置重新导入小说（全量清空）。
  如果允许在中间任意删除（例如在 1、2、3 集删第 2 集），将产生序号断层（1、3）或被动重排序（原第 3 集变为第 2 集，与用户起好的标题“第 3 集: 大结局”冲突）。栈式回退彻底杜绝了这类副作用。
- **备选方案**：为每行分集列表项均提供独立垃圾桶删除按钮。缺点是会产生序号空洞，维护成本高且容易误伤前序关键集。

### 2. 底层封装 `deleteLastEpisode` 与 `clearAllEpisodes` 并级联清理前情记忆
- 在 `StudioProjectManager` 中新增：
  - `deleteLastEpisode(seriesId)`：
    1. 扫描当前剧集的所有分集，按 `index` 排序定位末集；
    2. 物理递归删除 `episodes/<lastEpisodeId>/`；
    3. 同步过滤清理 `series.memories` 中对应 `episodeId` 的记忆条目并保存剧集配置。
  - `clearAllEpisodes(seriesId)`：
    1. 物理清空 `episodes/` 下的所有分集子目录；
    2. 清空 `series.memories = []` 并原子落盘保存；
    3. 保留 `series_profile.json` 自身的元数据（名称、世界观、关联 ipId 等）。
- 确保后续 AI 编剧上下文绝对不会读到已销毁分集的前情。

### 3. 会话状态与界面响应联动
- 在执行删除最后一集或清空前，判断 `session.episode?.seriesId == seriesId`：
  - 若执行一键清空，直接调用 `session.selectEpisode(null)`；
  - 若删除最后一集，且当前 `session.episode?.id == targetLastEp.id`，调用 `session.selectEpisode(null)`；
- 刷新分集列表数据，界面右上角“新建第 X 集”按钮文案自动动态更新。

### 4. 强警示二次确认交互
- **删除最后一集**：弹窗指明具体的集数与标题（例如《第 3 集: 终局之战》），降低误删概率；
- **一键清空**：弹窗使用警示红按钮，并在说明中明确告知“角色库与 IP 主库不受影响”，消除创作者顾虑。

## Risks / Trade-offs

- **[误操作清空风险]** → 弹窗增加明确的警示文案，确认按钮使用红色警示风格，取消按钮获得默认焦点；且列表为 0 时按钮直接置灰。
- **[文件写锁冲突]** → 调用 `_writeChains` 确保分集与剧集配置在原子链中安全保存并释放目录缓存。
