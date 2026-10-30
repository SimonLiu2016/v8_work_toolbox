## 1. Nuclei 周期统计流与严重度过滤参数实现

- [x] 1.1 在 `NucleiService.buildArgs` 中支持 `-stats`、`-si 5` 与 `-s <severities>` 严重度等级参数构建
- [x] 1.2 在 `NucleiService.scan` stdout 流中识别 Stats JSON 帧，格式化为友好的 `[扫描进度]` 控制台日志并触发 `onProgress` 回调
- [x] 1.3 实现健壮的 `extractHost(String input)` 静态方法，剥除 `https?://` 与端口号

## 2. 漏洞发现物资产精准归属与列表呈现

- [x] 2.1 修复 `VulnScanView` 中 `_runNuclei` 的资产关联：使用 `extractHost` 查找资产，确保端口服务（如 `:22`）能准确匹配到对应的 `PentestAsset` 并记录 `assetId`
- [x] 2.2 优化 `VulnScanView` 的 `_buildFindingList`：为每条发现物显式标注目标地址 Chip（如 `www.v8en.com:22`）并在副标题中展现目标信息，消除视觉重复
- [x] 2.3 在 `VulnScanView` 增加危险等级（Severity）多选过滤器，默认聚焦有效风险等级（Critical / High / Medium），按需勾选 Low / Info

## 3. 验证与本地应用部署

- [x] 3.1 编写针对 `extractHost`、Stats JSON 解析与 `-s` 参数生成的单元测试
- [x] 3.2 运行 `flutter analyze` 确保代码无静态警告
- [x] 3.3 运行 `flutter test` 确保全量测试通过
- [x] 3.4 执行 `./scripts/deploy_local.sh` 编译并更新本地应用
