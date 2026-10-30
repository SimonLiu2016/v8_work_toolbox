## Purpose

为实时会议翻译提供 StepFun ASR SSE 流式识别通信、端点路径适配以及启动前供应商与槽位健康预检机制。

## ADDED Requirements

### Requirement: StepFun ASR SSE 端点自适应解析与流式通信

系统 SHALL 支持根据 StepFun 供应商的 Base URL 自动匹配并解析流式识别端点，同时支持开放平台（`/v1/audio/asr/sse`）与 Step Plan 专属路径（`/step_plan/v1/audio/asr/sse`），并通过 HTTP + SSE 单向流推送 PCM 音频并解析实时识别事件（delta 与 done 增量/定稿文本）。

#### Scenario: 针对 Step Plan 路径发起流式 ASR

- **WHEN** 绑定的 StepFun 供应商 Base URL 为 `https://api.stepfun.com/step_plan/v1`
- **THEN** 系统解析并向 `https://api.stepfun.com/step_plan/v1/audio/asr/sse` 发送带 Authorization 和音频 Base64 负载的 POST 请求，并成功接收 SSE 事件流

#### Scenario: 针对开放平台常规路径发起流式 ASR

- **WHEN** 绑定的 StepFun 供应商 Base URL 为 `https://api.stepfun.com/v1`
- **THEN** 系统解析并向 `https://api.stepfun.com/v1/audio/asr/sse` 发起识别请求

### Requirement: 实时翻译启动识别前 ASR 槽位与客户端预检

在用户点击“开始识别”时，系统 SHALL 在启动底层音频捕获前校验 `stt` 槽位是否已配置可用的 StepFun 协议供应商及有效凭据；若预检失败，系统 SHALL 立即阻止启动并弹出明确的指引提示，MUST NOT 允许系统进入无 ASR 客户端的伪运行状态。

#### Scenario: 未配置有效 StepFun 供应商时拦截启动

- **WHEN** 用户点击“开始识别”，但当前 `stt` 槽位未绑定任何供应商，或绑定的供应商协议不为 StepFun，或缺少可用 API Key
- **THEN** 系统立即中断启动操作，保持“空闲”状态，并弹出提示说明需在 AI 能力配置中配置 StepFun 供应商并绑定 STT 槽位
