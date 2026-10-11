## 1. 协议核心与基础设施扩展

- [x] 1.1 在 `AiProtocolType` 枚举中添加 `agnes` 并完善序列化与标签
- [x] 1.2 在 `AiService` 中为 `AiProtocolType.agnes` 接入模型探测、连接测试与文本对话逻辑
- [x] 1.3 在 `AiConfigPage` 中增加 Agnes 协议选项与「Agnes / 中转站 (视/图多模态)」快速预设

## 2. 图像生成适配器规范化与解耦

- [x] 2.1 重构 `SystemAiImageAdapter`：对 Agnes 模型/协议固定 `/v1/images/generations` 端点并精简 payload 为 `{"model": "...", "prompt": "..."}`
- [x] 2.2 确保生图响应兼容解析 `data[0].url` 与 `data[0].b64_json`，并支持本地下载

## 3. 视频生成适配器规范化

- [x] 3.1 规范化 `AgnesVideoAdapter` 任务创建端点与请求体
- [x] 3.2 优化 `AgnesVideoAdapter` 任务状态轮询，对齐 `/v1/videos/{taskId}` 与官方回退接口

## 4. 验证与本地应用部署

- [x] 4.1 编写单元测试验证 Agnes 协议解析与生图 payload 结构
- [x] 4.2 运行自动化测试并通过
- [x] 4.3 执行 `./scripts/deploy_local.sh` 编译并替换本机应用
