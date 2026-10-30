## Context

当前漫剧工作台在生成音频与组装视频 Prompt 时，存在三个关键设计缺陷：
1. **TTS 与 Prompt 直出未净化**：台词中残留的 `姜七夜（内心 OS）：` 与 `（预估2.5秒）` 因正则覆盖不全被当成台词朗读；
2. **说话人推导盲目**：TTS 音色绑定直接取 `characterIds.first`，视频生成则从 `actionZh` 盲目扫描，当多人在场或心声提及他人时极易错配说话人；
3. **本地节拍映射污染**：`convertScenesToShots` 缺乏对内心独白的过滤，心声中出现的非在场角色名被强制加入 `characterIds`；
4. **多角色同框全景发型丢弃**：`PromptAssembler` 在 `hasCharacterRef` 时丢弃了角色的 `facialFeaturesZh`，导致全景/远景镜头下模型失去文字锚定、发型突变。

## Goals / Non-Goals

**Goals:**
- 提供全局统一的 `PromptAssembler.cleanDialogueForSpeech(String dialogue)` 方法，剥离一切人名前缀、内心 OS 标记与预估秒数，确保 TTS 与视频口型只拿到干净台词。
- 提供 `PromptAssembler.extractSpeakerName(String dialogue, {String defaultSpeaker = ''})`，精准捕获台词的真实说话人。
- 在 `sound_design_panel.dart` 与 `studio_generation_tasks.dart` 中，将音色绑定和说话人解析对齐到真实说话人，彻底废除 `characterIds.first` 盲选。
- 改造 `AiConstraintEngine.convertScenesToShots`：当台词为内心独白时，禁止使用台词文本匹配出场角色。
- 改造 `PromptAssembler.resolveCharacterStaging`：在多角色同框时，无论是否有参考图，均无条件将角色的核心容貌/发型特征（`facialFeaturesZh`）追加到同框站位描述中。

**Non-Goals:**
- 不改变底层 TTS 引擎（如 Edge-TTS）的通信协议。
- 不影响单角色特写镜头的已有提示词编译规则。

## Decisions

### 1. 集中化台词发声净化器（`cleanDialogueForSpeech`）
- **决策**：使用健壮的多层正则依次剔除：
  1. `（预估[\d\.]+秒）`、`(预估[\d\.]+s)`、`（[\d\.]+秒）` 等时长注记；
  2. `^.*?[（\(](?:内心\s*OS|OS|心声)[）\)][：:]?\s*`（匹配如 `姜七夜（内心 OS）：` 或 `（内心 OS）：`）；
  3. `^[^：:\n\r]{1,10}[：:]\s*[“"']?`（匹配普通说话人前缀如 `老王：“`）；
  4. 剥离首尾残留的括号、引号 `“”"'` 与多余空白。

### 2. 说话人提取策略（`extractSpeakerName`）
- **决策**：优先从 `dialogue` 头部抓取冒号前的姓名，并在角色库列表中通过姓名或别名解析匹配；未抓取到时依次回退到 `beat.dialogueSpeaker`、`characters.first`。

### 3. 本地节拍映射心声隔离
- **决策**：在 `convertScenesToShots` 中，若 `isInnerVoice` 为 true，出场角色匹配范围 `textScope` 仅由 `beat.dialogueSpeaker + ' ' + beat.action` 组成，严格排除 `beat.dialogue`。

### 4. 容貌特征文本双重锚定（双重锁定）
- **决策**：在 `resolveCharacterStaging` 中，将角色的 `facialFeaturesZh`（或 `effectiveFacialPrompt`，如“头发花白稀疏，面容浮肿”）拼接在站位之后，使图像生成模型在远景/全景时依然接收到强约束文本。

## Risks / Trade-offs

- **[Risk] 台词中包含合法冒号** → **[Mitigation]** 限制说话人前缀长度在 1-10 字符之间且紧随开引号或内心 OS 标记，避免正文句子中的冒号被误切。
