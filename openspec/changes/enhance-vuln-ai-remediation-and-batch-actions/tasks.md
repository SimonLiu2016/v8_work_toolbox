## 1. 防御型提示词重构、单漏洞轻量研判与离线建议引擎

- [x] 1.1 在 `SecuritySessionController` 中实现轻量化防御型漏洞研判接口 `askFindingRemediation`，精简请求上下文与证据截断（<= 500 字符），并支持传递 `ignoreCooldown`
- [x] 1.2 实现 `OfflineRemediationAdvisor` 离线加固建议引擎，支持基于常见服务（SSH、Web、SQL 注入、已知 CVE）及严重度级别生成本地防御处置规范
- [x] 1.3 在 `SecuritySessionController` 与 `SecurityRepositories` 中支持批量更新发现物状态 `batchSetFindingStatus(List<String> ids, String status)`

## 2. 单项研判弹窗交互升级与防熔断重试机制

- [x] 2.1 将 `_AiExploitDialog` 升级为 `_AiRemediationDialog`，改用防御合规主题与展示文案
- [x] 2.2 在请求失败或超时时提供「强制重试」按钮（带 `ignoreCooldown: true`）与「查看离线防御建议」切换选项
- [x] 2.3 异常捕获与降级体验优化：在模型不可用或网络阻断时，自动展示离线兜底建议，避免界面仅留下死锁红字

## 3. 漏洞发现物多选、批量操作栏与一键全量加固清单

- [x] 3.1 在 `VulnScanView` 的 `_buildFindingList` 中为每项发现物增加 Checkbox 选择控件，并在列表上方提供「全选 / 反选 / 仅选高危」快捷操作
- [x] 3.2 实现悬浮批量操作栏：当有选中项时，提供「批量标记为：已整改 / 误报 / 已验证」
- [x] 3.3 在 `VulnScanView` 增加「一键 AI 全量加固清单」按钮与弹窗，聚合去重同类漏洞并生成全局处置报告，支持 Markdown 预览与一键复制

## 4. 单元测试、静态分析与本地应用部署

- [x] 4.1 编写针对 `OfflineRemediationAdvisor`、轻量提示词构建与批量状态修改的单元测试
- [x] 4.2 运行 `flutter analyze` 确保代码无静态检查警告与错误
- [x] 4.3 运行 `flutter test` 确保全量自动化测试通过
- [x] 4.4 执行 `./scripts/deploy_local.sh` 编译并部署本地应用
