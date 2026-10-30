## 1. 数据模型与序列化

- [x] 1.1 在 `lib/tools/ai_video_studio/models/studio_models.dart` 中为 `CharacterVariation` 增加 `turnaroundPath` 与 `referenceImages` 字段，实现 JSON 序列化、反序列化与 copyWith。
- [x] 1.2 在 `StudioShot` 中增加 `characterVariations: Map<String, String>` 字段，支持按角色 ID 记录在该分镜选用的具体形态 ID，保持旧版 JSON 完全兼容。
- [x] 1.3 在 `CharacterTurnaroundPrompt` 中支持为形态（`CharacterVariation`）组装三视图专用提示词，将基础外观描述、形态差异词、时代锁与体态比例深度融合。

## 2. 角色卡 UI 与形态三视图脸模继承闭环

- [x] 2.1 在 `lib/tools/ai_video_studio/ui/series_page.dart` 的 `_VariationsSection` 中，为每个形态卡片增加专属三视图展示区（支持缩略图、点击查看大图、删除三视图）。
- [x] 2.2 实现形态三视图生成器：点击「生成三视图」支持选择标准比例/Q版萌系，自动提取默认 `turnaround.png` 作为 referenceImages 传递给图像适配器，输出至 `turnaround_${variation.id}.png`。
- [x] 2.3 支持将形态专属三视图一键收进资产库（自动附带 `[角色名, 形态名, 三视图, 时代]` 标签），并在删除形态时清理对应的磁盘三视图文件。

## 3. 分镜看板镜头级形态绑定与出图底图路由

- [x] 3.1 在 `lib/tools/ai_video_studio/ui/storyboard_board.dart` 的分镜卡片（`_ShotCard`）增加出场角色与形态联动选择组件，支持用户直观切换镜头中的角色形态。
- [x] 3.2 改造 `ImageGenTask._referenceImages` 路由逻辑：优先读取镜头所选形态专属的 `turnaround_${variation.id}.png`，缺失时平滑回退至默认 `turnaround.png`。
- [x] 3.3 分镜卡切换形态后，在 2 秒防抖内自动重组 Prompt，并回写至分镜数据中。

## 4. 测试验证与本地部署

- [x] 4.1 编写单元测试，覆盖 `CharacterVariation` 三视图路径解析、`StudioShot.characterVariations` 序列化向后兼容、`ImageGenTask` 动态底图路由回落逻辑。
- [x] 4.2 运行 `flutter analyze lib/tools/ai_video_studio` 与 `flutter test test/tools/ai_video_studio/` 确保零错误零失败。
- [x] 4.3 按照工程规范执行 `./scripts/deploy_local.sh` 编译并热替换本机应用。
