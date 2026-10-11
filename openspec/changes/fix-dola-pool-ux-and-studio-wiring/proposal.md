## Why

用户在体验内置 Dola 号池与 AI 视频工坊时，遇到了以下四个阻塞性体验与逻辑问题：
1. **Cookie 提取门槛高**：手动在外部浏览器 F12 抓包复制 `sessionid` 对小白极不友好，缺少便捷直观的 Cookie 获取方式。
2. **探活端点错误**：Dola 探活请求打到了不存在的路径导致 404/网络报错，未能使用正确的逆向协议端点。
3. **工坊引擎设置状态未持久化**：工坊设置弹窗内的引擎选择仅为内存态，关闭后再打开又变回跟随系统，且测试可用性缺少 Dola 号池分支。
4. **看板视频报错弹窗溢出与不可复制**：未生成关键帧直接点击视频生成时出现报错，且报错展示缺少滚动保护与一键复制功能。

## What Changes

- **便捷 Cookie 获取与登录引导**：
  - 在号池管理面板提供「一键快捷提取」JavaScript 小书签与直达网页登录引导，并在检测到外部/伴侣浏览器数据时提供一键导入支持。
- **修复真实 Dola 登录与探活端点**：
  - 对齐 `pure_api_gen.py`，改用真实的 `POST https://www.dola.com/alice/user/get_web_anon_id` 与请求签名，以响应头 `x-tt-agw-login: 1` 判定登录态，探活成功并校正剩余点数。
- **工坊引擎选择持久化与测试可用性修复**：
  - 在 `SettingsStore` 中持久化保存 `studio_preferred_image_engine` 与 `studio_preferred_video_engine`。
  - 在 `StudioSettingsDialog._test()` 中补齐 `dola-pool-*` 可用性测试逻辑。
- **分镜看板错误保护与可复制弹窗**：
  - 在点击「视频」前增加首帧前置检查：若该分镜无关键帧，提示“请先生成首帧画面”，避免抛错。
  - 将所有错误详情弹窗与看板错误信息重构为支持 `SelectableText`、最大高度限制与一键「复制错误日志」按钮，彻底解决内容溢出与无法选中的问题。

## Capabilities

### Modified Capabilities
- `dola-account-pool`: 完善账号探活接口协议实现与登录态校验。
- `dola-video-engine`: 完善分镜首帧依赖保护与工坊设置引擎持久化和可用性测试。

## Impact

- **Affected Code**:
  - `lib/tools/dola_pool/services/dola_probe_service.dart`
  - `lib/tools/dola_pool/ui/dola_account_pool_panel.dart`
  - `lib/tools/ai_video_studio/ui/studio_settings_dialog.dart`
  - `lib/tools/ai_video_studio/ui/storyboard_board.dart`
  - `lib/services/settings_store.dart`
