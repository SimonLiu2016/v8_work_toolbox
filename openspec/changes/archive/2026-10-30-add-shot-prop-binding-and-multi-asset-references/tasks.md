## 1. 数据模型与绑定契约扩充

- [x] 1.1 在 `StudioShot` 中增加 `propIds: List<String>` 字段，更新 `copyWith`、`toJson` 与 `fromJson`
- [x] 1.2 在 `ShotAssetBinding` 中增加 `materialPaths: List<String>` 多图支持，保留 `materialPath` getter 实现向前兼容
- [x] 1.3 编写分镜道具与多图绑定的数据序列化与反序列化单元测试

## 2. 道具素材枚举与指代编排解析

- [x] 2.1 在 `AssetMaterialEnumerator` 中实现 `forProp`，支持枚举道具目录下存在的全部候选参考图
- [x] 2.2 扩展 `AssetBindingResolver.resolve` 与 `resolveWithGaps`，支持同时解析角色、道具与场景的多图绑定
- [x] 2.3 在 `PromptAssembler` 与 `buildVideoGenPrompt` 中注入道具素材指代（`<Picture N> = 道具名（道具）`）与视觉动作描述
- [x] 2.4 编写道具素材枚举、指代顺序编排及多图解析的单元测试

## 3. 分镜看板资产面板 UI 与多选交互重构

- [x] 3.1 在 `storyboard_board.dart` 数据层中通过 `_manager.listProps(seriesId)` 加载项目道具库并传递至看板各层级
- [x] 3.2 重构 `_ShotAssetPanel`，支持道具列表展示，并将“添加角色”与“添加道具”改造为支持自主选择实体的弹出菜单（`PopupMenuButton`）
- [x] 3.3 重构 `_AssetRow`，支持单个角色或道具绑定多张参考图（多选/复选），并与已选图片数量联动
- [x] 3.4 增强出场资产面板顶栏，实时汇总总参考图数并在超出视频模型配置上限时展示醒目的警示提示
- [x] 3.5 编写出场资产面板添加道具、自主选角色与多图绑定的 Widget 测试

## 4. 视频与关键帧生成任务流水线集成

- [x] 4.1 在 `VideoGenTask`、`KeyframeGenTask` 与 `studio_generation_tasks.dart` 中读取项目道具卡列表，确保生图与生视频时将道具图片完整传入参考图数组
- [x] 4.2 编写端到端任务装配测试，验证多角色、多道具及多参考图正确进入生成请求载荷

## 5. 综合验证与本地打包部署

- [x] 5.1 运行所有相关单元测试与 Widget 测试，确保无破坏性变更与回归
- [x] 5.2 按照工程规范执行 `./scripts/deploy_local.sh` 编译 Release、保留 mihomo、重新签名并替换本机应用
- [x] 5.3 启动更新后的应用，实测验证分镜中添加角色、添加道具、多选参考图与生成联动
