## 1. 存储层与向下兼容性支持

- [x] 1.1 在 `AiConfigStore._initDefaults` 中添加 `'decision': <SlotCandidate>[]` 默认槽位
- [x] 1.2 在 `AiConfigStore._load` 中增加对 `decision` 槽位的缺省补齐（`putIfAbsent`），确保历史配置文件加载不报错且平滑兼容

## 2. AI 配置界面与预设联动

- [x] 2.1 在 `AiConfigPage._buildSlotsTab` 的槽位列表加入 `decision` 槽位卡片定义，配置展示文案与图标/提示
- [x] 2.2 验证槽位多候选拖拽排序、删除、添加候选及聚合健康度指示器对 `decision` 槽位正常工作
- [x] 2.3 在千问等内置快捷预设中支持预填推荐的决策/推理模型候选（如 `qwq-32b`）

## 3. 服务路由与异常防护

- [x] 3.1 确保 `AiService` 的统一路由调用支持 `slot: 'decision'`，未绑定候选时规范抛出 `SlotUnavailableException(slotName: 'decision')`

## 4. 自动化验证与部署

- [x] 4.1 编写/扩展 `ai_config_store_test.dart` 单元测试，覆盖 `decision` 槽位初始化、持久化与旧配置自动补齐
- [x] 4.2 执行单元测试确保全部通过
- [x] 4.3 执行 `./scripts/deploy_local.sh` 重新构建并替换本机应用
