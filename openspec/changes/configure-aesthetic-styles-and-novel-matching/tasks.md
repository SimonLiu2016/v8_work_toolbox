## 1. 数据模型与 35 套工业级出厂预设构建

- [x] 1.1 在 `lib/tools/ai_video_studio/models/studio_models.dart` 中实现 `AestheticStyle` 数据模型（含 id, category, nameZh, descriptionZh, positiveAnchor, negativeBan, defaultRatio, isBuiltin），并支持 `toJson` / `fromJson`
- [x] 1.2 增强 `VisualEraGenre`：支持 JSON 序列化、反序列化与可编辑扩充，补充民国谍战、现代悬疑、古代宫廷、中式民俗等题材预设
- [x] 1.3 根据 `/Users/simon/Downloads/AI短剧_全量美学风格提示词库.md` 完整提取并构建 8 大体系 35 套工业级美学风格的正负向出厂预设常量

## 2. 全局预设存储管理服务 (StudioPresetStore)

- [x] 2.1 创建 `StudioPresetStore` 单例，管理全局目录下的 `aesthetic_styles.json` 与 `visual_eras.json`
- [x] 2.2 实现出厂预设自愈初始化、磁盘读写、增删改查、恢复出厂预设与 `StreamController` 广播通知机制
- [x] 2.3 在 `AppPaths` 中注册 `studioPresetsDir` 与预设文件路径，并在启动阶段完成自愈

## 3. 三层负向防崩词装配重构

- [x] 3.1 改造 `PromptAssembler` 负向提示词组装逻辑，实现 [时代排他] + [风格专属] + [通用防崩] 三层自动合并与分词去重
- [x] 3.2 验证角色三视图、场景生图、分镜关键帧及大段视频中的负向 Prompt 组装正确性

## 4. 小说长文解构动态题材与画风智能匹配

- [x] 4.1 改造 `AiConstraintEngine._promptNovelMasterExtraction`：由硬编码枚举改为从 `StudioPresetStore` 动态注入已启用的时代题材与美学风格清单
- [x] 4.2 增强解构结果解析逻辑，提取 `era_genre` 与 `aesthetic_style` 字段并兼容容错
- [x] 4.3 改造 `StudioProjectManager.importChapterToEpisode`：小说解构完成后自动绑定推荐题材与风格，并自动装配正负向词写入剧集资产

## 5. 工坊 UI 升级与预设管理中心

- [x] 5.1 重构剧集世界观面板（`_WorldviewTab`）：淘汰原 6 个硬编码写死按钮，实现按 8 大体系分类的风格选择器与时代题材选择器，支持实时正负向提示词预览与局部微调
- [x] 5.2 在工坊设置或独立管理抽屉中实现“美学与题材预设管理中心”：支持查看 35 套词库、新增自定义预设、编辑保存与重置出厂

## 6. 验证、测试与本地应用部署

- [x] 6.1 编写单元测试验证预设存储加载、出厂自愈、35套词库完整性、三层负向词合并与小说动态 Prompt 组装
- [x] 6.2 运行静态代码检查与测试套件（`flutter analyze` 与 `flutter test`）
- [x] 6.3 执行 `./scripts/deploy_local.sh` 完成本地构建、重签名并替换本机运行应用
