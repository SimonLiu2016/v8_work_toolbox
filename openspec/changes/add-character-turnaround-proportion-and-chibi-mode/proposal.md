# Change Proposal: add-character-turnaround-proportion-and-chibi-mode

## Why

在 AI 视频工坊的角色三视图生成中，文生图大模型（如 FLUX / SDXL / Midjourney）受训练集三视图素材（大量包含游戏粘土周边图纸、贴纸表情）的关联偏置影响，在未显式约定体态比例时容易随机生成大头小身的 Q 版（Chibi / SD）动漫形象。

同时，在网络文学与动漫短剧创作实践中（如《师兄啊师兄》/《我师兄实在太稳健了》），同一主角往往既需要高燃帅气的“标准 7~8 头身修长本体”，又需要在纸人化身出巡、暗中观察或内心戏吐槽时切换为“2.5 头身 Q 版小人”。

因此，系统需要在角色卡三视图生成环节提供明确的比例选择（标准成人 vs Q版萌系），默认严密抑制 Q 版漂移，同时支持为同一角色并存生成两套三视图并无缝绑定到角色形态（Variations）中。

## What Changes

1. **体态比例模型 (`CharacterTurnaroundProportion`)**：
   - 定义 `standard`（标准全身比例，7~8头身，默认）与 `chibi`（Q版萌系，2.5头身大头小身）；
   - 标准比例正向锚定成人修长骨骼与比例，负向严格互斥拦截 `chibi, super deformed, SD, q-version, big head small body, oversized head, 2-head-tall, toddler proportions, miniature figurine`；
   - Q 版萌系正向锚定萌态可爱大头圆脸，负向拦截高挑成熟与写实面部特征。

2. **提示词组装引擎升级 (`CharacterTurnaroundPrompt`)**：
   - `build` 与 `buildNegative` 引入 `CharacterTurnaroundProportion` 入参，与剧集 `eraGenre`（时代锁）及 `styleTokens`（风格锁）深度复合；
   - 杜绝生成标准角色时由于词汇模糊意外滑入 Q 版。

3. **角色卡交互升级 (`_CharacterCard`)**：
   - 将原单点按钮升级为下拉操作按钮（`PopupMenuButton`）：
     - `● 生成标准比例三视图（7~8头身，默认）`
     - `○ 生成 Q版萌系三视图（2.5头身，纸人/内心戏）`
   - 一键直接触发生成，避免打断创作心流的确认弹窗。

4. **双轨产物与形态联动**：
   - 标准产物写 `turnaround.png`（或 `turnaround_standard.png`），Q版写 `turnaround_chibi.png`；
   - 参考图栏中均被标识为三视图（显示“三视图”或“Q版三视图”专属徽标）；
   - 生成 Q 版三视图后，支持一键在角色卡中创建绑定的「Q版形态」（`CharacterVariation`），供分镜按需切换；
   - 收进资产库时自动分类打上对应标签（`[角色名, '三视图', '标准比例']` 或 `[角色名, '三视图', 'Q版萌系']`）。

## Capabilities

### Modified Capabilities
- `ai-video-studio/series-asset-library`: 角色卡三视图生成支持体态比例模式选择（标准全身 vs Q版萌系）、提示词互斥排他、产物并存与形态联动绑定。

## Impact
- 涉及文件：
  - `lib/tools/ai_video_studio/models/studio_models.dart`（新增 `CharacterTurnaroundProportion` 枚举）
  - `lib/tools/ai_video_studio/services/prompt_assembler.dart`（升级 `CharacterTurnaroundPrompt` 组装）
  - `lib/tools/ai_video_studio/ui/series_page.dart`（升级角色卡三视图按钮交互、产物落盘与形态快捷创建）
  - `test/tools/ai_video_studio/`（对应测试用例扩充）
- 向后兼容：旧有 `turnaround.png` 自动视作标准三视图继续有效，不影响已生成的既有剧集与分镜。
