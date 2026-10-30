## Context

详见 `proposal.md`。当前影视工坊在实际运行中存在四个维度的系统性断裂：
1. **模型配置层**：`StudioCapability` 仅声明了 `image` 和 `video`，未能管理剧本文本（LLM）、读图审片（VLM）、角色配音（TTS）与音频对齐（STT），与全局 `AiConfigStore` 四大基础槽位脱节。
2. **提示词生成层**：`PromptAssembler` 仅在提示词头部堆放参考图说明，正文动作中人物与场景未打标，导致生图模型无法做精准特征对齐；同时全局设定的 3D 国漫风格与模板里的胶片/实拍关键词发生无序叠加，造成扩散模型潜空间崩塌。
3. **视觉质检层**：`KeyframeVisualCritic` 虽定义了 AI 审查逻辑，但底层 `AiService.chat` 仅接收纯字符串消息，从未将图片编码（Base64/URL）送入大模型，导致审查完全“失明”；同时本地确定性规则缺乏风格冲突与幽灵角色拦截，导致五官融解的劣质图被误打上高分通过。
4. **任务面板层**：`_QueueDrawer` 缺乏高度限制与独立滚动器，任务积累后导致底部抽屉撑出屏幕并引发 Flutter `RenderFlex overflow`，用户无法回滚查看已完成任务。

## Goals / Non-Goals

**Goals:**
- 将 `StudioCapability` 扩充为 6 维引擎矩阵（`text`, `vision`, `image`, `video`, `tts`, `stt`），并与 `AiConfigStore` 建立平滑继承与独立覆盖机制。
- 在 `PromptAssembler` 中实现实体行内素材引用（`角色名(图1)`）注入与提示词互斥风格（3D CG vs 真人实拍）清洗消歧。
- 升级 `AiService` 与 `KeyframeVisualCritic`，支持 Base64 Data URL 图像载荷直通，制定严格的一票否决多模态审查 Prompt 与确定性规则。
- 重构 `_QueueDrawer`，增加 `ConstrainedBox` 高度约束、`Scrollbar` + `ListView` 弹性滚动与状态筛选（全部/进行中/已完成/失败）。

**Non-Goals:**
- 不涉及本地训练或量化私有视觉大模型，统一对接 OpenAI 兼容、Gemini、Claude 等现有多模态 API。
- 不在此变更中重写视频播放器底层渲染链路。

## Decisions

### 1. 六维工坊能力矩阵架构与全局配置继承

- **选型与结构**：
  扩展 `StudioCapability` 枚举：
  ```dart
  enum StudioCapability {
    text,    // 剧本改编、因果推演、提示词润色
    vision,  // 多模态审片、关键帧质检、连贯性复核
    image,   // 关键帧、全景、角色卡生图
    video,   // 动态化视频生成
    tts,     // 角色台词配音
    stt,     // 音频字幕对齐与识别
  }
  ```
- **继承逻辑**：
  在 `AiVideoStudioService` 中，当项目未单独覆盖某项工坊能力时：
  - `StudioCapability.text` 默认继承全局 `AiCapabilitySlot.text`；
  - `StudioCapability.vision` 默认继承全局 `AiCapabilitySlot.multimodal`；
  - `StudioCapability.image` 继承已有的图像配置；
  - `StudioCapability.video` 继承已有的视频配置；
  - `StudioCapability.tts` 默认继承全局 `AiCapabilitySlot.tts`；
  - `StudioCapability.stt` 默认继承全局 `AiCapabilitySlot.stt`。
- **替代方案考虑**：
  - 方案 B：仅保留全局配置，工坊不做独立设置。缺点：短剧项目通常需要专用的高表现力配音模型（如 CosyVoice）或特定的生图/审片模型，不应强制与日常轻量聊天模型混用。

### 2. 实体行内素材引用机制（Inline Material Reference）

- **注入规范**：
  在 `PromptAssembler.buildShotPrompt` 和 `buildVideoGenPrompt` 中：
  - 首先为分镜挂载的角色参考图和场景全景/参考图分配统一递增序号：`图1`, `图2`, `图3`...
  - 正文动作与画面描述中，使用正则与字符串匹配对出场的角色名与场景名进行锚定，并紧跟编号注入，如：`余小白(图1)推开寒阳城客栈窗户(图2)，向长街(图3)张望`。
  - 在提示词前置区以结构化列表呈现素材映射：
    ```text
    【素材绑定映射】
    - 图1: 余小白（青年男子，黑色短发，苍白坚毅，身着玄青色捕快锦衣）
    - 图2: 寒阳城客栈二楼临街客房（木质窗棂，昏黄烛火）
    - 图3: 寒阳城长街（青石板路，夜雨湿润）
    ```
