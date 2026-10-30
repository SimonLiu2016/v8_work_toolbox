## Why

当前工作坊的角色三视图生成存在两大体验与画质痛点：一是采用三张全身横排立绘，导致头部像素过小，系统在三视图生成后强制弹窗阻断要求用户手动框选裁切面部，破坏了一键式流水线体验；二是针对当前主力的 Agnes 系列图像模型（Agnes-Image-2.1/2.5 Flash），由于 Agnes 图像 API 不支持独立的 `negative_prompt` 入参，且天生具有过度磨皮、强镜面 CG 高光与盲盒玩具蜡像化偏置，加上既有风格词中混有 `UE5渲染`、`次世代CG` 等诱发强反光的渲染词，导致生成的人物与画面塑料感极强。

升级角色设定图排版架构为 16:9 4 区块专业角色资产图，并在正向提示词中全面注入中英双语 PBR 物理材质与去塑料感微观光影，同时彻底移除阻断式的面部截取弹窗，是提升角色 IP 资产质量与操作流畅度的关键一步。

## What Changes

- **16:9 4区块专业角色资产图架构**：三视图升级为单图自闭环架构——左侧大图为正面脸部胸像特写（清晰呈现五官、发型、妆容与上半身细节），右侧横向排列正面全身、标准 90 度侧面全身与背面全身三身立绘。正向提示词首置 `Character turnaround sheet` 英文锚点与正交平视 (`orthographic`) 约束。
- **彻底移除三视图生成后的截取面部弹窗**：生成三视图后静默入库并显示完成提示，不再自动弹出 `FaceCropDialog` 或确认弹窗。由于左侧胸像自身已具备超高分辨率面部特写，完全自满足后续生图参考需求；卡片菜单中仅保留可选的手动截取入口。
- **Agnes 专用去塑料感 PBR 材质与漫射光影注入**：在正向提示词中注入中英双语材质锁（`soft diffused studio lighting` 柔和漫射柔光、`matte surface, low specular` 哑光低高光、`natural skin pores` 自然微观毛孔、`flyaway hairs` 碎发飞毛、`subsurface scattering` 次表面散射通透感、`very subtle film grain` 细微胶片颗粒），并在正向显式追加 `not a toy, not figurine` 阻断手办蜡像偏置。
- **风格词排毒清洗与渲染词转译**：在三视图提示词组装的风格清洗阶段，主动拦截过滤 `unreal engine 5`、`ue5`、`octane render`、`cg渲染`、`3d渲染` 等在 Agnes 中诱发强镜面塑胶反光的词汇，自动转译为 PBR 物理漫射光影。
- **负向违禁词库双保险升级**：全面扩充三视图与通用负向违禁词库（涵盖 `plastic skin, waxy wax skin, oily sheen, strong specular highlight, doll, blind box toy, 塑胶人偶, 蜡像, 过度磨皮, airbrushed, 美颜滤镜, 光滑无瑕皮肤, CGI渲染, 3d玩偶, 统一光滑塑料涂层`），在支持负向词的引擎中形成第二道防崩防线。

## Capabilities

### Modified Capabilities
- `character-turnaround-sheet`: 升级三视图排版为 16:9 4 区块专业资产图，移除生成后的强制交互式裁切弹窗流程，在提示词组装中注入 Agnes 适配的 PBR 物理材质、漫射光影、防玩具正向守卫及反塑料负向防御词库。

## Impact

- `lib/tools/ai_video_studio/services/prompt_assembler.dart`: 更新 `CharacterTurnaroundPrompt` 的视角排版声明、PBR 微观肌理注入、风格词毒性过滤与防塑料负向词库。
- `lib/tools/ai_video_studio/ui/series_page.dart`: 清理 `_WorldviewTab._generateTurnaround` 中的弹窗唤起逻辑，消除阻断打扰。
- 测试套件更新：`test/tools/ai_video_studio/character_identity_and_attire_decoupling_test.dart`、`test/tools/ai_video_studio/prop_card_and_category_test.dart` 等相关单测。
