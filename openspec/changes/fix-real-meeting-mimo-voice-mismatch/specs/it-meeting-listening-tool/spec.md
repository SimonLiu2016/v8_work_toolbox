## MODIFIED Requirements

### Requirement: 角色到音色的稳定映射

系统 SHALL 为每个说话人分配一个语音音色，且同一角色在不同片段、不同场景中 SHALL 始终使用同一音色，使用户能通过声音辨识说话人。映射 SHALL 覆盖男性与女性两类音色，且不依赖音色名称的字面含义（音色名与实际音高不符时以标注为准）。

系统 SHALL 为每条素材保存其实际使用的音色分配，使生词本与听力练习的播放可追溯某段音频由哪个音色朗读。当 TTS 槽位绑定到小米 MiMo 时，音色候选 SHALL 包含 MiMo 官方预置音色，且用户 SHALL 能直接选择 MiMo 音色而不被被动回退到默认音色。此约束 SHALL 同样适用于真实会议的「说话人与音色」界面、「我的身份」对话框、说话人散列兜底与烘焙管线：在 MiMo 下，它们 SHALL 产出或展示合法 MiMo 音色标识，SHALL NOT 把用户选择的音色或散列兜底音色静默替换为 `mimo_default`。

#### Scenario: 同一角色跨场景音色一致

- **WHEN** 名为 "Lena" 的说话人分别出现在站会片段与故障排查片段中
- **THEN** 这两个片段中由 Lena 朗读的音频使用完全相同的音色

#### Scenario: 音色分配可追溯

- **WHEN** 用户查看某素材的详情
- **THEN** 系统展示该素材每一轮次所使用的音色标识

#### Scenario: 生词本在 MiMo 下可选 MiMo 音色

- **WHEN** 系统 TTS 槽位绑定到 MiMo 且用户在生词本/听力练习的播放区选择音色
- **THEN** 音色候选 SHALL 列出 MiMo 官方预置音色（如 `mimo_default` / 冰糖 / 茉莉 / 苏打 / 白桦 / Mia / Chloe / Milo / Dean）
- **AND** 用户选择的 MiMo 音色 SHALL 被直接发往合成请求，而 SHALL NOT 被替换为 `mimo_default`（除非所选音色不在 MiMo 支持列表内）

#### Scenario: 生词本在非 MiMo 下沿用角色音色池

- **WHEN** 系统 TTS 槽位绑定到非 MiMo 供应商（如 StepFun）
- **THEN** 音色候选 SHALL 沿用既有 `VoicePool` 音色池，行为不变

#### Scenario: 真实会议在 MiMo 下可选 MiMo 音色

- **WHEN** 系统 TTS 槽位绑定到 MiMo 且用户在真实会议的「说话人与音色」页签或「我的身份」对话框中调整说话人音色
- **THEN** 音色候选 SHALL 列出 MiMo 官方预置音色（如 `mimo_default` / 冰糖 / 茉莉 / 苏打 / 白桦 / Mia / Chloe / Milo / Dean），而非 StepFun 角色音色池
- **AND** 用户选择的 MiMo 音色 SHALL 在点击「重新合成」后被直接发往合成请求
- **AND** 合成结果中该角色的声音 SHALL 对应所选 MiMo 音色，SHALL NOT 为 `mimo_default`

#### Scenario: 真实会议散列兜底在 MiMo 下仍可听声辨人

- **WHEN** 系统 TTS 槽位绑定到 MiMo，且某说话人未显式指定音色（依赖散列兜底）
- **THEN** 该说话人解析到的音色 SHALL 是 MiMo 合法音色标识（位于 MiMo 支持列表内）
- **AND** 不同说话人 SHALL 以高概率解析到不同 MiMo 音色，而非全部收敛到 `mimo_default`

#### Scenario: 真实会议在非 MiMo 下沿用角色音色池

- **WHEN** 系统 TTS 槽位绑定到非 MiMo 供应商（如 StepFun）
- **THEN** 真实会议的音色候选、散列兜底与「我的身份」默认值 SHALL 沿用既有 `VoicePool` 音色池，行为不变

#### Scenario: 真实会议烘焙在 MiMo 下透传风格指令

- **WHEN** 系统 TTS 槽位绑定到 MiMo 且真实会议烘焙触发合成
- **THEN** 合成请求 SHALL 透传 MiMo 风格指令（自然语言语速/情感调节），使合成结果具备可感知语气
