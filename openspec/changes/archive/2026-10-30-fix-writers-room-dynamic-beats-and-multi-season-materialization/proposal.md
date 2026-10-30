## Why

用户在“编剧研讨室”生成全季规划时，系统原有的线性拉伸插值算法将大模型输出的有限骨架节拍机械复制数遍，导致第 1~4 集乃至全季分集的核心冲突与断章钩子完全重复（仅在标题追加生硬的 `(节拍 2)`、`(节拍 3)`），严重破坏了戏剧起伏与故事独立性；同时，研讨室顶栏标题未做弹性自适应，将定稿按钮与关闭按钮挤出窗外；此外，研讨室规划的多季路线图在定稿时未能在剧集库中物化新建出后续各季对应的剧集项目，且剧集库列表项未直观展示分季与分集徽章，导致创作者难以感知同步结果。

本次变更旨在让分集规划彻底回归由小说真实剧情密度与高潮冲突自然推演，消灭所有机械克隆分集；并在定稿时自动物化多季项目（共享 IP 角色资产），重构顶栏自适应排布，使整套影视化改编与项目管理流程自然顺畅。

## What Changes

- **彻底废除机械复制插值，实现 100% 真实独立分集推演**：
  - 移除 `_SchemaValidators.writersRoomSeasonBeats` 中的直接映射拉伸克隆算法与 `(节拍 X)` 污染逻辑；
  - 优化 AI Prompt 调度，使大模型根据原著小说情节密度、冲突转折与高潮分布自然规划最合理的集数与分集，确保每一集都拥有独一无二的戏剧化标题、核心对抗冲突（`conflict`）与集尾断章钩子（`hook`）；用户指定集数时亦由大模型真实递进推演，绝不克隆重复内容。
- **多季项目自动物化实例化（Multi-Season Materialization）**：
  - 当研讨室规划了多季路线图（如第 1 季、第 2 季、第 3 季）并点击定稿同步时，除将当前剧集更新为第 1 季外，系统自动为第 2 季、第 3 季等其余季度在剧集库中创建对应的独立 `StudioSeries` 项目（如《书名 · 第 2 季 · 季名》）；
  - 所有衍生季度项目严格继承主项目的 `ipId` 与绑定的 `novelId`，实现跨季角色库（脸模、性格、正负向 Prompt）与道具资产的完全共享；
  - 自动将研讨室规划的各季专属分集大纲与断章钩子写入对应项目的分集与记忆库中。
- **剧集库卡片显化分季与集数徽章**：
  - 在 `ProjectListPage` 的剧集卡片折叠态标题旁高亮呈现【第 X 季 · 共 N 集】徽标，一目了然显示剧集体量与季度划分；
  - 在 `_SeriesCardState` 中实现 `didUpdateWidget`，确保跨工序会话广播更新时分集列表与集数统计即时刷新。
- **研讨室顶栏自适应与关闭按钮固定锚定**：
  - 重构 `WritersRoomDialog` 顶部 Header，左侧标题使用 `Flexible` + `overflow: TextOverflow.ellipsis`，根据窗口尺寸自适应收缩；
  - 右侧操作按钮紧凑化排布，右上角关闭按钮（`Icons.close`）固定锚定在窗体最右侧，杜绝任何窗口宽度下的溢出与按钮遮挡。

## Capabilities

### Modified Capabilities
- `ai-video-studio/script-workshop`: 增加小说真实情节密度驱动的无重复分集规划规范、多季路线图自动物化衍生项目规范，以及剧集库分季集数显化要求。

## Impact

- `lib/tools/ai_video_studio/services/ai_constraint_engine.dart`: 移除机械复制插值逻辑，优化短剧分集大纲生成 Prompt 与校验器。
- `lib/tools/ai_video_studio/ui/writers_room_dialog.dart`: 实现定稿时多季项目批量创建与资产继承，修复顶部 Header 弹性自适应与固定关闭按钮。
- `lib/tools/ai_video_studio/ui/project_list_page.dart`: 在剧集卡片显化【第 X 季 · 共 N 集】徽章，补全 `didUpdateWidget` 实时刷新。
- `lib/tools/ai_video_studio/services/studio_project_manager.dart`: 支撑多季项目联动与分季元数据读写。
