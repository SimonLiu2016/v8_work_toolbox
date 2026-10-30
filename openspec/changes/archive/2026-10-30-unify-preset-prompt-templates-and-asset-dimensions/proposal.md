## Why

当前短视频工坊存在三项严重的工程硬编码与架构割裂问题：
1. **配置存储多头分散与系统提示词硬编码**：系统提示词（三视图 4 区块规范、纯净场景规范、五维导演拆镜规范等）写死在 Dart 代码常量中，用户无法在 UI 中查看或编辑；且工坊预设库只纳管了风格和题材，缺乏统一的规则模板配置体系；
2. **年龄与骨架约束缺失导致微胖/少年角色退化为幼童**：系统静态注入“修长挺拔”与角色的“矮壮敦实”产生严重提示词冲突，且中文“白胖圆脸、圆髻、唇红齿白”在无骨架保护时触发了强烈的年画福娃/幼童先验，导致十六岁少年“余小白”生成为 5~6 岁儿童；
3. **场景图意外落入 9:16 竖屏短剧比例且缺乏人工尺寸控制**：场景图单视角与批量生成漏传宽高，落入 `1080x1920` 竖屏默认值，严重破坏空间纵深；且 IP 主库生图全流程缺乏用户自由调整尺寸与比例的入口。

统一预设存储体系、动态自适应全年龄骨架、纠偏场景图宽屏并开放 IP 主库全生图规格控制，是保障工坊专业度与生成自由度的必要升级。

## What Changes

- **统一工坊预设存储（`StudioPresetStore` 扩容）**：
  - 新增 `prompt_templates.json`，统一归口至 `video_studio/global_library/presets/`；
  - 由 `StudioPresetStore` 统一纳管三大核心预设（美学风格、时代题材、系统提示词模板），支持出厂自愈、增量持久化与响应式广播；
  - 交付 `StudioPromptTemplate` 模型与 5 套核心出厂纯中文提示词模板。
- **预设中心 UI 扩展（可视化系统提示词管理）**：
  - 在 `StudioPresetManagementDialog` 中新增「系统提示词与规则」Tab；
  - 支持按分类查看出厂预置、富文本编辑自定义内容、保存修改以及一键恢复出厂设置。
- **全年龄阶段动态骨骼防漂移与体态解绑**：
  - 移除系统比例硬编码“身材修长挺拔”，改为“符合角色自身体型设定”，消除语义打架；
  - 动态识别中文自然语言中的年龄阶层（幼童、少年、青年、中年、老年），在正向提示词中注入对应骨骼身量与防低幼/防老态约束，彻底解决余小白等角色退化为幼童的缺陷。
- **场景图 16:9 纠偏与 IP 主库全局生图规格控制**：
  - 场景图单视角生成与 7 方位批量生成彻底修复漏传宽高的缺陷，默认绑定 `2K · 16:9` 宽画幅；
  - 在角色三视图、场景视角、道具卡等生图操作区挂载统一的 `ImageDimensionSelector`，支持用户手动选定 1K~4K 分辨率档位与 16:9 / 9:16 / 1:1 / 4:3 / 21:9 宽高比，直通对齐 Agnes 官方参数。

## Capabilities

### New Capabilities
- `studio-prompt-templates`: 短视频工坊系统提示词与规则模板化统一存储与可视化管理，统一由 `StudioPresetStore` 纳管，支持出厂预置、自愈、用户覆写与一键恢复出厂。

### Modified Capabilities
- `character-turnaround-sheet`: 增加全年龄段动态骨骼防漂移与体态解绑（解绑修长挺拔硬编码，动态注入幼童/少年/青年/中年/老年骨架描述，解决微胖少年被误生为幼童的缺陷），并支持人工自由指定生图尺寸档位与画幅比例。
- `prop-cards`: 支持人工自由指定道具资产图的生图尺寸档位与画幅比例。
- `ai-video-studio/series-asset-library`: 场景空间视角生成默认纠偏为 16:9 宽画幅，并在场景空间视角单张与 7 方位批量生成中支持人工自由指定尺寸档位与画幅比例。

## Impact

- **代码修改**：
  - `lib/services/app_paths.dart`：登记 `promptTemplatesFile`；
  - `lib/tools/ai_video_studio/models/studio_models.dart`：定义 `StudioPromptTemplate`、`StudioImageDimensionPreset` 与全年龄骨骼解析逻辑；
  - `lib/tools/ai_video_studio/services/studio_preset_store.dart`：扩容加载与持久化 `prompt_templates.json`；
  - `lib/tools/ai_video_studio/services/prompt_assembler.dart` 与 `ai_constraint_engine.dart`：解耦静态硬编码常量，从 Store 动态读取模板；
  - `lib/tools/ai_video_studio/ui/studio_preset_management_dialog.dart`：增加系统提示词管理 Tab；
  - `lib/tools/ai_video_studio/ui/series_page.dart`：场景图生成绑定 16:9，并为角色、场景、道具接入规格选择器。
- **配置与兼容性**：
  - 首次启动自动将出厂模板写入 `prompt_templates.json`，向后兼容无破损；
  - 场景图历史文件不受影响，新生成图默认 16:9 宽屏。
