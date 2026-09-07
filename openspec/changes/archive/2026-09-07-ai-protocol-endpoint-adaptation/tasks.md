## 1. 协议 URL 智能规范化与鉴权头注入

- [x] 1.1 在 `AiService` 中实现 Base URL 智能规范化辅助函数（处理末尾斜杠，探测/补齐 `/v1`）
- [x] 1.2 在 `_chatAnthropic` 和 `_discoverAnthropicModels` 中注入双重鉴权头（`x-api-key` 和 `api-key`）
- [x] 1.3 在 `_chatOpenAi` 和 `_discoverOpenAiModels` 中添加 `api-key` 头部兼容支持
- [x] 1.4 在 `_discoverOpenAiModels` 中添加自适应回退逻辑：当 `$baseUrl/models` 返回 404 时自动尝试 `$baseUrl/v1/models`

## 2. Anthropic 网关端点自适应探测与记忆

- [x] 2.1 在 `AiService` 中添加 `Map<String, String> _resolvedChatEndpoint` 内存缓存
- [x] 2.2 在 `_chatAnthropic` 中实现自适应端点试探：优先尝试已缓存端点，未缓存时按优先级尝试 `['$baseUrl/anthropic/v1/messages', '$baseUrl/v1/messages', '$baseUrl/messages']`
- [x] 2.3 当候选端点返回 200 时，将其写入 `_resolvedChatEndpoint` 缓存；在供应商删除或更新时清理缓存
- [x] 2.4 在 `_discoverAnthropicModels` 中添加模型探测候选路径回退：若 `$baseUrl/v1/models` 或 `$baseUrl/models` 404，尝试根路径下的 `/v1/models`

## 3. 两阶段真机连通性验证（Ping 校验）

- [x] 3.1 在 `AiService` 中实现轻量级 `_pingProvider(AiProviderConfig provider, {String? model, String? apiKey})` 方法，发送单字 prompt 校验实际推理能力
- [x] 3.2 重构 `testConnection(AiProviderConfig provider, {String? apiKey})`：先调用 `discoverModels`，再调用 `_pingProvider`，两者皆通过才返回 true
- [x] 3.3 当第一阶段成功但第二阶段失败时，透传结构化错误信息（例如：“模型列表获取成功，但对话接口返回 404：请确认网关路由”），并在 UI 中清晰展示

## 4. 自动化测试与验证

- [x] 4.1 编写 Anthropic 网关端点自适应单元测试（模拟 `/anthropic/v1/messages` 成功而 `/v1/messages` 404 场景）
- [x] 4.2 编写 Anthropic 双鉴权头注入验证测试（验证请求包含 `x-api-key` 和 `api-key`）
- [x] 4.3 编写 OpenAI 无 `/v1` 自动补齐单元测试（验证 `https://host.com` 自动补齐为 `/v1/models` 和 `/v1/chat/completions`）
- [x] 4.4 编写两阶段连接测试单元测试（模型成功 + 对话失败，断言抛出明确错误）
- [x] 4.5 运行 `flutter analyze --no-fatal-infos` 确认 0 错误 0 警告，所有测试通过
