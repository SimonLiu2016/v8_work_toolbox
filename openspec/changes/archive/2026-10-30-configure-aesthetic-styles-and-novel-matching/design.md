## Context

见 `proposal.md`。当前短视频工坊将时代题材硬编码为 8 项，美学风格写死为 6 个简单短语，缺乏正负向分层，且小说解构无法动态推荐高质量风格。

## Goals / Non-Goals

**Goals:**
- 提供全局可扩展的美学风格与时代题材持久化管理（`StudioPresetStore`），默认内置 35 套工业级美学风格与全题材世界观；
- 实现生图/生视频三层负向避雷词自动叠装（时代排他 + 风格专属 + 通用防崩）；
- 小说长文解构动态注入全局预设库，由大模型自动匹配推荐最佳 `era_genre` 与 `aesthetic_style` 并自动绑定；
- 在剧集世界观面板（`_WorldviewTab`）与工坊设置面板中提供可视化选择、微调、新增及管理界面。

**Non-Goals:**
- 不修改底层云端生图/生视频模型本身的权重或接口协议（仅在 Prompt 组装层注入规范化正向与负向词）；
- 不做云端预设同步（所有自定义预设保存在本地应用的全局 AppSupport 目录中）；
- 不破坏现有历史剧集存储结构（历史剧集的 `era_genre` 与 `style_tokens` 依然完全向前兼容）。

## Architecture & Data Flow

```
┌────────────────────────────────────────────────────────────────────────┐
│                        StudioPresetStore (全局单例)                     │
│  - AppPaths.studioDir/presets/aesthetic_styles.json                    │
│  - AppPaths.studioDir/presets/visual_eras.json                         │
│  - 35套工业级美学风格出厂自愈载入                                       │
└──────────────────┬─────────────────────────────────┬───────────────────┘
                   │ 读取可用预设                    │ 注入推荐清单
                   ▼                                 ▼
   ┌──────────────────────────────┐  ┌───────────────────────────────────┐
   │ 剧集世界观面板 (_WorldviewTab) │  │  小说解构引擎 (AiConstraintEngine)  │
   │  • 题材选择 (Tag/Chips)       │  │  • 动态注入时代与画风选项清单    │
   │  • 画风选择 (8大体系二级选择)   │  │  • LLM 输出匹配的 era & style ID │
   │  • 正向/负向词即时预览与微调   │  └─────────────────┬─────────────────┘
   └───────────────┬──────────────┘                    │ 自动回填推荐
                   │                                   │
                   ▼                                   ▼
   ┌─────────────────────────────────────────────────────────────────────┐
   │                        StudioSeries (剧集模型)                      │
   │  eraGenre: "xianxia"                                                │
   │  styleId: "ue5_3d_xianxia"                                          │
   │  styleTokens: "UE5渲染, 3D国漫, 次世代CG, PBR物理材质..."            │
   │  negativeStyleTokens: "2D手绘, Q版卡通, 畸形手部, 塑料感..."        │
   └──────────────────────────────────┬──────────────────────────────────┘
                                      │
                                      ▼
   ┌─────────────────────────────────────────────────────────────────────┐
   │                 提示词组装器 (PromptAssembler)                      │
   │  组装最终 Negative Prompt:                                          │
   │  [时代排他负向词] + [美学专属负向词] + [通用防崩防畸形词]          │
   └─────────────────────────────────────────────────────────────────────┘
```

## Decisions

### 1. 数据模型与正负向规范
- **`AestheticStyle` 数据模型**：
  ```dart
  class AestheticStyle {
    final String id;
    final String category; // 东方国风, 日系二次元, 西式CG, 科幻赛博, 实拍电影等
    final String nameZh;
    final String descriptionZh;
    final String positiveAnchor;
    final String negativeBan;
    final String defaultRatio;
    final bool isBuiltin;
  }
  ```
- **`VisualEraGenre` 增强**：保留原有 `id, labelZh, descriptionZh, costumeAnchor, environmentAnchor, propMaterialAnchor, negativeBans` 字段，增加 `isBuiltin` 并支持 JSON 序列化，方便用户自定义扩充（如民国谍战、中式怪谈）。

### 2. 存储位置与出厂自愈
- 存储路径：`AppPaths.studioDir/presets/aesthetic_styles.json` 与 `AppPaths.studioDir/presets/visual_eras.json`。
- 启动检测：若文件不存在或内容损坏，自动从内置常量（收录 35 套工业级美学风格）无损生成默认文件；若用户在自定义后希望恢复，提供“恢复出厂默认”动作。

### 3. 三层负向词去重组装
- 在 `PromptAssembler.buildNegativePrompt` 中：
  1. 收集 `eraGenre?.negativeBans`（题材层，例如古代禁现代裤、现代建筑）；
  2. 收集 `aestheticStyle?.negativeBan`（画风层，例如水墨禁 3D/写实，写实禁卡通/动漫）；
  3. 收集通用防崩词（通用层，例如“畸形手部, 多手指, 五官扭曲, 脸部崩坏, 肢体变形, 模糊, 低分辨率, 水印, logo”）；
  4. 采用逗号分词、去除首尾空格、不区分大小写去重后重组，输出整洁高效的负向 Prompt。

### 4. 小说解构动态模板注入
- 在 `AiConstraintEngine._promptNovelMasterExtraction` 中：
  - 将硬编码的 8 项枚举改为通过 `StudioPresetStore.instance` 获取已启用的题材与风格列表；
  - 动态格式化生成 prompt 片段：
    ```
    2. era_genre: 从以下题材枚举中选择最贴合的一项（...题材ID与说明列表...）
    3. aesthetic_style: 从以下美学风格枚举中选择最贴合的一项（...风格ID与说明列表...）
    ```
  - 解析 LLM 返回的 JSON 时提取 `era_genre` 与 `aesthetic_style`，并在 `StudioProjectManager.importChapterToEpisode` 中自动查找对应的预设对象，填充正负向锚点与 `styleTokens`。

## Risks / Trade-offs

- **[Risk] 用户自定义风格包含不规范字符破坏 JSON** → **Mitigation**: 使用安全 JSON 编解码与 schema 校验，解析失败时平滑回退到内置出厂预设，不崩溃。
- **[Risk] 提示词过长导致超出部分视频生成模型 Token 限制** → **Mitigation**: 负向词进行精确分词去重；通用防崩词提供精简版与完整版自适应配置。
- **[Risk] 旧剧集缺少 `aesthetic_style` 字段** → **Mitigation**: `StudioSeries` 保持字段非空默认值（空字符串），若为空则根据 `styleTokens` 文本模糊反查风格，或回退沿用现存纯文本。
