## 1. 数据模型扩展

- [x] 1.1 在 `drama_director_contract.dart` 的 `DramaBeat` 中新增 `props: List<String>`、`holdingItem: String`、`holdingHand: String` 字段及 `copyWith`
- [x] 1.2 在 `DramaBeat.toJson` 与 `DramaBeat.fromJson` 中实现新字段的序列化、反序列化与安全向后兼容
- [x] 1.3 编写或更新单元测试验证 `DramaBeat` 道具及手持字段的往返序列化

## 2. 编剧研讨室 Prompt 与约束引擎升级

- [x] 2.1 修改 `ai_constraint_engine.dart` 中的 `_promptWritersRoomMasterExtract`，增加 `key_props` 结构化提取指令与 Output JSON Schema
- [x] 2.2 修改 `_promptWritersRoomSeasonBeats`，在分集大纲条目中增加 `key_props` 字段与提取规则
- [x] 2.3 验证 `extractWritersRoomMaster` 与 `planWritersRoomSeasonBeats` 校验器能正确识别与归一化 `key_props`

## 3. 编剧研讨室 UI 与关键道具同步

- [x] 3.1 在 `writers_room_dialog.dart` 中增加 `_keyProps` 状态管理并在主线解析后正确解析存储
- [x] 3.2 在 `WritersRoomDialog` 标签页导航中新增「关键道具」面板，渲染道具卡片（名称、分类、描述、外观 Prompt）
- [x] 3.3 实现 `_syncPropsToIpMaster` 方法并绑定「一键同步关键道具到 IP 主库」按钮，批量创建并保存 `PropCard(isKeyProp: true)`
- [x] 3.4 在全季分集大纲卡片视图中渲染本集登场的关键道具 Chip 标签

## 4. 剧本工作台 Prompt 与约束引擎升级

- [x] 4.1 修改 `_promptNovelDramaChapterAdaptation`，在 `beats` 中增加 `props`、`holding_item`、`holding_hand` 提取要求与微动作化规则
- [x] 4.2 修改 `_promptScreenplayGeneration`，同样在 `beats` 中输出 `props`、`holding_item` 与 `holding_hand`
- [x] 4.3 在 `screenplay_panel.dart` 与 `novel_import_task_service.dart` 调用剧本生成前，注入当前剧集 IP 道具库的已知名称列表

## 5. 剧本工作台 UI 交互与分镜继承

- [x] 5.1 在 `screenplay_panel.dart` 节拍卡片中增加道具 Chip 展示，匹配 IP 主库道具显示已关联标记，未入库道具提供「+收录为资产」快捷按钮
- [x] 5.2 实现节拍即时道具一键收录为 `PropCard` 的交互与持久化
- [x] 5.3 升级 `ai_constraint_engine.dart` 中的 `extractDramaBeatsToShots`，根据 `beat.props` 自动模糊匹配 IP 道具并填充 `StudioShot.propIds`
- [x] 5.4 在 `extractDramaBeatsToShots` 中将 `beat.holdingItem` 与 `beat.holdingHand` 自动映射至 `ShotContinuity.holdingRight` 或 `ShotContinuity.holdingLeft`

## 6. 集成测试与应用部署验证

- [x] 6.1 运行所有相关自动化测试（`flutter test test/tools/ai_video_studio/`），确保无回归错误
- [x] 6.2 遵循工程级规范执行 `./scripts/deploy_local.sh` 重新构建并部署本机应用，验证研讨室与工作台道具完整闭环
