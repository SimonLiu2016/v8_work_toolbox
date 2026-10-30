## Context

当前系统在角色资产构建流程中存在以下约束与现状：
1. **排版与尺寸**：[`CharacterTurnaroundPrompt`](file:///Users/simon/ClaudeWorkspace/V8WorkToolbox/lib/tools/ai_video_studio/services/prompt_assembler.dart#L1592) 当前仅指导模型横排生成三个全身站立视角，头部像素占比偏小。
2. **网关契约**：[`SystemAiImageAdapter`](file:///Users/simon/ClaudeWorkspace/V8WorkToolbox/lib/tools/ai_video_studio/services/image_gen_adapter.dart#L1058) 对接的 Agnes 图像网关（`agnes-image-2.1/2.5-flash`）不支持独立的 `negative_prompt` 参数（提交即报 HTTP 400），负向词在网关侧被自动剔除。因此单纯依赖负向词无法抑制 Agnes 的塑料打蜡偏置。
3. **UI 强打扰交互**：[`series_page.dart`](file:///Users/simon/ClaudeWorkspace/V8WorkToolbox/lib/tools/ai_video_studio/ui/series_page.dart#L381-L412) 在三视图生成完成后，自动通过弹窗唤起 `FaceCropDialog` 或询问重新裁切，阻断了流畅出图体验。

## Goals / Non-Goals

**Goals:**
- 将角色三视图升级为单图自闭环的 16:9 4 区块专业角色资产图（左侧大胸像特写 + 右侧 3 身立绘）。
- 在 `CharacterTurnaroundPrompt` 正向提示词中注入 Agnes 适配的中英双语 PBR 物理材质、漫射柔光与防手办违禁守卫。
- 在风格词清洗中过滤 `UE5`、`Octane`、`CG渲染` 等诱发 Agnes 强镜面高光的词汇，转译为 PBR 物理漫射光影。
- 彻底移除三视图生成完成后的自动弹窗交互，实现静默入库与轻量通知。
- 扩充并强化负向违禁词库作为支持负向词引擎的第二道防线。

**Non-Goals:**
- 不修改视频生成任务或视频适配器协议。
- 不废弃角色卡右键/更多菜单中原有的可选“手动截取面部”辅助功能。
- 不改变体态比例（如成人标准与 Q 版萌系）的切换与存储逻辑。

## Decisions

### 1. 正向双语微观材质注入（对抗 Agnes 负向词缺位）
- **方案**：由于 Agnes API 拒绝 `negative_prompt`，我们将核心去塑料约束全部直接编排进 Positive Prompt：
  `soft diffused studio lighting`（核心柔漫射光）、`matte surface, low specular`（哑光低高光）、`natural skin pores`（毛孔肌理）、`flyaway hairs`（细碎碎发）、`subsurface scattering`（次表面散射）、`PBR physically based shading`，并在正向尾部显式声明 `not a toy, not figurine`。
- **替代方案**：尝试强行给 Agnes API 发送 negative_prompt → 失败，上游服务返回 400 校验错误。

### 2. 16:9 4 区块专业角色资产图单图闭环
- **方案**：采用国际主流的角色板（Turnaround Sheet）排版：
  ```
  [左侧 1/3~2/5 区域]：正面脸部胸像大图特写（清晰五官、发型、妆容与上半身细节）
  [右侧 3/5~2/3 区域]：横向排列正面全身、90 度侧面全身、背面全身
  ```
  通过 `Character turnaround sheet` 与 `orthographic`（正交平视）首置提示词，单次生成出图。
- **替代方案**：分两步生成（先生成头像，再以图生图生成三视图）→ 存在两次网络调用的延迟、成本翻倍及两次间服饰不一致的风险。

### 3. 彻底移除生成后弹窗与非阻断入库
- **方案**：三视图生成完毕后，立即保存文件并执行 `_manager.saveCharacter`，随后通过 `ScaffoldMessenger` 提示成功，直接返回正常界面。移除原先对 `_cropFaceAnchorFromTurnaroundFile` 的自动唤起以及 `AlertDialog` 询问逻辑。
- **替代方案**：通过算法自动裁剪头像 → 依赖额外的图像人脸检测模型，增加安装包体积与跨平台运行复杂度；而左侧大图本身已是胸像特写，供扩散模型做 IP 参考无需切图。

### 4. 风格词清洗中排毒与渲染词转译
- **方案**：在 `cleanTurnaroundStyleTokens` 中追加引擎词拦截：`unreal engine 5`、`unreal`、`ue5`、`octane`、`octane render`、`cray`、`3d渲染`、`cg渲染`。若原风格中含有这些词，自动过滤并注入 `PBR physically based shading，soft diffused lighting`。
- **替代方案**：保留 UE5 词汇由用户自行承担后果 → Agnes 必然产出反光极重的高光塑料玩具，体验极差。

## Risks / Trade-offs

- **[Risk] 既有单元测试对三视图提示词包含特定子串的断言可能失败**  
  → **Mitigation**: 保持 `正面平视`、`侧面`、`背面`、`同一角色` 等核心语义关键词在模板中的顺序与存在，同时扩展单测对 4 区块和 PBR 关键词的覆盖断言。
- **[Risk] 极少数用户仍需要独立的 1:1 头像图片展示在某些 UI 列表中**  
  → **Mitigation**: 保留角色卡更多菜单里的「截取面部特写锚点」手动入口，满足特殊定制需求，但绝不强行弹窗打扰常规流程。
