## Why

当前短视频工坊在小说导入与剧本改编管线中存在两大关键阻碍与历史技术包袱：
1. **剧本割裂与人设崩塌**：小说影视化提示词严重受“下沉爆款短剧/前3秒爆发核心危机”等刻板模板污染，将松弛腹黑、掌控全场的主角强行格式化为“长街受辱”式的低俗打脸套路，且彻底缺失了网文核心精髓——【角色内心独白（OS）】，导致生成的剧本支离破碎、阅读体验极差。
2. **过时的英文提示词包袱**：系统遗留了 2022~2023 年 SD1.5/CLIP 时代的英文咒语堆砌习惯（如 `UE5 render`, `Octane render`, `chubby young master` 等），在面向 Agnes、即梦、可灵等现代国产原生大模型时，这种中英混杂、词汇冲突的 Prompt 严重稀释了核心动作权重、丢失东方仙侠/武侠神韵，并引发生成动作漂移与材质崩坏。

重构剧本为标准影视文学分场剧本（原生支持内心 OS）并全面切换为原生纯中文导演提示词体系，是让系统生成好剧本与高质感视频的必然基石。

## What Changes

- **文学分场剧本与内心 OS 一等公民化**：
  - 清除小说改编与分集大纲中的低俗短剧刻板诱导词（如“爆款短剧”、“前3秒核心危机”），建立原著基调自适应机制，坚决捍卫主角人设与爽点内核，杜绝《长街受辱》式魔改；
  - 在剧本场次与节拍（`DramaBeat`）中正式引入 `inner_voice`（角色内心独白/OS），与 `dialogue`（对外发声对白）和 `narration`（旁白）明确分流；
  - 剧本 Markdown 导出与展示升级为标准影视文学剧本排版（如 `姜七夜（内心 OS）：...`），实现行云流水的阅读与编辑体验。
- **提示词全面转向原生纯中文导演语言**：
  - 彻底废弃生图与视频生成中的英文咒语堆叠（移除 `UE5 render`, `Octane render`, `masterpiece` 等历史包袱）；
  - 移除中英混杂模式，统一使用纯中文描述角色外貌形制、场景空间光影与微动作镜头语言；
  - 重构 `PromptAssembler`，生成发往 Agnes / 即梦 / 可灵 / SenseAudio 的原生纯中文提示词；
  - 统一音画分流规则：角色画面保持自然微闭口神态，台词与内心 OS 剥离为后期配音音轨，避免画面汉字乱码与嘴型畸变。

## Capabilities

### New Capabilities
*(无新建独立 Spec 目录，所有变更均针对现有工坊核心能力做标准升级)*

### Modified Capabilities
- `ai-video-studio/script-workshop`: 结构化剧本与拆镜规范升级：移除对“英文生图 Prompt”的强制要求，转向原生纯中文导演提示词；在剧本节拍中增加内心独白（OS）支持与原著人设调性保护规则。
- `storyboard-visual-composition`: 视听提示词组装规范升级：移除英文标签堆叠与冲突渲染器咒语，确立纯中文【主体形制 + 场景光影 + 镜头动作】组装标准，实现所见即所得。
- `ai-video-studio/novel-import`: 小说长文导入与分集大纲改编升级：单章提炼与分集规划尊重原著人物性格与爽点内核，剔除狗血短剧套路与受辱刻板模板，输出高品质文学分场剧本与纯中文资产卡。

## Impact

- **Affected Code**:
  - `lib/tools/ai_video_studio/services/ai_constraint_engine.dart`: 重构 `_promptNovelDramaChapterAdaptation`, `_promptScreenplayGeneration`, `_promptNovelEpisodeSegmentation` 系统提示词与输出契约。
  - `lib/tools/ai_video_studio/models/drama_director_contract.dart`: 在 `DramaBeat` 中增加发声类型及内心独白支持。
  - `lib/tools/ai_video_studio/ui/screenplay_panel.dart`: 升级文学剧本 Markdown 导出与人机交互展示。
  - `lib/tools/ai_video_studio/services/prompt_assembler.dart`: 全面重构 `compileShot`, `compileSegment`, `buildVideoGenPrompt` 为原生纯中文导演语言编译器。
- **Dependencies & APIs**: 零新增外部依赖；不破坏既有数据存储结构（向后兼容）。
