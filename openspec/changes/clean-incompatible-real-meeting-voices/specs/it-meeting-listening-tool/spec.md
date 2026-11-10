## MODIFIED Requirements

### Requirement: 角色到音色的稳定映射

系统 SHALL 为每个说话人分配一个语音音色，且同一角色在不同片段、不同场景中 SHALL 始终使用同一音色，使用户能通过声音辨识说话人。映射 SHALL 覆盖男性与女性两类音色，且不依赖音色名称的字面含义（音色名与实际音高不符时以标注为准）。

系统 SHALL 为每条素材保存其实际使用的音色分配，使生词本与听力练习的播放可追溯某段音频由哪个音色朗读。当 TTS 槽位绑定到小米 MiMo 时，音色候选 SHALL 包含 MiMo 官方预置音色，且用户 SHALL 能直接选择 MiMo 音色而不被被动回退到默认音色。

当系统切换 TTS 供应商或加载包含跨厂商历史音色配置的真实会议时，系统 SHALL 自动检测并清洗不兼容的音色标识（不在当前供应商合法候选音色列表内的 `voiceId`）：
- 系统 SHALL 将该无效音色配置重置为空，使其透明平滑地回退到当前供应商音色池内的合法散列兜底音色；
- 系统 SHALL 将清洗后的说话人配置回写并持久化，SHALL NOT 将跨厂商的非法音色作为有效音色透传给烘焙链路，避免因底层的安全兜底导致所有说话人沦为单一的默认音色（如 `mimo_default`）；
- 真实会议的待更新组数（Pending Groups）比对逻辑 SHALL 始终基于当前供应商下的合法期望音色与已落盘音频的实际合成音色；在用户点击重新合成完成后，已更新组的烘焙音色标识 SHALL 与期望音色精准对齐，待更新计数 SHALL 彻底归零，SHALL NOT 出现无法清除的待更新残留；
- 「我的身份」（MyIdentity）在跨供应商加载时也 SHALL 遵循此清洗校验规则，确保标记为「是我」的说话人使用当前供应商支持的音色。

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

#### Scenario: 跨供应商历史音色自动清洗与散列兜底

- **WHEN** 系统当前 TTS 绑定为 MiMo，而某真实会议的历史配置中存在 StepFun 音色（如 `shenchennanyin` / `zhixingjiejie`）
- **THEN** 系统解析与加载该会议时自动将该不兼容音色识别为无效并清除，使其回退为 MiMo 候选池内的合法散列音色并自动持久化
- **AND** 后续合成时每个说话人均采用合法的 MiMo 官方音色，播放时呈现不同角色的清晰差异，不被降级为同一单一音色

#### Scenario: 重新合成后待更新组数干净归零

- **WHEN** 真实会议因说话人音色变更或历史清洗而出现 N 组待更新，用户点击重新合成
- **THEN** 系统按当前有效音色执行合成并回填写入烘焙状态 `TurnGroupAudio.voiceId`
- **AND** 重新合成成功后，系统刷新待更新计算，待更新组数立即归零（为 0 组），状态显示「● 已合成」
