## 1. 适配器工厂与系统配置集成

- [x] 1.1 在 `lib/tools/ai_video_studio/services/video_gen_adapter.dart` 中为 `VideoGenAdapterFactory` 增加对 `system-video` 偏好 ID 的直接支持，并提供获取当前系统绑定视频模型摘要信息的辅助方法
- [x] 1.2 重构 `lib/tools/ai_video_studio/ui/studio_settings_dialog.dart` 中的视频引擎列表，将「🌟 跟随系统配置」作为首选默认项，并动态从 `AiConfigStore` 渲染当前绑定的供应商和模型名称

## 2. 工坊设置界面与交互打通

- [x] 2.1 在 `lib/tools/ai_video_studio/ui/studio_settings_dialog.dart` 中，针对选中「跟随系统配置」时隐藏独立 Key 输入框，显示密钥托管状态提示与「前往系统 AI 配置」跳转按钮
- [x] 2.2 重构 `_StudioSettingsDialogState._test` 可用性检测逻辑，针对系统配置视频引擎执行连通性与 Key 有效性探测，并提供直观反馈

## 3. 验证与本地部署

- [x] 3.1 编写并运行单元测试验证工坊设置对系统视频模型的识别与可用性探测逻辑
- [x] 3.2 执行 `flutter analyze` 确保全局无编译与静态分析错误
- [x] 3.3 执行 `./scripts/deploy_local.sh` 完成本机构建并替换部署
