## ADDED Requirements

### Requirement: stepfun 供应商类型的协议分发

`stt` 槽位的路由 SHALL 支持 `stepfun` 供应商类型的协议分发：当候选供应商为 `stepfun` 类型时，识别请求 SHALL 以 HTTP + SSE 方式调用 StepFun ASR 端点，与既有的 OpenAI Whisper multipart、MiMo chat completions 协议并列，按供应商类型元数据自动选择，无需用户手动切换。

`stepfun` 类型的流式请求在候选健康检查与失败回退上 SHALL 与其它类型一致：主候选不健康时回退到下一个候选，全部候选耗尽时抛出带槽位名与各候选最后错误的异常。

#### Scenario: stepfun 候选被优先路由

- **WHEN** `stt` 槽位的有序候选中 `stepfun` 类型供应商优先级最高且健康
- **THEN** 识别请求走 StepFun ASR SSE 协议

#### Scenario: stepfun 候选不健康时回退

- **WHEN** `stepfun` 类型候选处于冷却期，下一候选为其它协议且健康
- **THEN** 识别请求回退到下一候选，并记录降级事件
