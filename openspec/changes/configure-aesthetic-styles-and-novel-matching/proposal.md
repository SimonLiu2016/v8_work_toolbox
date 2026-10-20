## Why

当前“短视频工坊”中的“美学风格”（Aesthetic Style）与“视觉时代与题材”（Visual Era & Genre）存在严重的硬编码与体验缺陷：
1. **硬编码与不可扩充**：美学风格仅为 UI 中写死的 6 个粗糙英文选项，时代题材仅为枚举类中硬编码的 8 项，用户无法根据创作需求在软件中自定义、扩充或修改标签；
2. **定义混乱且缺乏负向防崩体系**：缺少美术媒介与时代世界观的正交分层，且美学风格完全没有专属的负向避雷词，导致生图与生视频时频发跨媒介污染（如 2D 水墨出 3D 塑料感，3D 国漫出现手绘线稿，古装仙侠穿现代短裤等）；
3. **小说解构匹配失准**：在小说全案长文解构中，时代题材只能从固定的 8 项中死板选择，风格词全凭大模型即兴临场发挥，生成的词往往无法命中经过调优的生图引擎最佳范式。

亟需建立一套全局可配置、高覆盖度的美学风格与时代题材预设库体系（基于工业级 35 套美学提示词库与全题材世界观），并在小说解构时实现全自动智能匹配与正负向避雷锁的自动装配。

## What Changes

- **全局预设持久化存储与出厂预设加载**：在全局公共目录（`AppPaths.studioDir/presets/`）下引入 `aesthetic_styles.json` 与 `visual_era_genres.json`，出厂默认收录 8 大体系 35 套工业级全量美学风格（正向词、专属负向避雷词、推荐画幅）以及扩充后的全量时代题材世界观，支持全局跨项目共享与自愈补全。
- **预设管理中心（全局配置）**：在工坊设置中提供可视化的预设管理抽屉，支持用户按体系分类浏览、新增自定义风格/题材、编辑正负向词条、复制微调、重置出厂预设。
- **三层负向词智能装配**：重构 `PromptAssembler` 与约束引擎，负向提示词由单层避雷升级为三层自动叠装：`[时代题材排他负向词] + [美学风格专属负向词] + [通用防崩负向词]`。
- **小说解构自动化智能匹配**：小说全案第一阶段提炼（`_promptNovelMasterExtraction`）动态注入当前全局生效的时代题材与美学风格清单，由大模型自动匹配推荐最贴合的 `era_genre` 和 `aesthetic_style`，并在剧集生成时自动注入正向风格锁、时代物质锚点与三层负向避雷锁。
- **剧集世界观 Tab 交互升级**：重构 `_WorldviewTab`，淘汰写死的 6 个按钮，提供支持分类层级的美学风格下拉与时代题材 Tag 选择，支持即时预览正向与负向生效词并允许用户针对单剧进行二次微调。

## Capabilities

### Modified Capabilities
- `ai-video-studio/series-asset-library`: 增加全局可配置美学风格库与视觉时代题材库的持久化规约，规范正向锚点与三层负向避雷词结构，支持全局共享与单剧覆写。
- `ai-video-studio/novel-import`: 增加小说解构阶段动态注入全局预设清单的规约，支持大模型自动匹配并推荐最佳时代题材与美学风格，并在创建剧集资产时自动装配正负向 Prompt 约束。

## Impact

- **Affected Models & Services**:
  - `lib/tools/ai_video_studio/models/studio_models.dart`: 扩展 `VisualEraGenre` 与新增 `AestheticStyle` 数据模型，支持 JSON 序列化与可配置结构。
  - `lib/tools/ai_video_studio/services/studio_preset_store.dart`: 新增全局预设管理单例，负责磁盘读写、出厂 35 套预设自愈初始化与变更通知。
  - `lib/tools/ai_video_studio/services/prompt_assembler.dart`: 支持三层负向提示词的规范拼装。
  - `lib/tools/ai_video_studio/services/ai_constraint_engine.dart`: 小说全案第一阶段提示词由硬编码枚举改为动态模板注入。
- **Affected UI**:
  - `lib/tools/ai_video_studio/ui/series_page.dart`: `_WorldviewTab` 升级为动态分类选择器，支持实时正负向词预览。
  - `lib/tools/ai_video_studio/ui/studio_settings_dialog.dart`: 新增美学风格与时代题材的配置与管理入口。
- **File System / Persistence**:
  - 新增全局文件 `AppPaths.studioDir/presets/aesthetic_styles.json` 与 `AppPaths.studioDir/presets/visual_eras.json`。
