## 1. 数据模型与缓存击穿基座 (Data Model & Cache-Busting)

- [x] 1.1 在 `StudioShot` 中扩展 `clipStatus`（`none`, `valid`, `stale`）、`candidateFramePaths` 与 `activeFaceCharacterIds` 字段，补全 JSON 序列化、反序列化与 `copyWith`
- [x] 1.2 在 `_Thumbnail` 与 `_MediaPreviewDialog` 中为 `Image.file` 注入基于文件修改时间戳的 `ValueKey`，彻底消除 Flutter 内存图片缓存残留旧图的问题
- [x] 1.3 在 `storyboard_board.dart` 的任务持久化回调中，当重新生成关键帧成功且该分镜已存在本地视频时，自动将 `clipStatus` 置为 `stale`

## 2. 工业级规约与参考图动态收窄 (Reference Scoping & Rules)

- [x] 2.1 在 `PromptAssembler` 与 `ImageGenTask` 中净化首帧生图提示词，自动剥离五官长相修饰词并注入抗打架参照声明
- [x] 2.2 在 `ImageGenTask` 与 `VideoGenTask` 中实现 `faces` 参考图动态收窄：过肩背影与远景微小人物严禁下发人脸参考图，仅作为环境文本描述
- [x] 2.3 在 `AiConstraintEngine` 与 `DirectorValidationEngine` 中增加 Pre-flight 门禁：远景（Long Shot）禁止注入 Lip-Sync 对白口型指令，并清洗负向冲突对抗词
- [x] 2.4 在导演规划与分镜拆解规则中，识别垂直高低落差对话场景，自动规划为 A/B/C 三机位正反打镜头对（Shot-Reverse-Shot）

## 3. 分镜卡片与弹窗交互解耦 (UI Decoupling & 1-of-4 Sampling)

- [x] 3.1 改造分镜卡片 `_Thumbnail`：当视频状态为 `stale` 或关键帧更新后，优先清晰展示最新关键帧大图，并展示“视频待重构”状态角标，不再被旧视频播放图标遮蔽
- [x] 3.2 优化 `_MediaPreviewDialog`：打开弹窗时智能定向，若视频为 `stale` 或刚生成完关键帧，默认直接激活“关键帧大图”Tab 并支持顺畅缩放
- [x] 3.3 实现单镜“关键帧抽卡 (1 选 4)”交互：生成 4 张微变体首帧并在网格弹窗中展示，点击直接选定持久化为分镜主关键帧

## 4. 故事板连环画预审流 (Comic Storyboard Previs)

- [x] 4.1 在 `StoryboardBoard` 工具栏增加 `[ 标准看板 | 连环画预审 ]` 切换视图按钮
- [x] 4.2 构建 `ComicPrevisView` 横向画卷视图：以连续大图卷轴方式呈现全剧分镜首帧、景别、角色与台词，支持快速缩放走查
- [x] 4.3 提供“一键生成全片关键帧”极速批处理功能，并在连环画卷轴上实时呈现渲染进度与卡片就绪状态

## 5. 验证与本机应用构建部署 (Verification & Deployment)

- [x] 5.1 执行 `flutter test`，确保现有与新增的 Studio 测试用例全部通过
- [x] 5.2 按照工程规范执行 `./scripts/deploy_local.sh`，完成 Release 构建、二进制保留、签名并替换运行本机应用
