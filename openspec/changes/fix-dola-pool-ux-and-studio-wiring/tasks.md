## 1. 探活协议修正与 Cookie 获取指引

- [x] 1.1 修改 `DolaProbeService`，将探测端点改为 `POST https://www.dola.com/alice/user/get_web_anon_id` 并根据响应头 `x-tt-agw-login: 1` 判断有效性
- [x] 1.2 在 `DolaAccountPoolPanel` 导入弹窗中增加「获取 Cookie 指引」帮助折叠栏（提供一键复制 JavaScript 脚本及详细步骤指引）

## 2. 工坊设置持久化与测试分支

- [x] 2.1 在 `SettingsStore` 中添加 `studioPreferredImageEngine` 与 `studioPreferredVideoEngine` 持久化字段
- [x] 2.2 修改 `StudioSettingsDialog`，在 `_load()` 时读取持久化配置，并在引擎切换及保存时写入 `SettingsStore`
- [x] 2.3 在 `StudioSettingsDialog._test()` 中补充 `dola-pool-*` 可用性测试分支

## 3. 分镜看板错误拦截与弹窗修复

- [x] 3.1 在 `_enqueueClip(shot)` 中增加首帧关键帧是否存在的前置检查，缺失时弹出友好引导提示
- [x] 3.2 优化看板分镜卡片底部的失败信息展示，点击可展开无溢出、可复制的详细报错弹窗

## 4. 验证与本地部署

- [x] 4.1 运行相关单元测试并通过校验
- [x] 4.2 执行 `./scripts/deploy_local.sh` 重新构建并部署替换本机应用
