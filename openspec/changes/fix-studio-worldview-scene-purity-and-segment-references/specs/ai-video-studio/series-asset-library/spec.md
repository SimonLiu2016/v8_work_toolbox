## ADDED Requirements

### Requirement: 场景纯净空镜空间与多角度组图生成

系统 SHALL 在 IP 主库场景库中为每个常驻场景提供纯净空镜空间约束与多角度/全景组图生成能力。在生成或更新场景生图 Prompt 时，系统 SHALL 强制注入场景空镜正向特征词（`empty scene, no humans, pure architectural scenery, vacant interior`）与负向人类排除锁（`human, people, person, crowd, man, woman, face, character`），确保场景资产卡不出现具体人物。

系统 SHALL 支持一键为场景卡生成多角度视角组图，组图涵盖：
1. 全景建立镜头（Wide Establishing / Panoramic Shot）
2. 主轴平视全景（Eye-Level Main Interior/Exterior View）
3. 反打/侧方位视角（Reverse Angle / Side Angle View）
4. 局部陈设特写（Detail & Architectural Close-up）

生成后的多视角图片 SHALL 自动存入场景目录下的参考图集合中供下游分镜与大段任务按需引用。

#### Scenario: 场景生图自动阻绝人物并生成空镜
- **WHEN** 用户在场景卡编辑弹窗中点击“AI 生成场景图”
- **THEN** 系统在调用生图适配器时自动拼接纯净空镜提示词与人类负向排除词，生成的图片为不包含人物的纯建筑空间与环境光影。

#### Scenario: 一键生成多角度场景包
- **WHEN** 用户点击“生成多角度场景组图”
- **THEN** 系统依次并发或按序生成全景、主视、反打与特写视角的一整套图片，并追加至该场景的参考图库中。

### Requirement: 连续剧全局会话与时代题材状态同步

系统 SHALL 在全局 `StudioSession` 中维护当前激活的剧集对象。当在 IP 主库修改世界观、时代题材（`eraGenre`）、全局风格锁等属性并落盘时，`StudioSession` SHALL 在剧集 ID 相同时更新内存中保存的最新剧集对象，并向全局监听器广播通知，且 SHALL NOT 误重置当前选中的集（`episode`）。各面板（如 `SeriesPage`）在收到通知或切换 Tab 时，SHALL 呈现内存中最新的剧集属性与标签选中状态。

#### Scenario: 切换时代题材标签后切 Tab 状态保持
- **WHEN** 用户在「世界观」选项卡中选中一个视觉时代题材（如“仙侠修真”），并切换到「角色卡」或左侧「分镜看板」后再切换回「世界观」
- **THEN** 界面上的“仙侠修真”标签仍处于高亮选中状态，且下方展示对应的时代服饰与道具锚点。
