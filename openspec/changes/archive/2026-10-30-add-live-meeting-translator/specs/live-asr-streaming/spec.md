## Purpose

定义实时会议翻译工具的流式语音识别契约：通过 `stepfun` 供应商类型调用 StepFun ASR SSE 接口，把音频块转为带时间戳的识别文本，并规定断线与错误的归因行为，使字幕获得可靠且低延迟的识别来源。

## ADDED Requirements

### Requirement: 新增 stepfun 供应商协议

AI 配置 SHALL 支持 `stepfun` 供应商类型，用于 `stt` 槽位的流式识别。该协议 SHALL 以 HTTP + SSE 方式调用 StepFun ASR 端点，与既有的 OpenAI Whisper multipart、MiMo chat completions 并列，按供应商与模型元数据自动分发。

#### Scenario: stt 槽位绑定 stepfun 供应商

- **WHEN** 用户把 `stt` 槽位绑定到 `stepfun` 类型的供应商并选择 ASR 模型
- **THEN** 识别请求走 StepFun ASR SSE 协议，而非 Whisper multipart

### Requirement: 流式识别与增量文本

系统 SHALL 把音频块持续送入识别端，并消费 SSE 事件流。系统 SHALL 解析增量文本事件与完成事件：增量事件用于实时刷新当前句，完成事件用于定稿当前句并触发翻译。

系统 SHALL 在开启时间戳时为每个完成句记录起止时间，用于字幕时间轴与导出。

#### Scenario: 一句话的流式识别过程

- **WHEN** 用户说话产生一句 3 秒的语音
- **THEN** 系统先通过增量事件在悬浮窗实时显示识别中的文本，待完成事件到达后定稿该句并记录其起止时间

### Requirement: 识别语言与热词配置

系统 SHALL 允许用户配置识别语言与自定义热词。语言配置 SHALL 至少覆盖中文、英语、日语、韩语。热词 SHALL 随请求传入识别端，用于提升专有名词与术语的准确率。

#### Scenario: 配置热词后识别术语

- **WHEN** 用户把 "回滚"、"API gateway" 加入热词并开始识别
- **THEN** 识别请求携带这些热词，字幕中相应术语更可能被准确识别

### Requirement: 识别错误归因与恢复

识别请求失败或 SSE 流中断时，系统 SHALL 给出可归因的错误提示（区分鉴权失败、端点不可用、配额不足、网络中断），MUST NOT 把技术错误直接抛给用户或静默吞掉。

系统 SHALL 在可恢复的中断后自动重连并继续识别；连续重连失败 SHALL 停止识别并提示用户，MUST NOT 无限重试。

#### Scenario: 网络中断后自动重连

- **WHEN** 识别过程中网络短暂中断
- **THEN** 系统自动重连并继续识别，已定稿的字幕不丢失

#### Scenario: 鉴权失败时明确提示

- **WHEN** StepFun API Key 无效或过期
- **THEN** 系统提示鉴权失败并引导用户检查供应商配置，而不是显示空白字幕或通用错误
