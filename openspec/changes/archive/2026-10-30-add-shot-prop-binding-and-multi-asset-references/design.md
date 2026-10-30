## Context

参见 `proposal.md`。当前系统在 IP 资产库中已具备 `PropCard` 数据模型与存储能力，但在进入分镜看板与图生视频流水线时，分镜模型（`StudioShot`）中既没有 `propIds` 字段，看板视图也未加载项目道具列表。同时，现有的资产绑定行（`_AssetRow`）采用单一字符串 `materialPath` 与单选下拉框，无法为单一资产关联多张参考图。

## Goals / Non-Goals

**Goals:**
- **实体维度扩展**：分镜支持绑定任意数量的道具（`propIds`），并在看板出场资产面板中以可视化资产行统一管理。
- **选择交互优化**：“添加角色”与“添加道具”提供直观的弹出菜单，让用户自由挑选要加入分镜的具体资产。
- **多参考图支持**：单个资产支持绑定 1~N 张参考图，统一映射至 `<Picture N>` 引用流与视频大模型 media 数组。
- **提示词与大模型闭环**：`AssetBindingResolver` 与 `PromptAssembler` 将道具与多参考图正确编译进【素材指代】与正向提示词。

**Non-Goals:**
- 不重构现有角色与场景卡的底层文件存储路径（继续保持 `characters/`、`scenes/`、`props/` 目录组织）。
- 不突破下游大模型的单次参考图硬性上限（如 Agnes 最大 5 张），仅负责在超出时给予前置提示与有序截断。

## Decisions

### 1. 分镜数据结构扩充与向后兼容
- **方案**：
  - 在 `StudioShot` 中新增 `final List<String> propIds;`（默认 `const []`）；
  - 在 `ShotAssetBinding` 中新增 `final List<String> materialPaths;`，并将旧的 `materialPath` 包装为 getter：`String get materialPath => materialPaths.firstOrNull ?? '';`；
  - `ShotAssetBinding.fromJson` 兼容旧版 `{ "material_path": "..." }` 与新版 `{ "material_paths": [...] }`。
- **替代方案**：为道具单独新建 `ShotPropBinding` 类。
  - *未采用原因*：角色、道具与场景在生图和视频模型中本质皆为可附带分工与多张参考图的“输入资产”，统一使用通用的 `ShotAssetBinding` 可以极大精简序列化与编译器代码。

### 2. 素材枚举与指代排序规则
- **方案**：
  - `AssetMaterialEnumerator` 补充 `forProp(PropCard prop, {required String propDirPath})`，枚举道具目录下的全部生成图与参考图；
  - `AssetBindingResolver.resolve` 严格遵循以下有序编号：
    1. 角色参考图（按 `characterIds` 顺序展开各自的多张 `materialPaths`）；
    2. 道具参考图（按 `propIds` 顺序展开各自的多张 `materialPaths`）；
    3. 场景参考图（按 `sceneId` 展开）。
  - 若某个实体绑定了 2 张图，则按顺序分配两个 `<Picture N>` 标签，如：
    - `<Picture 1> = 姜七夜（主体）`
    - `<Picture 2> = 姜七夜（特写）`
    - `<Picture 3> = 杀生剑（道具）`
    - `<Picture 4> = 寒阳城长街（场景）`

### 3. 看板交互与弹出选择器
- **方案**：
  - 将 `_ShotAssetPanel` 的文本按钮改为带下拉弹窗的 `PopupMenuButton<String>`；
  - 点击“添加角色”时，弹出的菜单项显示未绑定的角色头像、名称与描述，点击即可加入；
  - 点击“添加道具”时，弹出的菜单项显示未绑定的道具名称、分类与关键标记，点击即可加入；
  - 资产行支持多选模式：点击素材下拉或选择标签，支持一次勾选多张候选图。

## Risks / Trade-offs

- **[Risk]** 用户为同一个镜头勾选过多角色、道具与参考图，导致参考图总数超出视频大模型限制（如 Agnes 限制 5 张）。
  - **Mitigation**: 在 `_ShotAssetPanel` 头部实时显示 `[参考图: N/max]` 计数，当 `N > max` 时以醒目的黄色条幅提醒，并在提交生图任务时优先按角色主体 ➔ 道具 ➔ 场景保留前 `max` 张，避免静默报错。
- **[Risk]** 旧版本历史分镜数据中无 `prop_ids`。
  - **Mitigation**: `StudioShot.fromJson` 中使用 `(json['prop_ids'] as List?)?.cast<String>() ?? const []` 兜底，实现 100% 平滑迁移。
