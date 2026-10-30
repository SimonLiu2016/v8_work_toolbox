## ADDED Requirements

### Requirement: 场景库 AI 生成图入口

系统 SHALL 在场景编辑面板提供「生成场景图」操作，接入与道具库一致的图像生成适配器。生成结果 SHALL 存储至场景专属目录，并追加至场景的 `referenceImages` 列表。

#### Scenario: 场景图 AI 生成并收进资产库

- **WHEN** 用户为场景生成 AI 参考图并点击「收进资产库」
- **THEN** 系统 SHALL 将图片以 `AssetCategory.scene` 分类收入资产库，资产库筛选器 SHALL 能按「场景」分类筛出该图
