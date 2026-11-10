## 1. 全局品牌与命名升级

- [x] 1.1 升级 `lib/tools/registry.dart` 中的工具条目，将 `Agnes 试炼场` 更名为 `大模型试炼场`，更新多模型通用描述
- [x] 1.2 升级 `lib/main.dart` 独立子窗口标题、启动参数解析与提示文案为 `大模型试炼场`
- [x] 1.3 升级 `lib/tools/agnes_playground/ui/playground_page.dart` 顶栏 AppBar 标题、页面内文案与帮助提示
- [x] 1.4 升级 `lib/tools/ai_video_studio/` 中设置弹窗与分镜卡片右键菜单的「转入试炼场调试」相关文案

## 2. 数据模型与出厂预置资产

- [x] 2.1 创建 `VisualPromptTemplate`、`TemplateModelBenchmark` 实体类，包含分类维度、通道、占位符结构与推荐参数
- [x] 2.2 编写覆盖 5 大体系 16 个细分维度的精选出厂预置模板集合 `assets/prompt_templates/builtin_templates.json`并在 `pubspec.yaml` 中注册
- [x] 2.3 在 `lib/services/app_paths.dart` 中新增全局共享模板目录 `sharedPromptTemplatesDir` 与 `promptBenchmarksDir`

## 3. 全局存储与管理器实现

- [x] 3.1 实现 `PromptTemplateStore` 单例服务，管理模板主索引 `catalog.json` 并实现启动时出厂预置自愈合并
- [x] 3.2 实现模板的增删改查、特定模型 Benchmark 实测样片记录、1~5 星打分与标杆推荐标记
- [x] 3.3 实现本地多媒体样片文件的安全存储、关联与孤儿文件清理逻辑

## 4. 试炼场界面集成与效果库交互

- [x] 4.1 在 `playground_page.dart` 输入控制台设计并添加「提示词模板」抽屉侧边栏或唤出面板
- [x] 4.2 实现模板分类维度树、通道/关键词过滤、标签检索与瀑布流卡片展示
- [x] 4.3 在模板详情中集成模型实测样片展示器（支持图片缩放查看与 MP4 视频预览播放）
- [x] 4.4 实现「载入到控制台」动作，自动将模板内容填入输入框，并根据模型能力吸附推荐宽高比与时长

## 5. 校验与工程构建部署

- [x] 5.1 运行 `flutter analyze` 确保全工程无语法错误与类型破坏
- [x] 5.2 执行 `./scripts/deploy_local.sh` 完成 Release 构建、二进制保留、签名与替换更新本机应用
- [x] 5.3 启动验证「大模型试炼场」各入口显示、提示词模板浏览与载入流程正常