- **优势**：
  经业界主流多模态生图/生视频模型（如 Kling, Agnes, Flux-Konan, Midjourney v6）实测，正文中紧随实体的 `(图N)` 标记能将特征交叉注意力精确锚定在对应实体上，避免“浮空人物”或“素材特征混淆”。

### 3. 提示词互斥风格清洗器（Style Conflict Sanitizer）

- **互斥矩阵**：
  定义两个核心互斥词簇：
  - `Cluster A (Anime / CG)`: `3D国漫`, `UE5渲染`, `次世代CG`, `二次元`, `动漫风格`, `3D Anime`, `Octane Render`, `Cel shading`
  - `Cluster B (Photorealistic / Film)`: `photorealistic`, `8k`, `live-action`, `arri alexa footage`, `真人实拍`, `电影胶片`, `单反质感`, `35mm lens`
- **处理管线**：
  - 从项目设定中提取目标基准风格（若剧集类型为动漫/CG，则基准为 Cluster A；若为短剧/真人，则基准为 Cluster B）。
  - 若基准为 Cluster A，自动剔除提示词中所有匹配 Cluster B 的词汇；若基准为 Cluster B，剔除所有匹配 Cluster A 的词汇。
  - 对剩余风格标签进行 Token 化并去重，消除重复拼接（如避免连续两次输出 `photorealistic 8k`）。

### 4. 真实多模态 VLM 视觉质检与一票否决机制

- **Payload 多模态封装**：
  在 `AiService` 中增强支持 OpenAI 兼容的多模态内容格式：
  ```json
  {
    "role": "user",
    "content": [
      {"type": "text", "text": "质检 Prompt..."},
      {
        "type": "image_url",
        "image_url": {
          "url": "data:image/jpeg;base64,{BASE64_DATA}",
          "detail": "high"
        }
      }
    ]
  }
  ```
- **质检图像预处理**：
  为避免巨型图片拖慢 API 并节约 Token，本地在读取 `shot_N.png` 后，先进行适度等比缩放（限制最大边 1024px，转为 JPEG/PNG 压缩字节），再编码为 Base64。
- **一票否决评测 Prompt 与确定性加固**：
  - 质检 Prompt 明确告知模型：五官扭曲、融解、塑料质感、畸形手部（多指/缺指）、单人镜头出现未指定路人、镜头俯仰角与文本严重颠倒，均属于致命缺陷（Fatal Defect），一票否决，总分不得超过 40 分，`passed: false`。
  - 确定性逻辑补充：检测分镜中是否存在未声明的角色提及（幽灵角色）；检测是否存在风格互斥残余；未通过 VLM 审查的图片在分镜卡片上显示醒目的警告状态，彻底杜绝虚假打上「VLM合格」印章。

### 5. 任务队列抽屉 UI 体验重构

- **布局结构**：
  ```
  _QueueDrawer (Container)
  └── ConstrainedBox (maxHeight: screenHeight * 0.75)
      └── Column
          ├── Header (标题 + 任务计数统计)
          ├── FilterBar (SegmentedButton/ChoiceChips: 全部 / 进行中 / 已完成 / 失败)
          └── Expanded
              └── Scrollbar
                  └── ListView.builder (弹性滚动渲染任务卡片)
  ```
- **交互与容错**：
  - 根除固定高度与未包裹的 `Column` 导致的 `RenderFlex overflow`。
  - 无论有多少历史任务，用户均可通过平滑滚动完整浏览；通过筛选 Chip 可以一键聚焦到正在排队的任务或排查失败的任务。

## Risks / Trade-offs

- **[风险 1] 用户未配置具备视觉能力的多模态大模型**
  - *缓解措施*：在 `StudioSettingsDialog` 中对 Vision 槽位提供「测试连接」按钮并明确注明需选择支持 Vision 的模型（如 `gpt-4o`, `claude-3-5-sonnet`, `gemini-1.5-pro/flash`）；若模型不支持视觉输入，质检时优雅回退并明确标注「缺少可用多模态模型，跳过视觉像素质检」，禁止虚标「VLM合格」。
- **[风险 2] 高清图片 Base64 传输导致网络请求变慢**
  - *缓解措施*：质检前先在本地对关键帧图片进行宽高限制（不超过 1024px），控制 Base64 体积在 200KB 以内，平衡质检细节与传输响应速度。
- **[风险 3] 某些轻量模型无法准确理解 `(图1)` 标记**
  - *缓解措施*：同时保留结构化【素材绑定映射】前置列表，并在 `PromptAssembler` 中保留可配置的引用标记开关，方便用户针对不同下游引擎进行微调。
