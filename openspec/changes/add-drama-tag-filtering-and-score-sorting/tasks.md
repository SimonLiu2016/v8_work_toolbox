# 任务分解：add-drama-tag-filtering-and-score-sorting

- [x] 1. 模型与控制器层扩展
  - [x] 1.1 在 `drama_models.dart` 中定义 `DramaSortType` 枚举
  - [x] 1.2 在 `CasualShortDramaController` 中维护 `selectedTag`、`sortType` 及热门标签集
  - [x] 1.3 实现 `selectTag`、`setSortType` 与列表保序重排逻辑
- [x] 2. 界面视图层联动改造
  - [x] 2.1 在 `CasualShortDramaPage` 增加题材标签横向滚动筛选栏
  - [x] 2.2 在片库工具栏增加排序选择控件（默认、评分最高、集数最多）
  - [x] 2.3 将海报卡片上的标签改造为可点击交互胶囊并联动快速筛选
- [x] 3. 测试与验证
  - [x] 3.1 编写/更新排序与标签筛选单元测试
  - [x] 3.2 运行静态分析与全套测试（`flutter analyze`）
  - [x] 3.3 执行 `./scripts/deploy_local.sh` 编译并替换本机应用
