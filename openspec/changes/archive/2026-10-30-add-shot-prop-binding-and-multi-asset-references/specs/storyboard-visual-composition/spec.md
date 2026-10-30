## ADDED Requirements

### Requirement: 道具素材指代与正向提示词编译
系统提示词组装引擎（`PromptAssembler` & `AssetBindingResolver`）SHALL 支持解析分镜中的道具绑定。在参考图模式（`reference`）下，系统 SHALL 为每个选中的道具素材分配全局连续的 `<Picture N>` 编号（顺序为：角色素材 ➔ 道具素材 ➔ 场景素材）。

在组装最终提示词时，系统 SHALL 在【素材指代】段中输出道具标识（如 `<Picture 3> = 杀生剑（道具）`），并在出场主体/关键物描述中注入该道具的视觉特征与操作交互。

#### Scenario: 分镜包含角色、道具与场景时的素材编号连续编排
- **WHEN** 分镜绑定了 1 个角色（选 1 张图）、1 个道具（选 1 张图）和 1 个场景（选 1 张图）
- **THEN** 提示词引擎 SHALL 按顺序生成：`<Picture 1> = 角色名（主体）`、`<Picture 2> = 道具名（道具）`、`<Picture 3> = 场景名（场景）`，编号无空缺且与提交到模型 media 数组严格同序

#### Scenario: 首尾帧 keyframe 模式下收敛道具与角色克隆
- **WHEN** 分镜处于首尾帧（`keyframe`）模式并执行提示词净化
- **THEN** 系统 SHALL 剥离 `<Picture N>` 道具标签与重复构图描述，保留核心交互动势，防止视频生成模型二次多重绘制道具或克隆实体
