# studio-prompt-templates Specification

## Purpose
短视频工坊系统提示词与规则模板化统一存储与可视化管理，统一由 StudioPresetStore 纳管，支持出厂预置、自愈、用户覆写与一键恢复出厂。
## Requirements
### Requirement: 统一工坊提示词模板持久化与出厂自愈

系统 SHALL 在 `video_studio/global_library/presets/` 目录下通过 `prompt_templates.json` 集中持久化管理短视频工坊的所有系统提示词与排版规则模板，统一由 `StudioPresetStore` 纳管。

系统启动时 SHALL 校验并自动自愈缺失的内置出厂模板，出厂模板集 SHALL 至少覆盖：
1. `character_turnaround`：角色三视图 4 区块排版、正交平视与 PBR 物理漫射去塑料感规范；
2. `character_age_staging`：全年龄阶层骨骼身量与防低幼/防老态自适应规范；
3. `scene_environment`：场景宏大空间构图、纯净空镜与人物排除规范；
4. `prop_asset`：道具资产多角度展示与纯白底规范；
5. `director_breakdown_5d`：五维导演拆镜与视听语言语法规范。

#### Scenario: 首次启动自动初始化出厂提示词模板
- **WHEN** 应用首次启动且 `prompt_templates.json` 不存在或为空
- **THEN** 系统 SHALL 自动以预置出厂模板创建该文件，并在内存中加载全部有效模板

#### Scenario: 缺失内置模板自动增量补齐
- **WHEN** 磁盘上的模板配置文件缺少某个新增的出厂内置模板
- **THEN** 系统 SHALL 增量将该出厂模板补入配置并落盘，同时保留用户已自定义修改的其他模板内容

### Requirement: 可视化系统提示词管理界面

系统 SHALL 在工坊预设管理中心（`StudioPresetManagementDialog`）中提供「系统提示词与规则」管理标签页。

界面 SHALL 支持：
1. 按资产规范与导演调度分类查看所有预置提示词模板；
2. 在右侧编辑器中查看说明、出厂默认内容及用户覆写内容；
3. 编辑并保存自定义提示词模板；
4. 支持单项一键恢复为出厂默认设置，并即时持久化到磁盘。

#### Scenario: 编辑并保存自定义提示词模板
- **WHEN** 用户在预设管理中心修改了某个提示词模板的内容并点击「保存」
- **THEN** 系统 SHALL 更新内存中的模板状态并原子写入 `prompt_templates.json`
- **AND** 后续的相关生图或拆镜流水线 SHALL 立即读取使用修改后的提示词

#### Scenario: 恢复出厂默认设置
- **WHEN** 用户对已修改的提示词模板点击「恢复出厂默认」
- **THEN** 系统 SHALL 将该模板重置为出厂预置内容并持久化，界面同步更新为默认状态

### Requirement: 流水线动态读取与渲染提示词模板

生图组装器（`PromptAssembler`）与 AI 约束引擎（`AiConstraintEngine`）在构建三视图、场景图、道具图以及拆镜提示词时，SHALL 动态从 `StudioPresetStore` 读取最新有效的提示词模板，MUST NOT 依赖硬编码静态常量。

#### Scenario: 动态读取更新后的三视图提示词
- **WHEN** 用户在设置中修改了三视图的排版提示词，并在 IP 主库中为角色点击「生成三视图」
- **THEN** 系统组装出的生图 Prompt SHALL 包含用户最新修改的模板规则内容

