## ADDED Requirements

### Requirement: Builtin Mimo Provider Candidate
系统 SHALL 提供小米 MiMo 供应商的快速填充预设，预填 MiMo API 模式（按量计费）的服务地址与其文本、语音合成、语音识别模型标识。预填的模型 SHALL 覆盖 MiMo 当前在售的 TTS、STT 与文本型号，并按用途分别填入对应槽位，使用户无需手工查文档即可配齐三槽位。预设的协议类型 SHALL 为 OpenAI 兼容协议，且 SHALL NOT 新增专用协议枚举值。

#### Scenario: One preset fills all three slots
- **WHEN** 用户在添加供应商时激活 MiMo 快速填充预设
- **THEN** 系统填入 MiMo 的 API 模式服务地址 `https://api.xiaomimimo.com/v1`、OpenAI 兼容协议类型，以及分别用于文本、TTS、STT 槽位的 MiMo 模型标识
- **AND** 用户 SHALL 能直接进入连接验证，无需手工查找模型名称

#### Scenario: TTS model is the currently served mimo-v2.5-tts
- **WHEN** 用户激活 MiMo 快速填充预设
- **THEN** TTS 槽位预填模型 SHALL 为 `mimo-v2.5-tts`
- **AND** 该模型 SHALL 为官方 `/v1/models` 列表当前仍提供、且经真机合成返回合法音频的型号

#### Scenario: Text models use the v2.6 series
- **WHEN** 用户激活 MiMo 快速填充预设
- **THEN** 文本槽位预填模型 SHALL 为 `mimo-v2.6-flash` 与 `mimo-v2.6-pro`
- **AND** 预设 SHALL NOT 包含已下线（2026-10-21 起）的 `mimo-v2.5` / `mimo-v2.5-pro`

#### Scenario: Preset must not expose Token Plan subscription route
- **WHEN** 用户激活 MiMo 快速填充预设
- **THEN** 预填的 Base URL SHALL 为 API 模式地址 `https://api.xiaomimimo.com/v1`
- **AND** 预设 SHALL NOT 预填任何 Token Plan 订阅地址（`token-plan-cn` / `token-plan-sgp` / `token-plan-ams` 等 `*.xiaomimimo.com` 集群）或 `tp-` 前缀 Key
- **AND** 预设 SHALL NOT 提供「Token Plan 会员」快捷入口（对齐 Qwen 的双入口先例，MiMo 仅保留 API 模式单一入口）

#### Scenario: Preset respects user-entered Base URL
- **WHEN** 用户激活 MiMo 快速填充预设，且当前 Base URL 输入框已填有非 MiMo 的地址
- **THEN** 预设 SHALL NOT 覆盖用户已输入的自定义地址，除非当前值为空或为 MiMo API 默认地址
- **AND** 模型标识 SHALL 仍按预设填充，供用户仅需修正地址即可
